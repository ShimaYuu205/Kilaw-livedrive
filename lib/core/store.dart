import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'odo.dart';
import 'search.dart';
import 'util.dart';

/// Dataset yang disimpan & disinkronkan. 'pasien' berkunci noFile, lainnya berkunci id.
const dataSets = ['pasien', 'entry', 'prospek', 'gigi', 'stok', 'mutasi', 'beli', 'consent', 'dokter'];
const catatanSets = ['prospek', 'gigi', 'stok', 'mutasi', 'beli'];

String keyOf(String set, Rec r) => set == 'pasien' ? s(r['noFile']) : s(r['id']);

class AppStore extends ChangeNotifier {
  late final Directory _dir;
  late final SharedPreferences prefs;
  final Map<String, List<Rec>> data = {for (final k in dataSets) k: <Rec>[]};
  Rec antrian = {'v': 1, 'seq': 0, 'items': <dynamic>[]};
  Rec odoState = {};
  List<Rec> harga = [];
  List<Rec> stage = []; // popup Antrian (daftar sementara, hanya lokal)
  final Map<String, Map<String, int>> tomb = {for (final k in [...dataSets, 'antrian']) k: <String, int>{}};
  final Map<String, int> rev = {for (final k in [...dataSets, 'antrian']) k: 0};
  final Set<String> dirty = {};
  bool ready = false;

  /// Dipanggil setiap ada perubahan data yang perlu dikirim (nama dataset).
  void Function(String set)? onDirty;

  // ---- pengaturan ----
  String get url => _cfg['url'] ?? '';
  String get token => _cfg['token'] ?? '';
  bool get syncReady => url.isNotEmpty && token.isNotEmpty;
  Map<String, String> _cfg = {'url': '', 'token': ''};
  bool lightTheme = false;
  String get jagaId => prefs.getString('kilaw_dokter_jaga') ?? '';
  String get savedSig => prefs.getString('kilaw_sig_png') ?? '';

  // ============================================================
  Future<void> init() async {
    prefs = await SharedPreferences.getInstance();
    final base = await getApplicationSupportDirectory();
    _dir = Directory('${base.path}/kilaw');
    if (!_dir.existsSync()) _dir.createSync(recursive: true);
    final c = prefs.getString('kilaw_appscript_source');
    if (c != null) {
      try {
        final m = jsonDecode(c) as Map;
        _cfg = {'url': s(m['url']), 'token': s(m['token'])};
      } catch (_) {}
    }
    lightTheme = (prefs.getString('kilaw_theme') ?? prefs.getString('kilawnote_theme') ?? 'dark') == 'light';
    for (final k in dataSets) {
      final j = await _read(k);
      if (j is List) data[k] = j.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    final a = await _read('antrian');
    if (a is Map && a['items'] is List) antrian = Map<String, dynamic>.from(a);
    final o = await _read('odo_state');
    if (o is Map) odoState = Map<String, dynamic>.from(o);
    final h = await _read('odo_harga');
    harga = h is List ? h.map((e) => Map<String, dynamic>.from(e as Map)).toList() : defaultHarga();
    final st = await _read('stage');
    if (st is List) stage = st.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final tb = await _read('tomb');
    if (tb is Map) {
      tb.forEach((k, v) {
        if (tomb.containsKey(k) && v is Map) tomb[k] = v.map((a, b) => MapEntry(s(a), (b as num).toInt()));
      });
    }
    final dr = await _read('dirty');
    if (dr is List) dirty.addAll(dr.map(s));
    // id & updatedAt untuk entry lama
    var ch = false;
    for (final e in data['entry']!) {
      if (s(e['id']).isEmpty) {
        e['id'] = newId('e');
        ch = true;
      }
    }
    if (ch) _persist('entry');
    ready = true;
    notifyListeners();
  }

  // ---------------- file I/O (atomic, debounced) ----------------
  final Map<String, Timer> _timers = {};
  File _f(String name) => File('${_dir.path}/$name.json');

  Future<dynamic> _read(String name) async {
    try {
      final f = _f(name);
      if (await f.exists()) return jsonDecode(await f.readAsString());
    } catch (e) {
      debugPrint('read $name: $e');
      try {
        final b = File('${_f(name).path}.bak');
        if (await b.exists()) return jsonDecode(await b.readAsString());
      } catch (_) {}
    }
    return null;
  }

  dynamic _valueOf(String name) {
    switch (name) {
      case 'antrian':
        return antrian;
      case 'odo_state':
        return odoState;
      case 'odo_harga':
        return harga;
      case 'stage':
        return stage;
      case 'tomb':
        return tomb;
      case 'dirty':
        return dirty.toList();
      default:
        return data[name];
    }
  }

  void _persist(String name) {
    _timers[name]?.cancel();
    _timers[name] = Timer(const Duration(milliseconds: 350), () => _writeNow(name));
  }

  Future<void> _writeNow(String name) async {
    try {
      final f = _f(name);
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode(_valueOf(name)), flush: true);
      if (await f.exists()) {
        try {
          await f.copy('${f.path}.bak');
        } catch (_) {}
      }
      await tmp.rename(f.path);
    } catch (e) {
      debugPrint('write $name: $e');
    }
  }

