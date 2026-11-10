import 'util.dart';

const ua = [18, 17, 16, 15, 14, 13, 12, 11, 21, 22, 23, 24, 25, 26, 27, 28];
const la = [48, 47, 46, 45, 44, 43, 42, 41, 31, 32, 33, 34, 35, 36, 37, 38];
const ud = [55, 54, 53, 52, 51, 61, 62, 63, 64, 65];
const ld = [85, 84, 83, 82, 81, 71, 72, 73, 74, 75];
// [daftar gigi, kolom awal, y]
const odoRows = <(List<int>, int, int)>[(ud, 3, 20), (ua, 0, 85), (la, 0, 175), (ld, 3, 240)];
final List<int> allTeeth = [...ua, ...ud, ...la, ...ld];
const cyc = ['PR', 'PI', 'NP'];
const arLabel = {'atas': 'RA', 'bawah': 'RB'};
const kelLabel = {'lepasan': 'Lepasan', 'permanen': 'Permanen', 'full': 'Full denture (per rahang)'};

List<Rec> defaultHarga() => [
      {'id': 'tam_ant', 'nama': 'Tambal anterior', 'k': 'tambal', 'z': 'ant', 'h': '0'},
      {'id': 'tam_post', 'nama': 'Tambal posterior', 'k': 'tambal', 'z': 'post', 'h': '0'},
      {'id': 'psa', 'nama': 'PSA kunjungan awal', 'k': 'psa', 'h': '200', 'n': 2},
      {'id': 'exo', 'nama': 'EXO umum', 'k': 'cabut', 'h': '150', 'hb': '', 's8': false},
      {'id': 'odonto', 'nama': 'Odontectomy', 'k': 'cabut', 'h': '0', 'hb': '', 's8': true},
      {'id': 'akrilik', 'nama': 'Akrilik', 'k': 'lepasan', 'h': '700', 'a': '200'},
      {'id': 'valplast', 'nama': 'Valplast', 'k': 'lepasan', 'h': '800', 'a': '200'},
      {'id': 'termosen', 'nama': 'Termosen', 'k': 'lepasan', 'h': '1250', 'a': '250'},
      {'id': 'pfm', 'nama': 'PFM', 'k': 'permanen', 'h': '1250'},
      {'id': 'emax', 'nama': 'E.max', 'k': 'permanen', 'h': '2500'},
      {'id': 'zirkonia', 'nama': 'Zirkonia', 'k': 'permanen', 'h': '3000'},
      {'id': 'full', 'nama': 'Full denture', 'k': 'full', 'h': '3000'},
    ];

String arch(int t) => [1, 2, 5, 6].contains(t ~/ 10) ? 'atas' : 'bawah';

typedef Rng = (double, double);
Rng rng(dynamic v) {
  final m = RegExp(r'^(\d+(?:[.,]\d+)?)(?:[-\u2013](\d+(?:[.,]\d+)?))?$').firstMatch(s(v).replaceAll(RegExp(r'\s'), ''));
  if (m == null) return (0, 0);
  final a = double.parse(m[1]!.replaceAll(',', '.'));
  final b = m[2] != null ? double.parse(m[2]!.replaceAll(',', '.')) : a;
  return a <= b ? (a, b) : (b, a);
}

String fr(Rng r) => r.$1 == r.$2 ? rp(r.$1) : '${rp(r.$1)} - ${groupId((r.$2 * 1000).round())}';
Rng sc(Rng r, num k) => (r.$1 * k, r.$2 * k);
Rng ad(Rng a, Rng b) => (a.$1 + b.$1, a.$2 + b.$2);

class OdoCalc {
  String jenis = '', cat = '';
  Rng tot = (0, 0);
  List<List<String>> lines = [];
}

/// Seluruh logika odontogram (state S + daftar harga H) dalam satu kelas.
class OdoModel {
  Rec S;
  List<Rec> H;
  OdoModel(this.S, this.H) {
    S['p'] ??= <String, dynamic>{};
    S['t'] ??= <String, dynamic>{};
    S['g'] ??= <String, dynamic>{};
    S['gt'] ??= <String, dynamic>{};
    if (S['peg'] is! Map) S['peg'] = {'atas': 0, 'bawah': 0};
    if (S['ex'] is! List) S['ex'] = [];
    S['mode'] ??= 'tambal';
    S['zoom'] ??= 1.0;
    S['exoKind'] ??= 'exo';
    S['gtId'] ??= '';
    S['prId'] ??= '';
    (S['gt'] as Map)['atas'] ??= 'valplast';
    (S['gt'] as Map)['bawah'] ??= 'akrilik';
    for (final d in defaultHarga().where((d) => d['k'] == 'tambal' || d['k'] == 'psa')) {
      if (!H.any((x) => x['id'] == d['id'])) H.insert(0, Map<String, dynamic>.from(d));
    }
  }

