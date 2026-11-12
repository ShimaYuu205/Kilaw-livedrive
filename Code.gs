/**
 * Kilaw Dental Clinic — Apps Script v2 (khusus export & cetak ke Drive)
 *
 * Data harian TIDAK lewat sini: itu real-time di server STB. Skrip ini hanya:
 *   - menerima file hasil export (Excel) dan cetak (PDF/PNG) dari web app lalu menaruhnya di folder Drive,
 *   - menerima cadangan harian dari STB (log-<hari>.ndjson.gz) ke storage/backup-stb,
 *   - mengirim kembali satu file bila diminta (mis. "Muat dari Excel di Drive").
 *
 * Aksi (POST JSON {token, action, data}):
 *   ping      -> status folder
 *   putfile   -> {folder, sub?, name, mime, b64}            satu file
 *   putfiles  -> {files:[{folder, sub?, name, mime, b64}]}   banyak file, SATU panggilan
 *   getfile   -> {folder, sub?, name}                        -> {b64|null, updated}
 * folder = storage | cetak | laporan   (link/ID-nya disimpan di Script Properties)
 *
 * Pasang (sekali):
 *   1. Buat 3 folder di Drive: storage, cetak, laporan. Salin link masing-masing.
 *   2. Isi blok KONFIGURASI di bawah (tempel link folder; TOKEN boleh dikosongkan = dibuat otomatis).
 *   3. Pilih fungsi aturKonfigurasi -> Run -> izinkan akses Drive. Token tampil di log eksekusi.
 *   4. KOSONGKAN lagi blok KONFIGURASI (nilainya sudah tersimpan di Script Properties).
 *   5. Deploy -> Aplikasi web: Jalankan sebagai "Saya", akses "Siapa saja". Salin URL /exec.
 *   6. Di web app: tab Sinkron -> isi URL /exec dan token -> Tes koneksi.
 *   Ubah folder/token kapan saja lewat Project Settings -> Script Properties
 *   (kunci: TOKEN, FOLDER_STORAGE, FOLDER_CETAK, FOLDER_LAPORAN), tanpa deploy ulang.
 */

// ===== KONFIGURASI: isi lalu jalankan aturKonfigurasi(), setelah itu kosongkan lagi =====
var KONFIGURASI = {
  TOKEN: '',            // kosong = dibuat otomatis (atau tetap memakai yang sudah tersimpan)
  FOLDER_STORAGE: '',   // https://drive.google.com/drive/folders/XXXXXXXX
  FOLDER_CETAK: '',
  FOLDER_LAPORAN: ''
};

var FOLDER_PROP = { storage: 'FOLDER_STORAGE', cetak: 'FOLDER_CETAK', laporan: 'FOLDER_LAPORAN' };
var MAX_BODY = 45 * 1000 * 1000;   // karakter badan permintaan; client membatasi ±8 MB per panggilan

// ---------- pengaturan (dijalankan manual dari editor) ----------
function aturKonfigurasi() {
  var props = PropertiesService.getScriptProperties(), log = [];
  Object.keys(FOLDER_PROP).forEach(function (n) {
    var key = FOLDER_PROP[n], v = String(KONFIGURASI[key] || '').trim();
    if (!v) return;
    var id = folderId_(v);
    if (!id) throw new Error(key + ': bukan link/ID folder Drive yang valid.');
    var nama = DriveApp.getFolderById(id).getName();            // gagal di sini bila tidak punya akses
    props.setProperty(key, v); log.push(key + ' = "' + nama + '"');
  });
  var tok = String(KONFIGURASI.TOKEN || '').trim();
  if (!tok && !props.getProperty('TOKEN')) tok = tokenBaru_();
  if (tok) {
    if (tok.length < 16) throw new Error('TOKEN minimal 16 karakter.');
    props.setProperty('TOKEN', tok); log.push('TOKEN tersimpan: ' + tok);
  }
  Logger.log(log.join('\n') + '\n\nSelesai. Kosongkan blok KONFIGURASI, lalu Deploy -> Aplikasi web.');
}

function buatTokenBaru() {          // ganti token (isi ulang di tiap HP dan di STB bila memakai cadangan Drive)
  var tok = tokenBaru_();
  PropertiesService.getScriptProperties().setProperty('TOKEN', tok);
  Logger.log('TOKEN baru: ' + tok);
}

function cekKonfigurasi() {
  var props = PropertiesService.getScriptProperties(), tok = props.getProperty('TOKEN') || '';
  var out = ['TOKEN: ' + (tok.length >= 16 ? 'ada (' + tok.slice(0, 4) + '…, ' + tok.length + ' karakter)' : 'BELUM DIATUR')];
  Object.keys(FOLDER_PROP).forEach(function (n) {
    var st; try { st = '"' + folder_(n).getName() + '"'; } catch (e) { st = 'MASALAH: ' + e.message; }
    out.push(FOLDER_PROP[n] + ': ' + st);
  });
  Logger.log(out.join('\n'));
}

// ---------- web app ----------
function doGet() { return out_({ ok: true, info: 'Kilaw Apps Script v2 aktif.' }); }