  Future<void> flushAll() async {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    for (final k in [...dataSets, 'antrian', 'odo_state', 'odo_harga', 'stage', 'tomb', 'dirty']) {
      await _writeNow(k);
    }
  }

  // ---------------- penandaan perubahan ----------------
  void _mark(String set, {bool notify = true, bool sync = true}) {
    rev[set] = (rev[set] ?? 0) + 1;
    _persist(set == 'antrian' ? 'antrian' : set);
    if (sync) {
      dirty.add(set);
      _persist('dirty');
      onDirty?.call(set);
    }
    if (notify) notifyListeners();
  }

  void changed(String set, {bool notify = true}) => _mark(set, notify: notify);

  /// Simpan ke disk tanpa menandai kotor (hasil gabungan dari Drive).
  void persistOnly(String set) {
    rev[set] = (rev[set] ?? 0) + 1;
    _persist(set);
  }

  void clearDirty(Iterable<String> sets) {
    dirty.removeAll(sets);
    _persist('dirty');
  }

  // ---------------- indeks pasien ----------------
  Map<String, Rec>? _pIdx;
  int _pIdxRev = -1;
  Rec? findPasien(dynamic rm) {
    if (_pIdx == null || _pIdxRev != rev['pasien']) {
      _pIdx = {};
      for (final p in data['pasien']!) {
        _pIdx![s(p['noFile'])] = p;
      }
      _pIdxRev = rev['pasien']!;
    }
    return _pIdx![s(rm)];
  }

  List<Rec> get pasien => data['pasien']!;
  List<Rec> get entry => data['entry']!;

  // ---------------- CRUD generik ----------------
  Rec upsert(String set, Rec r, {bool touch = true}) {
    if (touch) r['updatedAt'] = nowMs();
    final list = data[set]!;
    final k = keyOf(set, r);
    final i = list.indexWhere((x) => keyOf(set, x) == k);
    if (i >= 0) {
      list[i] = r;
    } else {
      list.add(r);
    }
    tomb[set]!.remove(k);
    _mark(set);
    return r;
  }

  void removeKey(String set, String key) {
    data[set]!.removeWhere((x) => keyOf(set, x) == key);
    tomb[set]![key] = nowMs();
    _persist('tomb');
    _mark(set);
  }

  void replaceAll(String set, List<Rec> list) {
    // dipakai impor / "Muat dari Drive": semua ditandai baru.
    final t = nowMs();
    for (final r in list) {
      r['updatedAt'] ??= t;
    }
    data[set] = list;
    tomb[set]!.clear();
    _persist('tomb');
    _mark(set);
  }

  // ---------------- Pasien & Entry ----------------
  int highestRm([String extra = '']) {
    var mx = 0;
    for (final p in pasien) {
      final v = int.tryParse(s(p['noFile']));
      if (v != null && v > mx) mx = v;
    }
    for (final l in extra.split('\n')) {
      final m = RegExp(r'^\s*(\d+)').firstMatch(l);
      if (m != null) {
        final v = int.parse(m[1]!);
        if (v > mx) mx = v;
      }
    }
    return mx;
  }

  String maxEntryKey() {
    var mx = '';
    for (final e in entry) {
      final k = dateKey(s(e['tanggal']));
      if (k.compareTo(mx) > 0) mx = k;
    }
    return mx;
  }

  void insertEntryByDate(Rec e, {bool notify = false}) {
    e['id'] = s(e['id']).isEmpty ? newId('e') : e['id'];
    e['updatedAt'] = nowMs();
    final list = entry;
    final k = dateKey(s(e['tanggal']));
    if (k.isEmpty) {
      list.add(e);
    } else {
      if (k.compareTo(maxEntryKey()) < 0) e['susulan'] = true;
      var idx = -1;
      for (var i = list.length - 1; i >= 0; i--) {
        final kk = dateKey(s(list[i]['tanggal']));
        if (kk.isNotEmpty && kk.compareTo(k) <= 0) {
          idx = i;
          break;
        }
      }
      if (idx >= 0) {
        list.insert(idx + 1, e);
      } else {
        var first = -1;
        for (var i = 0; i < list.length; i++) {
          if (dateKey(s(list[i]['tanggal'])).isNotEmpty) {
            first = i;
            break;
          }
        }
        if (first >= 0) {
          list.insert(first, e);
        } else {
          list.add(e);
        }
      }
    }
    tomb['entry']!.remove(s(e['id']));
    _mark('entry', notify: notify);
  }

