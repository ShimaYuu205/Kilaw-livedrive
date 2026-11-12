/* Kilaw Sync Server — Node murni, tanpa dependensi (aman untuk STB ARM).
 * - Menyimpan data per "koleksi" (pasien, entry, ...) sebagai catatan kunci -> JSON.
 * - Perubahan dikirim ke semua perangkat lewat SSE (real-time); perangkat yang offline mengejar lewat /api/sync.
 * - Penyimpanan: log append-only (data/log.ndjson) + snapshot otomatis + cadangan harian.
 * - Opsional: cadangan harian log.ndjson.gz ke Google Drive lewat Apps Script (APPSCRIPT_URL + APPSCRIPT_TOKEN), tanpa rclone.
 * Jalankan:  KILAW_TOKEN=rahasia-panjang node server.js
 */
'use strict';
const http = require('http'), fs = require('fs'), path = require('path'), zlib = require('zlib'), crypto = require('crypto');

const PORT = +process.env.PORT || 8787;
const HOST = process.env.HOST || '127.0.0.1';           // di belakang tunnel: biarkan 127.0.0.1
const TOKEN = process.env.KILAW_TOKEN || '';
const DATA = path.resolve(process.env.DATA_DIR || path.join(__dirname, 'data'));
const PUB = path.resolve(process.env.PUBLIC_DIR || path.join(__dirname, 'public'));
const KEEP_BACKUPS = +process.env.KEEP_BACKUPS || 14;
const APPS_URL = process.env.APPSCRIPT_URL || '', APPS_TOKEN = process.env.APPSCRIPT_TOKEN || '';   // opsional: cadangan ke Drive
const MAX_BODY = 25 * 1024 * 1024, MAX_REC = 2 * 1024 * 1024, PAGE = 3000;
const COLS = new Set(['pasien', 'entry', 'prospek', 'gigi', 'stok', 'mutasi', 'beli', 'consent', 'antrian', 'dokter']);

if (TOKEN.length < 12) { console.error('KILAW_TOKEN wajib diisi, minimal 12 karakter.'); process.exit(1); }
fs.mkdirSync(DATA, { recursive: true }); fs.mkdirSync(path.join(DATA, 'backup'), { recursive: true }); fs.mkdirSync(PUB, { recursive: true });
const LOGF = path.join(DATA, 'log.ndjson');

// ---------- state ----------
const state = new Map();            // "c\0k" -> { s, c, k, j (JSON string atau 'null' = dihapus), dev }
let seq = 0, logFd = null, dirty = false, logLines = 0;

