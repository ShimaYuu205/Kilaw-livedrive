/**
 * Kilaw Dental Clinic - backend Apps Script (v2, dioptimalkan untuk sinkron real-time).
 *
 * Kompatibel dengan klien web lama: ping / putfile / getfile.
 * Baru: meta  -> satu panggilan murah yang mengembalikan waktu ubah semua file di folder,
 *        sehingga klien Flutter cukup polling meta tiap beberapa detik dan hanya mengunduh
 *        file yang benar-benar berubah.
 *
 * CARA PASANG
 *  1. script.google.com -> Proyek baru -> tempel file ini sebagai Code.gs.
 *  2. (opsional) isi LINK_FOLDER_APP / LINK_FOLDER_EXCEL dengan link folder Drive.
 *  3. Jalankan fungsi setup() sekali -> salin TOKEN dari log (Lihat > Log eksekusi).
 *  4. Deploy > Deployment baru > Aplikasi web: Jalankan sebagai "Saya", akses "Siapa saja".
 *  5. Salin URL (berakhiran /exec) + token ke tab Sinkron di aplikasi.
 *  Setiap kali Code.gs diubah: Deploy > Kelola deployment > Edit > Versi baru.
 */

var LINK_FOLDER_APP = '';    // mis. https://drive.google.com/drive/folders/XXXXXXXX  (kosong = buat folder "Kilaw Dental Clinic")
var LINK_FOLDER_EXCEL = '';  // folder terpisah untuk ekspor Excel (kosong = folder "excel" di dalam folder aplikasi)
var APP_FOLDER_NAME = 'Kilaw Dental Clinic';
var MAX_B64 = 40 * 1024 * 1024;

function setup() {
  var props = PropertiesService.getScriptProperties();
  var token = props.getProperty('TOKEN');
  if (!token) {
    token = Utilities.getUuid().replace(/-/g, '') + Utilities.getUuid().replace(/-/g, '').slice(0, 8);
    props.setProperty('TOKEN', token);
  }
  var root = appFolder_();
  ['data', 'laporan', 'export'].forEach(function (n) { sub_(root, n); });
  Logger.log('TOKEN: ' + token);
  Logger.log('Folder aplikasi: ' + root.getUrl());
  return token;
}

function doGet() {
  return json_({ ok: true, name: 'Kilaw Apps Script', time: Date.now() });
}

function doPost(e) {
  var lock = null;
  try {
    var req = JSON.parse((e.postData && e.postData.contents) || '{}');
    var token = PropertiesService.getScriptProperties().getProperty('TOKEN');
    if (!token || req.token !== token) return json_({ ok: false, error: 'Token salah.' });
    var d = req.data || {};
    switch (req.action) {
      case 'ping':
        return json_({ ok: true, excel: excelFolder_() ? excelFolder_().getName() : '' });
      case 'meta':
        return json_({ ok: true, files: meta_(d.folder || 'data'), now: Date.now() });
      case 'getfile':
        return json_(getfile_(d));
      case 'putfile':
        lock = LockService.getScriptLock();
        lock.waitLock(20000);
        return json_(putfile_(d));
      default:
        return json_({ ok: false, error: 'Aksi tidak dikenal: ' + req.action });
    }
  } catch (err) {
    return json_({ ok: false, error: String(err && err.message ? err.message : err) });
  } finally {
    if (lock) { try { lock.releaseLock(); } catch (x) { /* abaikan */ } }
  }
}

// ---------------- folder ----------------
function idFromLink_(link) {
  var m = String(link || '').match(/[-\w]{25,}/);
  return m ? m[0] : '';
}

function appFolder_() {
  var props = PropertiesService.getScriptProperties();
  var id = props.getProperty('APP_FOLDER_ID');
  if (id) { try { return DriveApp.getFolderById(id); } catch (e) { /* buat ulang */ } }
  var f;
  var lid = idFromLink_(LINK_FOLDER_APP);
  if (lid) f = DriveApp.getFolderById(lid);
  else {
    var it = DriveApp.getFoldersByName(APP_FOLDER_NAME);
    f = it.hasNext() ? it.next() : DriveApp.createFolder(APP_FOLDER_NAME);
  }
  props.setProperty('APP_FOLDER_ID', f.getId());
  return f;
}