  void saveEntry(Rec e) {
    e['updatedAt'] = nowMs();
    _mark('entry');
  }

  /// Salin nama/usia/alamat pasien terbaru ke semua riwayat entry miliknya.
  bool syncEntryFromPasien(Rec p) {
    var changed = false;
    final t = nowMs();
    for (final e in entry) {
      if (s(e['noFile']) == s(p['noFile']) && s(e['noFile']).isNotEmpty) {
        if (e['nama'] != p['nama']) {
          e['nama'] = p['nama'];
          changed = true;
          e['updatedAt'] = t;
        }
        if (e['umur'] != p['umur']) {
          e['umur'] = p['umur'];
          changed = true;
          e['updatedAt'] = t;
        }
        if (e['alamat'] != p['alamat']) {
          e['alamat'] = p['alamat'];
          changed = true;
          e['updatedAt'] = t;
        }
      }
    }
    if (changed) _mark('entry', notify: false);
    return changed;
  }

  /// Memasukkan data antrian (End Shift) ke pasien + entry.
  ({int baru, int diperbarui, int kunjungan, int dilewati}) applyShift(List<({Rec pasien, Map? odo, bool isNew})> patients, List<Rec> visits) {
    var nNew = 0, nUpd = 0, nVisit = 0, nSkip = 0;
    final now = nowMs();
    for (final x in patients) {
      var p = findPasien(x.pasien['noFile']);
      if (p == null) {
        p = {'noFile': x.pasien['noFile'], 'addedAt': now};
        pasien.add(p);
        nNew++;
        _pIdx = null;
      } else {
        nUpd++;
      }
      x.pasien.forEach((k, v) {
        if (k != 'noFile') p![k] = v;
      });
      if (x.odo != null) p['odo'] = x.odo;
      p['isIncomplete'] = false;
      p['updatedAt'] = now;
      tomb['pasien']!.remove(s(p['noFile']));
      if (!x.isNew) syncEntryFromPasien(p);
    }
    for (final v in visits) {
      final dup = entry.any((e) =>
          s(e['noFile']) == s(v['noFile']) &&
          e['tanggal'] == v['tanggal'] &&
          e['gigi'] == v['gigi'] &&
          e['perawatan'] == v['perawatan'] &&
          n(e['biaya']) == n(v['biaya']));
      if (dup) {
        nSkip++;
        continue;
      }
      v['id'] = newId('e');
      insertEntryByDate(v);
      nVisit++;
    }
    _mark('pasien');
    return (baru: nNew, diperbarui: nUpd, kunjungan: nVisit, dilewati: nSkip);
  }

  void saveOdoToPasien(String rm, Map snap) {
    final p = findPasien(rm);
    if (p == null) return;
    p['odo'] = snap;
    p['updatedAt'] = nowMs();
    _mark('pasien');
  }

  // ---------------- Stok & mutasi ----------------
  void saveMutasiBatch(List<Rec> recs) {
    for (final r in recs) {
      r['updatedAt'] = nowMs();
      data['mutasi']!.add(r);
    }
    _mark('mutasi');
  }

  // ---------------- Antrian ----------------
  List<Rec> get aqItems => (antrian['items'] as List).map((e) => e as Rec).toList();

  void aqSave() {
    antrian['u'] = nowMs();
    _mark('antrian');
  }

  void setAqItems(List<Rec> items) {
    antrian['items'] = items;
    antrian['seq'] = items.length;
    aqSave();
  }

  void saveStage() {
    _persist('stage');
    notifyListeners();
  }

  // ---------------- Dokter ----------------
  List<Rec> get dokterAll => data['dokter']!;
  List<Rec> get dokterVis => dokterAll.where((d) => d['del'] != true).toList();
  Rec? get jaga => firstWhereOrNull(dokterVis, (d) => d['id'] == jagaId);

  void mergeDokter(List<Rec> incoming) {
    final m = <String, Rec>{};
    for (final d in [...dokterAll, ...incoming]) {
      final id = s(d['id']);
      if (id.isEmpty) continue;
      if (!m.containsKey(id) || n(d['u']) >= n(m[id]!['u'])) m[id] = d;
    }
    data['dokter'] = m.values.toList();
    _mark('dokter');
  }

  void saveDokter(Rec rec) {
    rec['u'] = nowMs();
    rec['updatedAt'] = rec['u'];
    mergeDokter([rec]);
  }

  void deleteDokter(String id) {
    mergeDokter([
      {'id': id, 'del': true, 'u': nowMs(), 'updatedAt': nowMs()}
    ]);
    if (jagaId == id) prefs.remove('kilaw_dokter_jaga');
  }

  void setJaga(String id) {
    prefs.setString('kilaw_dokter_jaga', id);
    notifyListeners();
  }

