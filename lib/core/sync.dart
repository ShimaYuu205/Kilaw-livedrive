import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import 'store.dart';
import 'util.dart';

class ApiError implements Exception {
  final String message;
  final bool final_;
  ApiError(this.message, {this.final_ = false});
  @override
  String toString() => message;
}

/// Kolom ringkas (tanpa nama field berulang) - kompatibel dengan versi web.
Map<String, dynamic> encL(List<Rec> l) {
  final k = <String>[];
  final ix = <String, int>{};
  for (final o in l) {
    for (final c in o.keys) {
      if (!ix.containsKey(c)) {
        ix[c] = k.length;
        k.add(c);
      }
    }
  }
  final r = l.map((o) {
    final row = k.map((c) => o[c]).toList();
    while (row.isNotEmpty && row.last == null) {
      row.removeLast();
    }
    return row;
  }).toList();
  return {'k': k, 'r': r};
}

List<Rec> decL(dynamic e) {
  if (e is! Map || e['r'] is! List) return [];
  final k = (e['k'] as List).map(s).toList();
  return (e['r'] as List).map((row) {
    final o = <String, dynamic>{};
    final rr = row as List;
    for (var i = 0; i < k.length && i < rr.length; i++) {
      if (rr[i] != null) o[k[i]] = rr[i];
    }
    return o;
  }).toList();
}

Map<String, int> _tombOf(dynamic t) =>
    t is Map ? t.map((a, b) => MapEntry(s(a), (b as num).toInt())) : <String, int>{};

class _FileSpec {
  final String base;
  final List<String> sets; // dataset yang masuk ke file ini ('antrian' khusus)
  final bool plain;
  const _FileSpec(this.base, this.sets, this.plain);
}

const _files = <_FileSpec>[
  _FileSpec('antrian', ['antrian'], true),
  _FileSpec('entry', ['entry'], false),
  _FileSpec('pasien', ['pasien'], false),
  _FileSpec('catatan', catatanSets, false),
  _FileSpec('inform-consent', ['consent'], true),
  _FileSpec('ttd', ['dokter'], true),
];

SyncService? syncInstance;

class SyncService extends ChangeNotifier with WidgetsBindingObserver {
  final AppStore store;
  SyncService(this.store);

  String status = 'Sinkron belum diisi.';
  bool busy = false, online = true, foreground = true, metaOk = true;
  DateTime? lastOk;
  int pending = 0;
  final Map<String, int> _known = {}; // nama file -> modified (ms) terakhir yang sudah dimuat/dikirim
  Timer? _pushT, _pollT;
  int _errStreak = 0;
  bool _running = false;
  StreamSubscription? _conn;
  final _toast = StreamController<String>.broadcast();
  Stream<String> get messages => _toast.stream;

  Duration pollEvery = const Duration(seconds: 12);

  // ------------------------------------------------------------
  void start() {
    syncInstance = this;
    store.onDirty = _onDirty;
    WidgetsBinding.instance.addObserver(this);
    _conn = Connectivity().onConnectivityChanged.listen((r) {
      final on = !r.contains(ConnectivityResult.none);
      if (on && !online) {
        online = true;
        _kick(immediate: true);
      }
      online = on;
      notifyListeners();
    });
    _schedulePoll(const Duration(seconds: 1));
    if (store.dirty.isNotEmpty) _kick();
  }

  @override
  void dispose() {
    _pushT?.cancel();
    _pollT?.cancel();
    _conn?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState st) {
    foreground = st == AppLifecycleState.resumed;
    if (foreground) {
      _schedulePoll(const Duration(milliseconds: 300));
    } else {
      store.flushAll();
      if (store.dirty.isNotEmpty) _kick(immediate: true); // kirim sebelum ditidurkan
    }
  }

  void _onDirty(String set) {
    pending = store.dirty.length;
    if (!store.syncReady) {
      status = 'Tersimpan di perangkat (Sinkron belum diisi).';
      notifyListeners();
      return;
    }
    status = 'Menunggu kirim ke Drive…';
    notifyListeners();
    _kick(delay: set == 'antrian' ? const Duration(milliseconds: 700) : const Duration(milliseconds: 1800));
  }

  void _kick({bool immediate = false, Duration delay = const Duration(milliseconds: 1500)}) {
    if (!store.syncReady) return;
    _pushT?.cancel();
    _pushT = Timer(immediate ? Duration.zero : delay, () => syncNow());
  }