function load() {
  if (!fs.existsSync(LOGF)) return;
  const txt = fs.readFileSync(LOGF, 'utf8'); let bad = 0;
  for (const line of txt.split('\n')) {
    if (!line) continue;
    try { const r = JSON.parse(line); state.set(r.c + '\0' + r.k, { s: r.s, c: r.c, k: r.k, j: r.j, dev: r.dev || '' }); if (r.s > seq) seq = r.s; logLines++; } catch (e) { bad++; }
  }
  console.log('Dimuat:', state.size, 'catatan, seq', seq, bad ? '(baris rusak dilewati: ' + bad + ')' : '');
}
const lineOf = (r) => JSON.stringify({ s: r.s, c: r.c, k: r.k, j: r.j, dev: r.dev }) + '\n';
function openLog() { logFd = fs.openSync(LOGF, 'a'); }
function compact() {            // tulis ulang hanya keadaan terakhir (atomik via rename)
  const tmp = LOGF + '.tmp', fd = fs.openSync(tmp, 'w');
  for (const r of [...state.values()].sort((a, b) => a.s - b.s)) fs.writeSync(fd, lineOf(r));
  fs.fsyncSync(fd); fs.closeSync(fd);
  if (logFd !== null) fs.closeSync(logFd);
  fs.renameSync(tmp, LOGF); openLog(); logLines = state.size; console.log('Log dipadatkan:', state.size, 'catatan');
}
function backupDaily() {
  const f = path.join(DATA, 'backup', 'log-' + new Date().toISOString().slice(0, 10) + '.ndjson');
  try {
    if (!fs.existsSync(f) && fs.existsSync(LOGF)) {
      fs.copyFileSync(LOGF, f);
      const all = fs.readdirSync(path.join(DATA, 'backup')).filter((x) => x.startsWith('log-')).sort();
      all.slice(0, Math.max(0, all.length - KEEP_BACKUPS)).forEach((x) => fs.unlinkSync(path.join(DATA, 'backup', x)));
      console.log('Cadangan harian dibuat:', path.basename(f));
    }
  } catch (e) { console.error('Cadangan gagal:', e.message); }
}
// Cadangan ke Drive (opsional): sekali sehari setelah jam 02:00 waktu STB, satu file per hari-dalam-minggu (menimpa minggu lalu).
const HARI = ['minggu', 'senin', 'selasa', 'rabu', 'kamis', 'jumat', 'sabtu'], DRIVE_MARK = path.join(DATA, 'backup', '.drive-last');
async function backupDrive() {
  if (!APPS_URL || !APPS_TOKEN || typeof fetch !== 'function') return;
  const d = new Date(), pad = (n) => String(n).padStart(2, '0'), today = d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate());
  if (d.getHours() < 2) return;
  try { if (fs.readFileSync(DRIVE_MARK, 'utf8').trim() === today) return; } catch (e) { /* belum pernah */ }
  try {
    const gz = zlib.gzipSync(fs.readFileSync(LOGF), { level: 9 });
    const r = await fetch(APPS_URL, { method: 'POST', body: JSON.stringify({ token: APPS_TOKEN, action: 'putfile', data: { folder: 'storage', sub: 'backup-stb', name: 'log-' + HARI[d.getDay()] + '.ndjson.gz', mime: 'application/gzip', b64: gz.toString('base64') } }), signal: AbortSignal.timeout(120000) });
    const j = await r.json();
    if (!j.ok) throw new Error(j.error || 'ditolak Apps Script');
    fs.writeFileSync(DRIVE_MARK, today); console.log('Cadangan Drive terkirim:', 'log-' + HARI[d.getDay()] + '.ndjson.gz', Math.round(gz.length / 1024) + ' KB');
  } catch (e) { console.error('Cadangan Drive gagal (dicoba lagi jam berikutnya):', e.message); }
}
load(); openLog(); backupDaily(); setTimeout(backupDrive, 60000);
if (logLines > state.size * 3 + 2000) compact();
setInterval(() => { if (dirty) { try { fs.fsyncSync(logFd); dirty = false; } catch (e) { /* abaikan */ } } }, 4000);
setInterval(() => { backupDaily(); backupDrive(); if (logLines > state.size * 3 + 2000) compact(); }, 3600 * 1000);

// ---------- operasi ----------
// op: { c, k, d (objek | null), nb (true bila perangkat belum punya versi sebelumnya) }
function applyOps(ops, dev) {
  const changed = [], conflicts = []; let lines = '';
  for (const op of ops) {
    if (!op || !COLS.has(op.c) || typeof op.k !== 'string' || !op.k || op.k.length > 200) continue;
    const j = op.d === null ? 'null' : (op.d && typeof op.d === 'object' ? JSON.stringify(op.d) : null);
    if (j === null || j.length > MAX_REC) continue;
    const key = op.c + '\0' + op.k, cur = state.get(key);
    if (cur && cur.j === j) continue;                                  // sama persis: abaikan
    if (!cur && j === 'null') continue;                                // hapus sesuatu yang tak ada
    if (op.nb && cur && cur.j !== 'null' && j !== 'null') { conflicts.push({ c: op.c, k: op.k }); continue; }  // dua perangkat membuat kunci yang sama
    const r = { s: ++seq, c: op.c, k: op.k, j: j, dev: dev };
    state.set(key, r); changed.push(r); lines += lineOf(r); logLines++;
  }
  if (lines) { fs.writeSync(logFd, lines); dirty = true; }
  return { changed, conflicts };
}
const chJson = (r) => '{"s":' + r.s + ',"c":' + JSON.stringify(r.c) + ',"k":' + JSON.stringify(r.k) + ',"d":' + r.j + ',"dev":' + JSON.stringify(r.dev) + '}';
function since(n, limit) {
  const arr = []; for (const r of state.values()) if (r.s > n) arr.push(r);
  arr.sort((a, b) => a.s - b.s); const more = arr.length > limit;
  return { list: more ? arr.slice(0, limit) : arr, more: more };
}