  // ---------------- Odontogram ----------------
  OdoModel? _odo;
  OdoModel get odo => _odo ??= OdoModel(odoState, harga);
  void odoSaved() {
    _persist('odo_state');
    _persist('odo_harga');
  }

  void odoChanged() {
    odoSaved();
    notifyListeners();
  }

  // ---------------- Pengaturan ----------------
  Future<void> saveConfig(String u, String t) async {
    _cfg = {'url': u.trim(), 'token': t.trim()};
    await prefs.setString('kilaw_appscript_source', jsonEncode(_cfg));
    notifyListeners();
  }

  Future<void> setLight(bool v) async {
    lightTheme = v;
    await prefs.setString('kilaw_theme', v ? 'light' : 'dark');
    notifyListeners();
  }

  Future<void> saveSig(String b64) async => prefs.setString('kilaw_sig_png', b64);

  // ---------------- Gabung data dari Drive (LWW per rekaman) ----------------
  /// Menggabungkan [remote] ke dataset lokal. Rekaman terbaru (updatedAt) menang;
  /// penghapusan (tomb) dihormati bila lebih baru dari rekaman. Mengembalikan true bila ada perubahan lokal.
  bool mergeRemote(String set, List<Rec> remote, Map<String, int> remoteTomb) {
    final list = data[set]!;
    final idx = <String, int>{};
    for (var i = 0; i < list.length; i++) {
      idx[keyOf(set, list[i])] = i;
    }
    var changed = false;
    final lt = tomb[set]!;
    // hapus lokal bila ada tomb remote lebih baru
    remoteTomb.forEach((k, t) {
      final i = idx[k];
      if (i != null && n(list[i]['updatedAt']) < t) {
        list[i] = {'__del': true};
        changed = true;
      }
      if ((lt[k] ?? 0) < t) {
        lt[k] = t;
        changed = true;
      }
    });
    list.removeWhere((r) => r['__del'] == true);
    idx.clear();
    for (var i = 0; i < list.length; i++) {
      idx[keyOf(set, list[i])] = i;
    }
    for (final r in remote) {
      final k = keyOf(set, r);
      if (k.isEmpty) continue;
      final tt = lt[k];
      if (tt != null && tt >= n(r['updatedAt'])) continue; // sudah dihapus lokal
      final i = idx[k];
      if (i == null) {
        list.add(r);
        idx[k] = list.length - 1;
        changed = true;
      } else if (n(r['updatedAt']) > n(list[i]['updatedAt'])) {
        list[i] = r;
        changed = true;
      }
    }
    if (changed) {
      rev[set] = (rev[set] ?? 0) + 1;
      _persist(set);
      _persist('tomb');
    }
    return changed;
  }

  bool mergeAntrian(Map remote) {
    final local = aqItems;
    final byId = {for (final i in local) s(i['id']): i};
    var changed = false;
    final lt = tomb['antrian']!;
    final rt = remote['tomb'];
    if (rt is Map) {
      rt.forEach((k, v) {
        final t = (v as num).toInt();
        final i = byId[s(k)];
        if (i != null && n(i['u']) < t) {
          byId.remove(s(k));
          changed = true;
        }
        if ((lt[s(k)] ?? 0) < t) lt[s(k)] = t;
      });
    }
    for (final raw in (remote['items'] as List? ?? [])) {
      final r = Map<String, dynamic>.from(raw as Map);
      final k = s(r['id']);
      final tt = lt[k];
      if (tt != null && tt >= n(r['u'])) continue;
      final cur = byId[k];
      if (cur == null || n(r['u']) > n(cur['u'])) {
        byId[k] = r;
        changed = true;
      }
    }
    if (changed) {
      final items = byId.values.toList()..sort((a, b) => n(a['no']).compareTo(n(b['no'])));
      antrian['items'] = items;
      antrian['seq'] = items.length > n(antrian['seq']) ? items.length : antrian['seq'];
      rev['antrian'] = (rev['antrian'] ?? 0) + 1;
      _persist('antrian');
      _persist('tomb');
    }
    return changed;
  }

  void notifyExternal() => notifyListeners();

  // ---------------- Nomor RM untuk antrian ----------------
  int nextRm() {
    var mx = highestRm();
    for (final i in aqItems) {
      final v = int.tryParse(s(i['rm']));
      if (v != null && v > mx) mx = v;
    }
    for (final c in stage) {
      final v = int.tryParse(s(c['rm']));
      if (v != null && v > mx) mx = v;
    }
    return mx + 1;
  }

  bool inQueue(String rm) => aqItems.any((i) => s(i['rm']) == rm);

  /// Pasien yang belum lengkap datanya.
  List<Rec> get pasienBelumLengkap => pasien.where((p) => p['isIncomplete'] == true).toList();

  List<Rec> cariPasien(String q) => searchPatients(pasien, q);
}