  void _schedulePoll(Duration d) {
    _pollT?.cancel();
    _pollT = Timer(d, () async {
      if (foreground && online && store.syncReady && !busy) await _poll();
      final next = Duration(milliseconds: (pollEvery.inMilliseconds * (1 + (_errStreak > 5 ? 5 : _errStreak))).clamp(8000, 120000).toInt());
      _schedulePoll(next);
    });
  }

  // ------------------------------------------------------------
  // API (kompatibel dengan Code.gs lama: ping / putfile / getfile; baru: meta)
  Future<Map<String, dynamic>> api(String action, [Map<String, dynamic>? d]) async {
    if (!store.syncReady) throw ApiError('Isi URL dan token di atas, lalu simpan pengaturan.', final_: true);
    ApiError? last;
    for (var i = 0; i < 3; i++) {
      try {
        final body = jsonEncode({'token': store.token, 'action': action, 'data': d});
        final text = await _post(store.url, body);
        Map<String, dynamic> j;
        try {
          j = jsonDecode(text) as Map<String, dynamic>;
        } catch (_) {
          throw ApiError('Balasan bukan JSON. Pastikan Web app di-deploy sebagai “Anyone” dan URL berakhiran /exec.', final_: true);
        }
        if (j['ok'] != true) throw ApiError(s(j['error']).isEmpty ? 'Gagal' : s(j['error']), final_: true);
        return j;
      } on ApiError catch (e) {
        if (e.final_) rethrow;
        last = e;
      } catch (e) {
        last = ApiError(e.toString());
      }
      await Future.delayed(Duration(milliseconds: 700 * (i + 1)));
    }
    throw last ?? ApiError('Gagal');
  }

  final http.Client _http = http.Client();
  Future<String> _post(String url, String body) async {
    var req = http.Request('POST', Uri.parse(url))
      ..followRedirects = false
      ..headers['Content-Type'] = 'text/plain;charset=utf-8'
      ..body = body;
    var res = await http.Response.fromStream(await _http.send(req).timeout(const Duration(seconds: 60)));
    var hops = 0;
    while ({301, 302, 303, 307, 308}.contains(res.statusCode) && res.headers['location'] != null && hops++ < 5) {
      // Apps Script: hasil POST disajikan lewat GET ke alamat redirect.
      res = await _http.get(Uri.parse(res.headers['location']!)).timeout(const Duration(seconds: 60));
    }
    if (res.statusCode >= 400) throw ApiError('HTTP ${res.statusCode}');
    return utf8.decode(res.bodyBytes);
  }

  // ---------- encode / decode file ----------
  Uint8List _gz(String str) => Uint8List.fromList(gzip.encode(utf8.encode(str)));

  Future<int> putJson(String base, Object obj, {bool plain = false, String folder = 'data'}) async {
    final str = jsonEncode(obj);
    final bytes = plain ? Uint8List.fromList(utf8.encode(str)) : _gz(str);
    final name = base + (plain ? '.json' : '.json.gz');
    final j = await api('putfile', {
      'folder': folder,
      'name': name,
      'mime': plain ? 'application/json' : 'application/gzip',
      'b64': base64Encode(bytes),
    });
    final m = j['modified'];
    if (m is num) _known[name] = m.toInt();
    return bytes.length;
  }

  Future<({dynamic obj, int modified})?> getJson(String base, {bool plain = false}) async {
    for (final ext in plain ? ['.json'] : ['.json.gz', '.json']) {
      final name = base + ext;
      final j = await api('getfile', {'folder': 'data', 'name': name});
      final b = s(j['b64']);
      if (b.isEmpty) continue;
      final u = base64Decode(b);
      final text = ext == '.json.gz' ? utf8.decode(gzip.decode(u)) : utf8.decode(u);
      final m = j['modified'] is num ? (j['modified'] as num).toInt() : 0;
      _known[name] = m;
      return (obj: jsonDecode(text), modified: m);
    }
    return null;
  }