// ---------- SSE ----------
const clients = new Set();
function broadcast(changed, fromDev) {
  if (!changed.length) return;
  const body = 'event: ch\ndata: {"seq":' + seq + ',"ch":[' + changed.map(chJson).join(',') + ']}\n\n';
  for (const c of clients) if (c.dev !== fromDev) { try { c.res.write(body); } catch (e) { clients.delete(c); } }
}
setInterval(() => { for (const c of clients) { try { c.res.write('event: hb\ndata: 1\n\n'); } catch (e) { clients.delete(c); } } }, 20000);

// ---------- HTTP ----------
const fails = new Map();
const ipOf = (req) => String(req.headers['cf-connecting-ip'] || req.headers['x-forwarded-for'] || req.socket.remoteAddress || '').split(',')[0].trim();
function okToken(t) {
  const a = Buffer.from(String(t || '')), b = Buffer.from(TOKEN);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}
function authed(req, url, res) {
  const ip = ipOf(req), f = fails.get(ip) || { n: 0, t: Date.now() };
  if (Date.now() - f.t > 60000) { f.n = 0; f.t = Date.now(); }
  if (f.n >= 20) { send(req, res, 429, { ok: false, error: 'Terlalu banyak percobaan. Tunggu semenit.' }); return false; }
  const h = String(req.headers.authorization || '').replace(/^Bearer\s+/i, '');
  if (okToken(h) || okToken(url.searchParams.get('token'))) return true;
  f.n++; fails.set(ip, f); send(req, res, 401, { ok: false, error: 'Token salah.' }); return false;
}
const CORS = { 'Access-Control-Allow-Origin': process.env.ALLOW_ORIGIN || '*', 'Access-Control-Allow-Headers': 'Authorization, Content-Type', 'Access-Control-Allow-Methods': 'GET, POST, OPTIONS', 'Access-Control-Max-Age': '86400' };
function send(req, res, code, obj, raw) {
  const body = raw !== undefined ? raw : JSON.stringify(obj), h = Object.assign({ 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' }, CORS);
  if (body.length > 2048 && /gzip/.test(req.headers['accept-encoding'] || '')) {
    h['Content-Encoding'] = 'gzip'; res.writeHead(code, h); return res.end(zlib.gzipSync(body, { level: 5 }));
  }
  res.writeHead(code, h); res.end(body);
}
function readBody(req) {
  return new Promise((resolve, reject) => {
    let n = 0; const parts = [];
    req.on('data', (c) => { n += c.length; if (n > MAX_BODY) { reject(new Error('Terlalu besar')); req.destroy(); } else parts.push(c); });
    req.on('end', () => resolve(Buffer.concat(parts).toString('utf8'))); req.on('error', reject);
  });
}
const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.json': 'application/json', '.png': 'image/png', '.svg': 'image/svg+xml', '.ico': 'image/x-icon', '.webmanifest': 'application/manifest+json' };
const staticCache = new Map();      // path -> { etag, raw, gz }  (gzip dibuat sekali, bukan tiap permintaan)
function serveStatic(req, res, pathname) {
  let rel = decodeURIComponent(pathname); if (rel === '/' || rel === '') rel = '/index.html';
  const f = path.normalize(path.join(PUB, rel));
  if (!f.startsWith(PUB + path.sep) && f !== PUB) { res.writeHead(403); return res.end('Dilarang'); }
  fs.stat(f, (e, st) => {
    if (e || !st.isFile()) { res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' }); return res.end('Tidak ditemukan'); }
    const type = MIME[path.extname(f).toLowerCase()] || 'application/octet-stream', etag = '"' + st.size.toString(16) + '-' + Math.floor(st.mtimeMs).toString(16) + '"';
    const h = { 'Content-Type': type, 'Cache-Control': 'no-cache', ETag: etag, Vary: 'Accept-Encoding' };
    if (req.headers['if-none-match'] === etag) { res.writeHead(304, h); return res.end(); }
    let c = staticCache.get(f);
    const done = () => {
      if (c.gz && /gzip/.test(req.headers['accept-encoding'] || '')) { h['Content-Encoding'] = 'gzip'; h['Content-Length'] = c.gz.length; res.writeHead(200, h); return res.end(c.gz); }
      h['Content-Length'] = c.raw.length; res.writeHead(200, h); res.end(c.raw);
    };
    if (c && c.etag === etag) return done();
    fs.readFile(f, (er, raw) => {
      if (er) { res.writeHead(500); return res.end('Gagal membaca'); }
      c = { etag: etag, raw: raw, gz: /^text\/|json|svg/.test(type) ? zlib.gzipSync(raw, { level: 9 }) : null }; staticCache.set(f, c); done();
    });
  });
}

http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url, 'http://x'), p = url.pathname;
    if (req.method === 'OPTIONS') { res.writeHead(204, CORS); return res.end(); }
    if (p === '/api/ping' && req.method === 'GET') { if (!authed(req, url, res)) return; return send(req, res, 200, { ok: true, seq: seq, n: state.size, t: Date.now() }); }
    if (p === '/api/stats' && req.method === 'GET') {
      if (!authed(req, url, res)) return; const out = {}; for (const r of state.values()) if (r.j !== 'null') out[r.c] = (out[r.c] || 0) + 1;
      return send(req, res, 200, { ok: true, seq: seq, koleksi: out, klien: clients.size });
    }
    if (p === '/api/stream' && req.method === 'GET') {
      if (!authed(req, url, res)) return;
      res.writeHead(200, Object.assign({ 'Content-Type': 'text/event-stream; charset=utf-8', 'Cache-Control': 'no-cache, no-transform', Connection: 'keep-alive', 'X-Accel-Buffering': 'no' }, CORS));
      res.write('retry: 3000\n: terhubung\n\n');
      const c = { res: res, dev: String(url.searchParams.get('dev') || '').slice(0, 64) }; clients.add(c);
      req.on('close', () => clients.delete(c)); return;
    }
    if (p === '/api/sync' && req.method === 'POST') {
      if (!authed(req, url, res)) return;
      let b; try { b = JSON.parse(await readBody(req)); } catch (e) { return send(req, res, 400, { ok: false, error: 'JSON tidak valid.' }); }
      const dev = String(b.dev || '').slice(0, 64), ops = Array.isArray(b.ops) ? b.ops : [];
      const { changed, conflicts } = applyOps(ops, dev); broadcast(changed, dev);
      const limit = Math.min(+b.limit || PAGE, PAGE), page = since(+b.since || 0, limit);
      const mine = new Set(changed.map((r) => r.s));
      const extra = (Array.isArray(b.get) ? b.get.slice(0, 50) : []).map((g) => state.get(String(g.c) + '\0' + String(g.k))).filter(Boolean);
      const list = page.list.filter((r) => !mine.has(r.s)); extra.forEach((r) => { if (!list.includes(r)) list.push(r); });
      return send(req, res, 200, null, '{"ok":true,"seq":' + seq + ',"applied":' + changed.length + ',"conflicts":' + JSON.stringify(conflicts) + ',"more":' + page.more + ',"changes":[' + list.map(chJson).join(',') + '],"upto":' + (page.list.length ? page.list[page.list.length - 1].s : (+b.since || 0)) + '}');
    }
    if (p.startsWith('/api/')) return send(req, res, 404, { ok: false, error: 'Tidak ada.' });
    if (req.method === 'GET') return serveStatic(req, res, p);
    res.writeHead(405); res.end();
  } catch (e) { console.error(e); try { send(req, res, 500, { ok: false, error: 'Kesalahan server.' }); } catch (x) { /* abaikan */ } }
}).listen(PORT, HOST, () => console.log('Kilaw Sync Server di http://' + HOST + ':' + PORT + ' — data: ' + DATA + ' — web: ' + PUB));

function shutdown() { try { fs.fsyncSync(logFd); } catch (e) { /* abaikan */ } process.exit(0); }
process.on('SIGINT', shutdown); process.on('SIGTERM', shutdown);