function sub_(parent, name) {
  var props = PropertiesService.getScriptProperties();
  var key = 'SUB:' + parent.getId() + ':' + name;
  var id = props.getProperty(key);
  if (id) { try { return DriveApp.getFolderById(id); } catch (e) { /* buat ulang */ } }
  var it = parent.getFoldersByName(name);
  var f = it.hasNext() ? it.next() : parent.createFolder(name);
  props.setProperty(key, f.getId());
  return f;
}

function excelFolder_() {
  var lid = idFromLink_(LINK_FOLDER_EXCEL);
  if (lid) return DriveApp.getFolderById(lid);
  return sub_(appFolder_(), 'excel');
}

function folderFor_(name) {
  if (name === 'excel') return excelFolder_();
  var ok = { data: 1, laporan: 1, export: 1 };
  if (!ok[name]) throw new Error('Folder tidak diizinkan: ' + name);
  return sub_(appFolder_(), name);
}

function safeName_(n) {
  n = String(n || '');
  if (!n || /[\\\/]/.test(n) || n.indexOf('..') >= 0) throw new Error('Nama file tidak valid.');
  return n;
}

// ---------------- meta cepat (PropertiesService) ----------------
function metaKey_(folder, name) { return 'M:' + folder + '/' + name; }

function setMeta_(folder, name, file) {
  PropertiesService.getScriptProperties().setProperty(
    metaKey_(folder, name),
    JSON.stringify({ m: file.getLastUpdated().getTime(), s: file.getSize() })
  );
}

function meta_(folder) {
  var props = PropertiesService.getScriptProperties();
  var all = props.getProperties();
  var prefix = 'M:' + folder + '/';
  var out = {};
  Object.keys(all).forEach(function (k) {
    if (k.indexOf(prefix) === 0) {
      try { out[k.slice(prefix.length)] = JSON.parse(all[k]); } catch (e) { /* abaikan */ }
    }
  });
  if (!Object.keys(out).length) {
    // pertama kali / file diletakkan manual: pindai folder sekali lalu simpan
    var it = folderFor_(folder).getFiles();
    while (it.hasNext()) {
      var f = it.next();
      var name = f.getName();
      setMeta_(folder, name, f);
      out[name] = { m: f.getLastUpdated().getTime(), s: f.getSize() };
    }
  }
  return out;
}

// ---------------- file ----------------
function findFile_(folder, name) {
  var it = folder.getFilesByName(name);
  return it.hasNext() ? it.next() : null;
}

function getfile_(d) {
  var folder = folderFor_(d.folder);
  var f = findFile_(folder, safeName_(d.name));
  if (!f) return { ok: true, b64: '' };
  return { ok: true, b64: Utilities.base64Encode(f.getBlob().getBytes()), modified: f.getLastUpdated().getTime() };
}

function putfile_(d) {
  var name = safeName_(d.name);
  var b64 = String(d.b64 || '');
  if (!b64) throw new Error('Isi file kosong.');
  if (b64.length > MAX_B64) throw new Error('File terlalu besar.');
  var folderName = d.folder;
  var folder = folderFor_(folderName);
  var bytes = Utilities.base64Decode(b64);
  var blob = Utilities.newBlob(bytes, d.mime || 'application/octet-stream', name);
  var old = findFile_(folder, name);
  var file;
  if (old) {
    // cadangan: satu salinan per file di _cadangan (menimpa cadangan sebelumnya); folder excel: _cadangan-asli hanya sekali
    try {
      if (folderName === 'excel') {
        var asli = sub_(folder, '_cadangan-asli');
        if (!findFile_(asli, name)) old.makeCopy(name, asli);
      } else if (folderName === 'data') {
        var bk = sub_(folder, '_cadangan');
        var prev = findFile_(bk, name);
        if (prev) prev.setTrashed(true);
        old.makeCopy(name, bk);
      }
    } catch (e) { /* cadangan gagal tidak boleh menggagalkan simpan */ }
    // DriveApp tidak punya setBlob untuk file biner: file lama dibuang ke sampah, lalu dibuat ulang (nama sama).
    old.setTrashed(true);
  }
  file = folder.createFile(blob);
  setMeta_(folderName, name, file);
  return { ok: true, modified: file.getLastUpdated().getTime(), size: file.getSize() };
}

function json_(o) {
  return ContentService.createTextOutput(JSON.stringify(o)).setMimeType(ContentService.MimeType.JSON);
}