  Map get t => S['t'] as Map;
  Map get g => S['g'] as Map;
  Map get gtSel => S['gt'] as Map;
  Map get peg => S['peg'] as Map;
  List get ex => S['ex'] as List;
  Map get pat => S['p'] as Map;

  Rec? tooth(int n) => t['$n'] == null ? null : Map<String, dynamic>.from(t['$n'] as Map);
  bool hasGt(int n) => g['$n'] != null;

  List<Rec> cab() => H.where((x) => x['k'] == 'cabut').toList();
  String xk(Map tt) => (tt['k'] == null || tt['k'] == '' || tt['k'] == 'umum') ? 'exo' : s(tt['k']);
  Rec xi(Map tt) {
    final k = xk(tt);
    return firstWhereOrNull(cab(), (x) => x['id'] == k) ?? (cab().isNotEmpty ? cab().first : {'id': 'exo', 'nama': 'EXO umum', 'h': '0'});
  }

  Rec? curExo() {
    final c = cab();
    final id = S['exoKind'] == 'umum' ? 'exo' : s(S['exoKind']);
    return firstWhereOrNull(c, (x) => x['id'] == id) ?? (c.isNotEmpty ? c.first : null);
  }

  Rec item(String a) {
    final re = RegExp(r'^(lepasan|permanen|full)$');
    return firstWhereOrNull(H, (h) => h['id'] == gtSel[a] && re.hasMatch(s(h['k']))) ??
        firstWhereOrNull(H, (h) => re.hasMatch(s(h['k']))) ??
        {'id': '', 'nama': '-', 'k': 'lepasan', 'h': '0', 'a': '0'};
  }

  Rng zp(String z) {
    final it = firstWhereOrNull(H, (x) => x['k'] == 'tambal' && x['z'] == z);
    return rng(it != null ? it['h'] : 0);
  }

  /// Ketuk gigi. Mengembalikan pesan bila ada penolakan.
  String? tap(int n) {
    final m = s(S['mode']);
    final cur = t['$n'] as Map?;
    if (m == 'hapus') {
      t.remove('$n');
      g.remove('$n');
    } else if (m == 'gt') {
      if (g['$n'] != null) {
        g.remove('$n');
      } else {
        g['$n'] = 1;
      }
    } else if (m == 'tambal') {
      if (cur == null || cur['s'] != 'tambal') {
        t['$n'] = {'s': 'tambal', 'k': 'PR'};
      } else {
        final i = cyc.indexOf(s(cur['k'])) + 1;
        if (i >= cyc.length) {
          t.remove('$n');
        } else {
          cur['k'] = cyc[i];
        }
      }
    } else if (m == 'exo') {
      final it = curExo();
      if (it == null) return 'Belum ada jenis cabut di tab Harga';
      if (it['s8'] == true && n % 10 != 8) return '${it['nama']} hanya untuk gigi 8';
      if (cur != null && cur['s'] == 'exo' && xi(cur)['id'] == it['id']) {
        t.remove('$n');
      } else {
        t['$n'] = {'s': 'exo', 'k': it['id']};
      }
    } else {
      if (cur != null && cur['s'] == m) {
        t.remove('$n');
      } else {
        t['$n'] = {'s': m};
      }
    }
    return null;
  }

  void full(String a, List<int> list) {
    final done = list.every((n) => g['$n'] != null);
    final fl = firstWhereOrNull(H, (x) => x['k'] == 'full');
    for (final n in list) {
      if (done) {
        g.remove('$n');
      } else {
        g['$n'] = 1;
      }
    }
    if (!done && fl != null) gtSel[a] = fl['id'];
  }

  void clearChart() {
    S['t'] = <String, dynamic>{};
    S['g'] = <String, dynamic>{};
    S['peg'] = {'atas': 0, 'bawah': 0};
  }