  // ---------- bangun / baca payload per file ----------
  Object _buildPayload(_FileSpec f) {
    switch (f.base) {
      case 'pasien':
        return {'v': 1, 'd': encL(store.pasien), 'tomb': store.tomb['pasien']};
      case 'entry':
        return {'v': 1, 'd': encL(store.entry), 'tomb': store.tomb['entry']};
      case 'catatan':
        return {
          'v': 1,
          for (final k in catatanSets) k: encL(store.data[k]!),
          'tomb': {for (final k in catatanSets) k: store.tomb[k]},
        };
      case 'inform-consent':
        return {'v': 1, 'd': store.data['consent'], 'tomb': store.tomb['consent']};
      case 'ttd':
        return {'v': 1, 'd': store.data['dokter']};
      default: // antrian
        return {...store.antrian, 'tomb': store.tomb['antrian']};
    }
  }

  List<Rec> _recs(dynamic l) =>
      (l as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  /// Menggabungkan isi file remote ke store. true bila ada perubahan lokal.
  bool _applyPayload(_FileSpec f, dynamic o) {
    var ch = false;
    switch (f.base) {
      case 'pasien':
      case 'entry':
        final map = o is Map ? o : {'d': o};
        final set = f.base;
        final list = map['d'] is Map ? decL(map['d']) : _recs(map['d']);
        ch = store.mergeRemote(set, list, _tombOf(map['tomb']));
        break;
      case 'catatan':
        final m = o as Map;
        final tb = m['tomb'] is Map ? m['tomb'] as Map : {};
        for (final k in catatanSets) {
          ch = store.mergeRemote(k, decL(m[k]), _tombOf(tb[k])) || ch;
        }
        break;
      case 'inform-consent':
        final map = o is Map ? o : {'d': o};
        ch = store.mergeRemote('consent', _recs(map['d']), _tombOf(map['tomb']));
        break;
      case 'ttd':
        final map = o is Map ? o : {'d': o};
        final before = store.dokterAll.length;
        final jsonBefore = jsonEncode(store.dokterAll);
        final merged = <String, Rec>{};
        for (final d in [...store.dokterAll, ..._recs(map['d'])]) {
          final id = s(d['id']);
          if (id.isNotEmpty && (!merged.containsKey(id) || n(d['u']) >= n(merged[id]!['u']))) merged[id] = d;
        }
        store.data['dokter'] = merged.values.toList();
        ch = jsonBefore != jsonEncode(store.dokterAll) || before != store.dokterAll.length;
        if (ch) store.persistOnly('dokter');
        break;
      default:
        ch = store.mergeAntrian(o as Map);
    }
    return ch;
  }

  bool _isDirty(_FileSpec f) => f.sets.any(store.dirty.contains);

  String _fileName(_FileSpec f) => f.base + (f.plain ? '.json' : '.json.gz');

  // ---------- satu file: tarik bila berubah, gabung, lalu kirim bila ada perubahan lokal ----------
  Future<bool> _syncFile(_FileSpec f, {int? remoteModified}) async {
    var uiChanged = false;
    final name = _fileName(f);
    final known = _known[name];
    final mustPull = remoteModified == null || known == null || remoteModified != known;
    if (mustPull) {
      final r = await getJson(f.base, plain: f.plain);
      if (r != null) uiChanged = _applyPayload(f, r.obj);
    }
    if (_isDirty(f)) {
      final snap = {for (final k in f.sets) k: store.rev[k] ?? 0};
      await putJson(f.base, _buildPayload(f), plain: f.plain);
      // hanya bersihkan penanda bila tidak ada perubahan baru selama pengiriman
      store.clearDirty(f.sets.where((k) => (store.rev[k] ?? 0) == snap[k]));
    }
    return uiChanged;
  }

  // ------------------------------------------------------------
  /// Dorong semua perubahan lokal (setelah menarik perubahan remote agar tidak menimpa).
  Future<void> syncNow() async {
    if (!store.syncReady || busy || _running) {
      if (busy || _running) _kick(delay: const Duration(seconds: 2));
      return;
    }
    _running = true;
    busy = true;
    notifyListeners();
    try {
      Map<String, int> remote = {};
      if (metaOk) {
        try {
          remote = await _meta();
        } catch (e) {
          if (s(e).contains('Aksi tidak dikenal') || s(e).contains('unknown')) metaOk = false;
        }
      }
      var ui = false;
      for (final f in _files) {
        if (!_isDirty(f)) continue;
        ui = await _syncFile(f, remoteModified: remote[_fileName(f)]) || ui;
      }
      _errStreak = 0;
      lastOk = DateTime.now();
      pending = store.dirty.length;
      status = 'Tersinkron ${_hhmm(lastOk!)}';
      if (ui) store.notifyExternal();
    } catch (e) {
      _errStreak++;
      status = 'Tersimpan di perangkat; belum terkirim: $e';
      _kick(delay: Duration(seconds: (4 * (1 << (_errStreak > 5 ? 5 : _errStreak))).clamp(4, 120).toInt()));
    } finally {
      busy = false;
      _running = false;
      notifyListeners();
    }
  }

  Future<Map<String, int>> _meta() async {
    final j = await api('meta', {'folder': 'data'});
    final fs = j['files'];
    final out = <String, int>{};
    if (fs is Map) {
      fs.forEach((k, v) {
        if (v is Map && v['m'] is num) out[s(k)] = (v['m'] as num).toInt();
        if (v is num) out[s(k)] = v.toInt();
      });
    }
    return out;
  }

  /// Polling ringan: satu request meta, tarik hanya file yang berubah.
  Future<void> _poll() async {
    if (!metaOk || busy || _running) return;
    _running = true;
    try {
      final remote = await _meta();
      var ui = false;
      for (final f in _files) {
        final m = remote[_fileName(f)];
        if (m == null) continue;
        if (_known[_fileName(f)] == m) continue;
        final r = await getJson(f.base, plain: f.plain);
        if (r != null) ui = _applyPayload(f, r.obj) || ui;
      }
      if (ui) store.notifyExternal();
      _errStreak = 0;
      lastOk = DateTime.now();
      if (store.dirty.isEmpty) status = 'Tersinkron ${_hhmm(lastOk!)}';
    } catch (e) {
      if (s(e).contains('Aksi tidak dikenal') || s(e).contains('unknown')) {
        metaOk = false;
        status = 'Server lama: real-time dimatikan (perbarui Code.gs). Muat manual dari tab Sinkron.';
      } else {
        _errStreak++;
      }
    } finally {
      _running = false;
      notifyListeners();
    }
  }

  String _hhmm(DateTime d) => '${pad2(d.hour)}:${pad2(d.minute)}:${pad2(d.second)}';

  // ============================================================
  // Aksi manual dari tab Sinkron
  Future<String> ping() async {
    final j = await api('ping');
    metaOk = true;
    return j['excel'] != null && s(j['excel']).isNotEmpty
        ? 'Terhubung ke Apps Script. Folder Excel terpisah: “${j['excel']}”.'
        : 'Terhubung ke Apps Script. Folder Excel belum diatur di Code.gs (LINK_FOLDER_EXCEL).';
  }

  /// Kirim SEMUA data (tandai semua kotor lalu dorong).
  Future<String> uploadAll(void Function(String) progress) async {
    final sizes = <String>[];
    for (final f in _files) {
      progress('Mengirim ${f.base}…');
      final bytes = await putJson(f.base, _buildPayload(f), plain: f.plain);
      store.clearDirty(f.sets);
      sizes.add('${f.base} ${(bytes / 1024).round()} KB');
    }
    pending = 0;
    lastOk = DateTime.now();
    status = 'Tersinkron ${_hhmm(lastOk!)}';
    notifyListeners();
    return 'Terkirim ke Drive (folder data/): ${sizes.join(' · ')} — dikompres gzip. Versi lama otomatis dicadangkan.';
  }

  /// Muat SEMUA data dari Drive. [replace] = timpa (seperti versi web), kalau tidak = gabung.
  Future<String> downloadAll(void Function(String) progress, {bool replace = true}) async {
    final out = <String>[];
    for (final f in _files) {
      progress('Mengunduh ${f.base}…');
      final r = await getJson(f.base, plain: f.plain);
      if (r == null) {
        out.add('${f.base}: belum ada');
        continue;
      }
      if (replace) _wipe(f);
      _applyPayload(f, r.obj);
      store.clearDirty(f.sets);
      out.add('${f.base} ✓');
    }
    store.notifyExternal();
    return 'Selesai — ${out.join(' · ')}';
  }

  void _wipe(_FileSpec f) {
    for (final k in f.sets) {
      if (k == 'antrian') {
        store.antrian = {'v': 1, 'seq': 0, 'items': <dynamic>[]};
        store.tomb['antrian']!.clear();
      } else {
        store.data[k] = [];
        store.tomb[k]!.clear();
      }
    }
  }
}