function doPost(e) {
  try {
    var body = (e && e.postData && e.postData.contents) || '';
    if (!body) return out_({ ok: false, error: 'Permintaan kosong.' });
    if (body.length > MAX_BODY) return out_({ ok: false, error: 'Permintaan terlalu besar; kirim lebih sedikit file sekaligus.' });
    var req = JSON.parse(body);
    if (!tokenOk_(req.token)) { Utilities.sleep(800); return out_({ ok: false, error: 'Token salah.' }); }
    var d = req.data || {};
    switch (req.action) {
      case 'ping': return out_(ping_());
      case 'putfile': return out_(locked_(function () { return { ok: true, saved: [save_(d)] }; }));
      case 'putfiles': return out_(locked_(function () {
        var list = d.files || [];
        if (!list.length) throw new Error('Daftar file kosong.');
        return { ok: true, saved: list.map(save_) };
      }));
      case 'getfile': return out_(get_(d));
      default: return out_({ ok: false, error: 'Aksi tidak dikenal: ' + req.action });
    }
  } catch (err) {
    return out_({ ok: false, error: String((err && err.message) || err) });
  }
}

// ---------- inti ----------
function ping_() {
  var f = {};
  Object.keys(FOLDER_PROP).forEach(function (n) { try { f[n] = folder_(n).getName(); } catch (e) { f[n] = ''; } });
  return { ok: true, v: 2, folders: f };
}

// Simpan satu file. Nama sama = diganti: file baru dibuat dulu, baru yang lama dibuang ke tong sampah Drive
// (bisa dipulihkan 30 hari), jadi gagal di tengah jalan tidak menghilangkan file lama.
function save_(f) {
  var name = clean_(f && f.name);
  if (!name) throw new Error('Nama file kosong.');
  if (!f.b64) throw new Error('Isi file kosong: ' + name);
  var dir = sub_(folder_(f.folder), f.sub), old = [], it = dir.getFilesByName(name);
  while (it.hasNext()) old.push(it.next());
  var blob = Utilities.newBlob(Utilities.base64Decode(f.b64), f.mime || 'application/octet-stream', name);
  var file = dir.createFile(blob);
  old.forEach(function (o) { o.setTrashed(true); });
  return { name: name, id: file.getId(), size: file.getSize() };
}

function get_(d) {
  var dir = sub_(folder_(d.folder), d.sub, true);
  if (!dir) return { ok: true, b64: null };
  var it = dir.getFilesByName(clean_(d.name)), best = null;
  while (it.hasNext()) { var f = it.next(); if (!best || f.getLastUpdated() > best.getLastUpdated()) best = f; }
  if (!best) return { ok: true, b64: null };
  return { ok: true, b64: Utilities.base64Encode(best.getBlob().getBytes()), updated: best.getLastUpdated().getTime() };
}

// ---------- pembantu ----------
function folder_(name) {
  var key = FOLDER_PROP[String(name || '').toLowerCase()];
  if (!key) throw new Error('Folder tidak dikenal: "' + name + '" (pakai storage, cetak, atau laporan).');
  var v = PropertiesService.getScriptProperties().getProperty(key);
  if (!v) throw new Error('Script Property ' + key + ' belum diisi. Jalankan aturKonfigurasi().');
  var id = folderId_(v);
  if (!id) throw new Error(key + ' bukan link/ID folder yang valid.');
  return DriveApp.getFolderById(id);
}

function sub_(parent, sub, noCreate) {
  sub = clean_(sub);
  if (!sub) return parent;
  var it = parent.getFoldersByName(sub);
  if (it.hasNext()) return it.next();
  return noCreate ? null : parent.createFolder(sub);
}

function folderId_(v) {
  v = String(v || '').trim();
  var m = v.match(/\/folders\/([A-Za-z0-9_-]+)/) || v.match(/[?&]id=([A-Za-z0-9_-]+)/);
  if (m) return m[1];
  return /^[A-Za-z0-9_-]{10,}$/.test(v) ? v : '';
}

function clean_(s) {
  return String(s || '').replace(/[\\\/\u0000-\u001f<>:"|?*]/g, '_').replace(/^\.+/, '').trim().slice(0, 120);
}

function tokenOk_(t) {
  var real = PropertiesService.getScriptProperties().getProperty('TOKEN') || '';
  if (real.length < 16) return false;                       // token belum diatur: tolak semua
  t = String(t || '');
  var diff = real.length ^ t.length;                        // perbandingan waktu-tetap
  for (var i = 0; i < real.length; i++) diff |= real.charCodeAt(i) ^ (t.charCodeAt(i) || 0);
  return diff === 0;
}

function tokenBaru_() { return (Utilities.getUuid() + Utilities.getUuid()).replace(/-/g, ''); }

// Satu penulis pada satu waktu: percobaan ulang dari HP (jaringan putus-sambung) tidak membuat salinan ganda.
function locked_(fn) {
  var lock = LockService.getScriptLock();
  lock.waitLock(25000);
  try { return fn(); } finally { lock.releaseLock(); }
}

function out_(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);
}