  Map snapshot() => {
        't': Map<String, dynamic>.from(t.map((k, v) => MapEntry('$k', v is Map ? Map<String, dynamic>.from(v) : v))),
        'g': Map<String, dynamic>.from(g),
        'gt': Map<String, dynamic>.from(gtSel),
        'peg': Map<String, dynamic>.from(peg),
        'ex': ex.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
      };

  void loadSnapshot(Map? snap, Map<String, dynamic> p) {
    snap ??= {};
    S['p'] = {'rm': s(p['rm']), 'nama': s(p['nama']), 'alamat': s(p['alamat']), 'telp': s(p['telp'])};
    S['t'] = Map<String, dynamic>.from(((snap['t'] ?? {}) as Map).map((k, v) => MapEntry('$k', v is Map ? Map<String, dynamic>.from(v) : v)));
    S['g'] = Map<String, dynamic>.from((snap['g'] ?? {}) as Map);
    S['gt'] = Map<String, dynamic>.from((snap['gt'] ?? {}) as Map);
    S['peg'] = snap['peg'] is Map ? Map<String, dynamic>.from(snap['peg'] as Map) : {'atas': 0, 'bawah': 0};
    S['ex'] = ((snap['ex'] ?? []) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    S['gtId'] = '';
    S['prId'] = '';
    gtSel['atas'] ??= 'valplast';
    gtSel['bawah'] ??= 'akrilik';
  }

  void resetPatient() {
    S['p'] = <String, dynamic>{};
    clearChart();
    S['gtId'] = '';
    S['prId'] = '';
    S['ex'] = [];
  }

  ({Map<String, int> G, Map<String, Map<String, int>> X}) cnt() {
    final G = {'atas': 0, 'bawah': 0};
    final X = <String, Map<String, int>>{};
    for (final n in allTeeth) {
      if (g['$n'] != null) G[arch(n)] = G[arch(n)]! + 1;
      final tt = t['$n'] as Map?;
      if (tt != null && tt['s'] == 'exo') {
        final k = s(xi(tt)['id']);
        X.putIfAbsent(k, () => {'atas': 0, 'bawah': 0});
        X[k]![arch(n)] = X[k]![arch(n)]! + 1;
      }
    }
    return (G: G, X: X);
  }

  OdoCalc calc() {
    final c = cnt();
    final o = OdoCalc();
    final jenis = <String>[], cat = <String>[];
    void add(String lbl, String det, Rng r) {
      o.tot = ad(o.tot, r);
      o.lines.add([lbl, det, fr(r)]);
    }

    String nb(Rng r) => r.$2 != 0 ? '' : ' (harga belum diisi)';
    for (final a in ['atas', 'bawah']) {
      final k = c.G[a]!;
      if (k == 0) continue;
      final h = item(a);
      final pe = (peg[a] ?? 0) as int;
      final hp = rng(h['h']), ap = rng(h['a']);
      Rng v;
      String d;
      int u;
      if (h['k'] == 'permanen') {
        u = k + pe;
        v = sc(hp, u);
        d = '$k + $pe pegangan = $u unit x ${fr(hp)}${pe > 0 ? ' (bridge)' : ' (crown)'}';
      } else if (h['k'] == 'full') {
        u = 0;
        v = hp;
        d = '1 rahang, flat';
      } else {
        u = k;
        v = ad(hp, sc(ap, k - 1));
        d = '$k gigi: dasar ${fr(hp)}${k > 1 ? ' + ${k - 1} x ${fr(ap)}' : ''}';
      }
      jenis.add('${h['nama']} (${arLabel[a]})');
      cat.add('${arLabel[a]}${h['k'] == 'full' ? ' full denture' : ' $u unit'}');
      add('${arLabel[a]} ${h['nama']}', d, v);
    }
    final tm = {'ant': <int>[], 'post': <int>[]}, ps = {'ant': <int>[], 'post': <int>[]};
    const Z = {'ant': 'anterior', 'post': 'posterior'};
    final psa = firstWhereOrNull(H, (x) => x['k'] == 'psa') ?? {'h': '0', 'n': 0};
    for (final n in allTeeth) {
      final tt = t['$n'] as Map?;
      if (tt != null && tt['s'] == 'tambal') {
        (tt['k'] == 'PR' ? tm : ps)[n % 10 <= 3 ? 'ant' : 'post']!.add(n);
      }
    }
    for (final z in ['ant', 'post']) {
      final l = tm[z]!;
      final p = zp(z);
      if (l.isNotEmpty) add('Tambal ${Z[z]} ${l.length} gigi', '${l.length} x ${fr(p)}${nb(p)}', sc(p, l.length));
    }
    for (final z in ['ant', 'post']) {
      final l = ps[z]!;
      if (l.isEmpty) continue;
      final p = zp(z), v = rng(psa['h']);
      final nn = (psa['n'] ?? 0) as int;
      final per = ad(sc(v, nn), p);
      add('PSA ${Z[z]} ${l.length} gigi (${l.join(', ')})',
          '$nn kunjungan x ${fr(v)} + kunjungan akhir tambal ${Z[z]} ${fr(p)}${nb(p)}', sc(per, l.length));
    }
    for (final it in cab()) {
      for (final a in ['atas', 'bawah']) {
        final q = c.X[it['id']]?[a];
        if (q == null || q == 0) continue;
        final p = rng(a == 'bawah' && s(it['hb']).isNotEmpty ? it['hb'] : it['h']);
        add('${it['nama']} ${arLabel[a]} $q gigi', '$q x ${fr(p)}${nb(p)}', sc(p, q));
      }
    }
    for (final e in ex) {
      final it = firstWhereOrNull(H, (x) => x['id'] == (e as Map)['id']);
      if (it == null) continue;
      final p = rng(it['h']);
      final q = (e['q'] ?? 1) as int;
      add('${it['nama']} x $q', '${fr(p)}${nb(p)}', sc(p, q));
    }
    o.jenis = jenis.join(', ');
    o.cat = cat.join(', ');
    return o;
  }

  List<String> notes() {
    final L = <String>[];
    List<int> l(bool Function(int) fn) => allTeeth.where(fn).toList();
    bool T(String st, int n) => (t['$n'] as Map?)?['s'] == st;
    final tm = l((n) => T('tambal', n)), cb = l((n) => T('cabut', n));
    if (tm.isNotEmpty) L.add('Pro tambal: ${tm.map((n) => '$n (${(t['$n'] as Map)['k']})').join(', ')}');
    for (final it in cab()) {
      final e = l((n) => T('exo', n) && xi(t['$n'] as Map)['id'] == it['id']);
      if (e.isNotEmpty) L.add('${it['id'] == 'exo' ? 'Pro EXO' : 'Pro ${it['nama']}'}: ${e.join(', ')}');
    }
    if (cb.isNotEmpty) L.add('Sudah dicabut: ${cb.join(', ')}');
    for (final a in ['atas', 'bawah']) {
      final gg = l((n) => g['$n'] != null && arch(n) == a);
      if (gg.isNotEmpty) L.add('Pro GT ${arLabel[a]}: ${gg.join(', ')} [${item(a)['nama']}]');
    }
    final o = calc();
    if (o.cat.isNotEmpty) L.add('GT: ${o.cat}');
    return L.isNotEmpty ? L : ['Belum ada gigi yang ditandai.'];
  }

  /// Rencana untuk Prospek: {list, worthy}
  ({List<String> list, bool worthy}) plan() {
    final c = cnt();
    final pr = <String>[], rest = <String>[];
    for (final a in ['atas', 'bawah']) {
      if (c.G[a] == 0) continue;
      final h = item(a);
      final u = c.G[a]! + ((peg[a] ?? 0) as int);
      final tx = '${h['nama']} ${arLabel[a]}${h['k'] == 'full' ? ' full denture' : ' ${h['k'] == 'permanen' ? u : c.G[a]} unit'}';
      (h['k'] == 'permanen' ? pr : rest).add(tx);
    }
    final ex = <String, ({Rec it, List<int> l})>{};
    for (final n in allTeeth) {
      final tt = t['$n'] as Map?;
      if (tt != null && tt['s'] == 'exo') {
        final it = xi(tt);
        final k = s(it['id']);
        final cur = ex[k];
        if (cur == null) {
          ex[k] = (it: it, l: [n]);
        } else {
          cur.l.add(n);
        }
      }
    }
    ex.forEach((k, e) {
      final b = e.l.where((n) => n % 10 == 8).toList(), o = e.l.where((n) => n % 10 != 8).toList();
      if (b.isNotEmpty) pr.add('${e.it['s8'] == true ? e.it['nama'] : 'Cabut gigi bungsu'} ${b.join(', ')}');
      if (o.isNotEmpty) rest.add('${e.it['nama']} ${o.join(', ')}');
    });
    return pr.isNotEmpty ? (list: pr, worthy: true) : (list: rest, worthy: false);
  }
}
