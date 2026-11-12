/* Kilaw Sync (klien) — sinkron real-time ke server mini (STB). Dimuat SETELAH app.js.
 * Prinsip: hanya catatan yang berubah yang dikirim (bukan seluruh file); perubahan perangkat lain masuk lewat SSE.
 * Data tetap utuh di HP (offline aman); begitu tersambung, perubahan terkirim & terambil otomatis.
 */
(function () {
  'use strict';
  var R = window.KilawRM, N = window.KilawNote, C = window.KilawConsent, Q = window.KilawQ, D = window.KilawDokterSync;
  if (!R || !N || !C || !Q) return;

  var CFG_KEY = 'kilaw_server', DEV_KEY = 'kilaw_dev', CHUNK_COUNT = 300, CHUNK_BYTES = 1500000;
  var cfg = {}; try { cfg = JSON.parse(localStorage.getItem(CFG_KEY) || 'null') || {}; } catch (e) { cfg = {}; }
  var dev = localStorage.getItem(DEV_KEY);
  if (!dev) { dev = 'd' + Math.random().toString(36).slice(2, 9) + Date.now().toString(36).slice(-4); try { localStorage.setItem(DEV_KEY, dev); } catch (e) { /* abaikan */ } }

  // ---------- koleksi ----------
  var noteGet = function (n) { return function () { return N.getAll()[n]; }; };
  var noteSet = function (n) { return function (a) { var o = {}; o[n] = a; N.setAll(o); }; };
  var byId = function (r) { return r && r.id ? String(r.id) : ''; };
  var COLS = {
    pasien: { key: function (p) { return p && p.noFile != null ? String(p.noFile) : ''; }, get: function () { return R.getPasien(); }, set: function (a) { R.replaceAll(a, null); } },
    entry: { key: byId, get: function () { return R.getEntry(); }, set: function (a) { R.replaceAll(null, a); } },
    prospek: { key: byId, get: noteGet('prospek'), set: noteSet('prospek') },
    gigi: { key: byId, get: noteGet('gigi'), set: noteSet('gigi') },
    stok: { key: byId, get: noteGet('stok'), set: noteSet('stok') },
    mutasi: { key: byId, get: noteGet('mutasi'), set: noteSet('mutasi') },
    beli: { key: byId, get: noteGet('beli'), set: noteSet('beli') },
    consent: { key: function (c) { return c && c.rm != null ? String(c.rm) : ''; }, get: function () { return C.list(); }, set: function (a) { C.replace(a); } },
    antrian: { key: byId, get: function () { return Q.get().items; }, set: function (a) { Q.setItems(a); } }
  };
  if (D) COLS.dokter = { key: byId, get: D.get, set: D.set };      // daftar dokter + tanda tangan ikut sinkron
  var DIRTY = { db_data_pasien: 'pasien', db_entry_harian: 'entry', kilawnote_prospek_wa: 'prospek', kilawnote_gigi_tiruan: 'gigi', kilawnote_stok_obat: 'stok', kilawnote_mutasi_stok: 'mutasi', kilawnote_beli_list: 'beli', consent: 'consent', antrian: 'antrian', dokter: 'dokter' };

  // Data contoh bawaan aplikasi (muncul di perangkat baru yang masih kosong) tidak boleh ikut terkirim ke server.
  function onlySample(name, arr) {
    if (!arr || arr.length !== 1) return false; var r = arr[0];
    if (name === 'pasien') return r.noFile === '1258' && r.nama === 'Ika Novytasari' && r.telp === '089699617944';
    if (name === 'entry') return r.noFile === '1258' && r.nama === 'Ika Novytasari' && r.perawatan === 'Devit + Ts' && r.tanggal === '12/09/26';
    return false;
  }
  function h32(s) { var h = 2166136261; for (var i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 16777619); } return h >>> 0; }

  // ---------- penyimpanan state (IndexedDB: tidak membebani kuota localStorage) ----------
  var memKV = {};
  function idb() {
    return new Promise(function (res, rej) {
      if (!window.indexedDB) return rej(new Error('no idb'));
      var r = indexedDB.open('kilaw_sync', 1);
      r.onupgradeneeded = function () { r.result.createObjectStore('kv'); };
      r.onsuccess = function () { res(r.result); }; r.onerror = function () { rej(r.error); };
    });
  }
  function kvGet(k) { return idb().then(function (db) { return new Promise(function (res) { var q = db.transaction('kv').objectStore('kv').get(k); q.onsuccess = function () { res(q.result); }; q.onerror = function () { res(undefined); }; }); }).catch(function () { return memKV[k]; }); }
  function kvSet(k, v) { memKV[k] = v; return idb().then(function (db) { return new Promise(function (res) { var t = db.transaction('kv', 'readwrite'); t.objectStore('kv').put(v, k); t.oncomplete = function () { res(); }; t.onerror = function () { res(); }; }); }).catch(function () { /* memori saja */ }); }

  // ---------- state sinkron ----------
  var since = 0, base = {}, first = true, dirty = {}, applying = false, busy = false, again = false, ready = false;
  var status = 'off', lastOk = 0, backoff = 1000, retryT = null, pushT = null, persistT = null, es = null, esRetry = null, remoteQ = [], remoteT = null, conflicts = [], msg = '';
  var origin = function () { return String(cfg.url || '').replace(/\/+$/, ''); };
  var configured = function () { return !!(origin() && cfg.token); };

  function persist(now) {
    clearTimeout(persistT);
    var run = function () { kvSet('state', { since: since, base: base }); };
    if (now) run(); else persistT = setTimeout(run, 3000);
  }

  // ---------- diff lokal -> operasi ----------
  function collectOps(names) {
    var ops = [];
    names.forEach(function (name) {
      var col = COLS[name], arr = col.get() || [], b = base[name] || (base[name] = {}), seen = Object.create(null);
      if (onlySample(name, arr)) arr = [];
      for (var i = 0; i < arr.length; i++) {
        var rec = arr[i], k = col.key(rec); if (!k || seen[k]) continue; seen[k] = 1;
        var j = JSON.stringify(rec), h = h32(j);
        if (b[k] !== h) ops.push({ c: name, k: k, j: j, h: h, nb: b[k] === undefined });
      }
      for (var k2 in b) if (!seen[k2]) ops.push({ c: name, k: k2, j: 'null', h: 0, del: true });
    });
    return ops;
  }
  function chunkOf(ops, i) {
    var out = [], bytes = 0;
    while (i < ops.length && out.length < CHUNK_COUNT && (bytes < CHUNK_BYTES || !out.length)) { bytes += ops[i].j.length; out.push(ops[i]); i++; }
    return out;
  }
  var bodyOf = function (chunk, limit) {
    return '{"dev":' + JSON.stringify(dev) + ',"since":' + since + ',"limit":' + limit + (conflictGet.length ? ',"get":' + JSON.stringify(conflictGet.splice(0, 50)) : '') +
      ',"ops":[' + chunk.map(function (o) { return '{"c":' + JSON.stringify(o.c) + ',"k":' + JSON.stringify(o.k) + ',"d":' + o.j + (o.nb ? ',"nb":true' : '') + '}'; }).join(',') + ']}';
  };
  var conflictGet = [];

  // ---------- jaringan ----------
  var authErr = new Error('Token salah'); authErr.auth = true;
  function post(chunk) {
    var ctl = typeof AbortController === 'function' ? new AbortController() : null, t = setTimeout(function () { if (ctl) ctl.abort(); }, 40000);
    return fetch(origin() + '/api/sync', { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + cfg.token }, body: bodyOf(chunk, 3000), signal: ctl ? ctl.signal : undefined })
      .then(function (r) { clearTimeout(t); if (r.status === 401) throw authErr; if (!r.ok) throw new Error('HTTP ' + r.status); return r.json(); },
        function (e) { clearTimeout(t); throw e; });
  }

  // ---------- terapkan perubahan dari perangkat lain ----------
  function applyRemote(changes) {
    var by = {}, touched = false;
    changes.forEach(function (ch) { if (ch.dev === dev || !COLS[ch.c]) return; (by[ch.c] || (by[ch.c] = [])).push(ch); });
    Object.keys(by).forEach(function (name) {
      var col = COLS[name], b = base[name] || (base[name] = {}), cur0 = col.get() || [], copy = onlySample(name, cur0) ? [] : cur0.slice(), index = Object.create(null), changed = copy.length !== cur0.length;
      copy.forEach(function (r, i) { var k = col.key(r); if (k && index[k] === undefined) index[k] = i; });
      by[name].forEach(function (ch) {
        var k = ch.k, i = index[k], cur = i !== undefined ? copy[i] : undefined, hin = ch.d === null ? 0 : h32(JSON.stringify(ch.d));
        if (b[k] === hin) return;                                                         // sudah sama
        if (cur !== undefined && b[k] !== undefined && h32(JSON.stringify(cur)) !== b[k]) return;  // ada ubahan lokal belum terkirim: lokal menang
        if (ch.d === null) { if (cur !== undefined) { copy[i] = null; changed = true; } delete b[k]; }
        else { if (cur === undefined) { index[k] = copy.length; copy.push(ch.d); } else copy[i] = ch.d; b[k] = hin; changed = true; }
      });
      if (changed) {
        applying = true;
        try { col.set(copy.filter(function (x) { return x !== null; })); } catch (e) { console.error('sync apply', name, e); } finally { applying = false; }
        touched = true;
      }
    });
    if (touched) { persist(); try { window.dispatchEvent(new CustomEvent('kilaw-remote')); } catch (e) { /* abaikan */ } }
    return touched;
  }

  // ---------- satu siklus sinkron ----------
  function afterPush(chunk, r) {
    var bad = Object.create(null); (r.conflicts || []).forEach(function (c) { bad[c.c + '\0' + c.k] = 1; });
    chunk.forEach(function (o) {
      var b = base[o.c] || (base[o.c] = {});
      if (bad[o.c + '\0' + o.k]) {                                    // dua perangkat membuat kunci sama (mis. No RM kembar)
        var col = COLS[o.c], rec = (col.get() || []).filter(function (x) { return col.key(x) === o.k; })[0];
        if (rec) conflicts.push({ c: o.c, k: o.k, d: rec, t: Date.now() });
        conflictGet.push({ c: o.c, k: o.k });
      } else if (o.del) delete b[o.k]; else b[o.k] = o.h;
    });
    if ((r.conflicts || []).length) { kvSet('conflicts', conflicts); msg = r.conflicts.length + ' data bentrok (kunci sama dibuat di perangkat lain). Versi server dipakai; versi Anda disimpan di daftar Bentrok.'; if (N.toast) N.toast(msg, 'warn'); }
  }
  async function pull(chunk) {
    var r = await post(chunk); afterPush(chunk, r);
    applyRemote(r.changes || []); since = r.more ? r.upto : r.seq; return r;
  }
  async function cycle() {
    if (first) { var r0; do { r0 = await pull([]); } while (r0.more); }                                  // 1) ambil dulu semua dari server
    var names = first ? Object.keys(COLS) : Object.keys(dirty); dirty = {};
    try {
      var ops = collectOps(names), i = 0, r;
      while (i < ops.length) { var chunk = chunkOf(ops, i); i += chunk.length; r = await pull(chunk); setStatus('sync'); }  // 2) kirim yang berubah
      if (conflictGet.length) { r = await pull([]); }                                                      // ambil versi server untuk yang bentrok
      do { r = await pull([]); } while (r.more);                                                           // 3) kejar sisa
      first = false;
    } catch (e) { names.forEach(function (n) { dirty[n] = true; }); throw e; }                            // gagal: ulangi nanti, jangan hilang
    if (conflictGet.length === 0 && conflicts.length) paintPanel();
    persist(true);
  }
  async function sync() {
    if (!configured()) return setStatus('off');
    if (busy) { again = true; return; }
    busy = true; setStatus('sync');
    try {
      do { again = false; await cycle(); } while (again || Object.keys(dirty).length);
      backoff = 1000; lastOk = Date.now(); setStatus('on'); if (!es) openStream();
    } catch (e) {
      if (e.auth) { setStatus('auth'); } else { setStatus('off'); retryT = setTimeout(sync, backoff); backoff = Math.min(30000, backoff * 2); }
    } finally { busy = false; }
  }
  function schedulePush() { clearTimeout(pushT); pushT = setTimeout(sync, 700); }

  // ---------- SSE ----------
  function openStream() {
    closeStream(); if (!configured() || typeof EventSource !== 'function') return;
    es = new EventSource(origin() + '/api/stream?dev=' + encodeURIComponent(dev) + '&token=' + encodeURIComponent(cfg.token));
    es.addEventListener('ch', function (e) {
      try { var d = JSON.parse(e.data); remoteQ = remoteQ.concat(d.ch || []); } catch (x) { return; }
      clearTimeout(remoteT); remoteT = setTimeout(function () { var q = remoteQ; remoteQ = []; applyRemote(q); lastOk = Date.now(); paintPanel(); schedulePush(); }, 150);
    });
    es.addEventListener('hb', function () { lastBeat = Date.now(); });
    es.onopen = function () { lastBeat = Date.now(); backoff = 1000; sync(); };
    es.onerror = function () {
      setStatus('off');
      if (es && es.readyState === 2) { closeStream(); clearTimeout(esRetry); esRetry = setTimeout(sync, backoff); backoff = Math.min(30000, backoff * 2); }
    };
  }
  // Pengawas: sambungan SSE yang mati diam-diam (jaringan HP pindah, tunnel putus) dibuka ulang otomatis.
  var lastBeat = 0;
  setInterval(function () {
    if (!ready || !configured() || busy || status === 'auth') return;
    if (!es || es.readyState !== 1 || Date.now() - lastBeat > 65000) { closeStream(); sync(); }
  }, 15000);
  function closeStream() { if (es) { try { es.close(); } catch (e) { /* abaikan */ } es = null; } }

  // ---------- pemicu ----------
  window.addEventListener('kilaw-dirty', function (e) { var c = DIRTY[e.detail]; if (!c || applying) return; dirty[c] = true; if (ready && configured()) schedulePush(); });
  window.addEventListener('online', function () { if (ready) sync(); });
  document.addEventListener('visibilitychange', function () { if (document.hidden) persist(true); else if (ready && configured() && status !== 'on') sync(); });
  window.addEventListener('pagehide', function () { persist(true); });

  // ---------- UI: lencana status + panel di tab Sinkron ----------
  var LABEL = { off: ['#9aa0a6', 'Offline'], sync: ['#f5a623', 'Sinkron…'], on: ['#2ecc71', 'Tersambung'], auth: ['#e74c3c', 'Token salah'] };
  var pill = document.createElement('button');
  pill.type = 'button'; pill.title = 'Status sinkron real-time';
  pill.style.cssText = 'display:none;align-items:center;gap:6px;font-size:12px;padding:4px 10px;border-radius:999px;border:1px solid rgba(128,128,128,.35);background:transparent;color:inherit;cursor:pointer;margin-right:8px';
  var tt = document.getElementById('themeToggle'); if (tt && tt.parentNode) tt.parentNode.insertBefore(pill, tt);
  pill.addEventListener('click', function () { var t = document.querySelector('.tab-btn[data-tab="tab-sinkron"]'); if (t) t.click(); });
  function setStatus(s) {
    status = s; var l = LABEL[s] || LABEL.off;
    pill.style.display = configured() ? 'inline-flex' : 'none';
    pill.innerHTML = '<i style="width:8px;height:8px;border-radius:50%;background:' + l[0] + ';display:inline-block"></i>' + l[1];
    paintPanel();
  }

  var panel = document.createElement('div'); panel.className = 'panel'; panel.id = 'panelRealtime';
  var tab = document.getElementById('tab-sinkron'); if (tab) tab.insertBefore(panel, tab.firstChild);
  var tm = function (t) { var d = new Date(t); return d.toLocaleTimeString('id-ID'); };
  function paintPanel() {
    if (!tab) return;
    var l = LABEL[status] || LABEL.off, act = document.activeElement && panel.contains(document.activeElement);
    var info = configured() ? ('<b style="color:' + l[0] + '">● ' + l[1] + '</b>' + (lastOk ? ' · terakhir ' + tm(lastOk) : '') + ' · perangkat <code>' + dev + '</code>') : 'Belum disambungkan.';
    if (act && panel.dataset.built) { var st = panel.querySelector('#rtInfo'); if (st) st.innerHTML = info; var cb = panel.querySelector('#rtConf'); if (cb) cb.style.display = conflicts.length ? '' : 'none'; return; }
    panel.dataset.built = '1';
    panel.innerHTML = '<h3>Real-time (server sendiri)</h3>' +
      '<p class="hint">Perubahan dikirim otomatis per catatan ke server klinik dan langsung muncul di perangkat lain — tanpa export/import. Tetap berfungsi offline; data terkirim saat tersambung lagi.</p>' +
      '<div class="field-col"><label class="field-label" for="rtUrl">Alamat server</label><input id="rtUrl" class="text-input" placeholder="https://klinik.domainanda.com" value="' + (cfg.url || (/^https?:/.test(location.protocol) && location.hostname !== 'localhost' ? location.origin : '')).replace(/"/g, '&quot;') + '"></div>' +
      '<div class="field-col"><label class="field-label" for="rtTok">Token</label><input id="rtTok" type="password" class="text-input" autocomplete="off" value="' + String(cfg.token || '').replace(/"/g, '&quot;') + '"></div>' +
      '<div style="display:flex;gap:8px;flex-wrap:wrap;margin:10px 0"><button type="button" class="btn btn-accent" id="rtSave" style="flex:1 1 140px">Simpan &amp; Hubungkan</button><button type="button" class="btn btn-ghost" id="rtRe" style="flex:1 1 140px">Gabung ulang</button><button type="button" class="btn btn-ghost" id="rtOff" style="flex:1 1 140px">Putuskan</button></div>' +
      '<p class="hint" id="rtInfo">' + info + '</p>' +
      '<div id="rtConf" style="display:' + (conflicts.length ? '' : 'none') + '"><button type="button" class="btn btn-ghost" id="rtDl">Unduh data bentrok (JSON)</button></div>';
  }
  panel.addEventListener('click', function (e) {
    var id = e.target && e.target.id;
    if (id === 'rtSave') {
      cfg = { url: panel.querySelector('#rtUrl').value.trim(), token: panel.querySelector('#rtTok').value.trim() };
      try { localStorage.setItem(CFG_KEY, JSON.stringify(cfg)); } catch (x) { /* abaikan */ }
      first = true; closeStream(); setStatus('sync'); sync();
    } else if (id === 'rtRe') { first = true; since = 0; base = {}; closeStream(); sync(); if (N.toast) N.toast('Menggabung ulang dengan server…', 'ok'); }
    else if (id === 'rtOff') { cfg = {}; try { localStorage.removeItem(CFG_KEY); } catch (x) { /* abaikan */ } closeStream(); clearTimeout(retryT); setStatus('off'); panel.dataset.built = ''; paintPanel(); }
    else if (id === 'rtDl') {
      var a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([JSON.stringify(conflicts, null, 1)], { type: 'application/json' })); a.download = 'bentrok-sinkron.json'; a.click();
    }
  });

  // ---------- mulai ----------
  Promise.all([kvGet('state'), kvGet('conflicts')]).then(function (v) {
    if (v[0] && v[0].base) { since = v[0].since || 0; base = v[0].base; }
    conflicts = v[1] || []; ready = true; paintPanel(); setStatus(configured() ? 'wait' : 'off'); if (configured()) sync();
  });
  window.KilawSync = { sync: sync, status: function () { return status; }, dev: dev };
})();

