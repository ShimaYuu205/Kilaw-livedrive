import 'util.dart';

// Mesin pencarian bertingkat: Sama persis -> Mirip/mendekati -> Lainnya.
const _genderWords = {
  'l': ['l', 'laki', 'laki-laki', 'lelaki', 'pria', 'cowok', 'cowek', 'ikhwan'],
  'p': ['p', 'perempuan', 'wanita', 'cewek', 'cewe', 'akhwat'],
};
const _unitWords = {'th', 'thn', 'tahun', 'thun'};
final Map<String, String> genderLookup = () {
  final m = <String, String>{};
  _genderWords.forEach((g, ws) {
    for (final w in ws) {
      m[w] = g;
    }
  });
  return m;
}();

const _diac = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ç': 'c', 'ñ': 'n',
};

String norm(dynamic v) {
  var t = s(v).toLowerCase();
  if (RegExp(r'[^\x00-\x7F]').hasMatch(t)) {
    final b = StringBuffer();
    for (final r in t.runes) {
      final ch = String.fromCharCode(r);
      b.write(_diac[ch] ?? ch);
    }
    t = b.toString();
  }
  return t.replaceAll(RegExp("['\u2019`]"), '').replaceAll(RegExp(r'\s+'), ' ').trim();
}

List<String> splitWords(String v) => norm(v).split(RegExp(r'[^a-z0-9]+')).where((x) => x.isNotEmpty).toList();

/// Kunci fonetik: Achmad=Ahmad, Soetrisno=Sutrisno, Djoko=Joko, Zaenal=Jainal, Putri=Putry.
String phon(String w) {
  return w
      .replaceAll('dj', 'j')
      .replaceAll('tj', 'c')
      .replaceAll('oe', 'u')
      .replaceAll('ph', 'f')
      .replaceAll('sy', 's')
      .replaceAllMapped(RegExp(r'[ck]h'), (_) => 'h')
      .replaceAll('q', 'k')
      .replaceAll('c', 'k')
      .replaceAll('x', 'ks')
      .replaceAll('v', 'f')
      .replaceAll('z', 'j')
      .replaceAll('y', 'i')
      .replaceAllMapped(RegExp(r'a[ei]'), (_) => 'e')
      .replaceAllMapped(RegExp(r'(.)\1+'), (m) => m[1]!);
}

/// 0812-xxx / +62812xxx / 812xxx -> 0812xxx
String normPhone(dynamic v) {
  var d = s(v).replaceAll(RegExp(r'\D'), '');
  if (d.startsWith('62')) {
    d = '0${d.substring(2)}';
  } else if (d.isNotEmpty && d[0] == '8') {
    d = '0$d';
  }
  return d;
}

/// Jarak edit Damerau dengan batas.
int editDistance(String a, String b, int max) {
  if (a == b) return 0;
  final la = a.length, lb = b.length;
  if ((la - lb).abs() > max) return max + 1;
  var pp = List<int>.filled(lb + 1, 0);
  var prev = List<int>.generate(lb + 1, (j) => j);
  var cur = List<int>.filled(lb + 1, 0);
  var prevMin = 0;
  for (var i = 1; i <= la; i++) {
    cur[0] = i;
    var rowMin = i;
    for (var j = 1; j <= lb; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      var v = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost].reduce((x, y) => x < y ? x : y);
      if (i > 1 && j > 1 && a.codeUnitAt(i - 1) == b.codeUnitAt(j - 2) && a.codeUnitAt(i - 2) == b.codeUnitAt(j - 1)) {
        if (pp[j - 2] + 1 < v) v = pp[j - 2] + 1;
      }
      cur[j] = v;
      if (v < rowMin) rowMin = v;
    }
    if (rowMin > max && prevMin > max) return max + 1;
    prevMin = rowMin;
    final tmp = pp;
    pp = prev;
    prev = cur;
    cur = tmp;
  }
  return prev[lb];
}

int fuzzyLimit(int len) => len < 4 ? 0 : len <= 5 ? 1 : len <= 8 ? 2 : 3;

bool fuzzyWordHit(String token, List<String> words) {
  final lim = fuzzyLimit(token.length);
  if (lim == 0) return false;
  for (final w in words) {
    if (editDistance(token, w, lim) <= lim) return true;
    if (w.length > token.length + lim && editDistance(token, w.substring(0, token.length), lim) <= lim) return true;
  }
  return false;
}

class _Idx {
  final String sig;
  final String nama, alamat, telpRaw, telp, noFile, umur, namaJoin, namaPj, alamatPj;
  final List<String> namaW, alamatW, namaP, alamatP;
  _Idx(this.sig, this.nama, this.alamat, this.telpRaw, this.telp, this.noFile, this.umur, this.namaJoin, this.namaPj,
      this.alamatPj, this.namaW, this.alamatW, this.namaP, this.alamatP);
}

final Expando<_Idx> _cache = Expando<_Idx>('searchIdx');

_Idx _fieldsFor(Rec p) {
  final sig = [p['noFile'], p['nama'], p['alamat'], p['telp'], p['umur']].map(s).join('\u0001');
  final c = _cache[p];
  if (c != null && c.sig == sig) return c;
  final nama = norm(p['nama']), alamat = norm(p['alamat']);
  final namaW = splitWords(nama), alamatW = splitWords(alamat);
  final namaP = namaW.map(phon).toList(), alamatP = alamatW.map(phon).toList();
  final f = _Idx(sig, nama, alamat, s(p['telp']).replaceAll(RegExp(r'\D'), ''), normPhone(p['telp']), s(p['noFile']),
      ageDigits(p['umur']), namaW.join(''), namaP.join(' '), alamatP.join(' '), namaW, alamatW, namaP, alamatP);
  _cache[p] = f;
  return f;
}

int rmCompare(Rec a, Rec b) {
  final na = int.tryParse(s(a['noFile'])), nb = int.tryParse(s(b['noFile']));
  if (na != null && nb != null) {
    final d = na - nb;
    return d != 0 ? d : s(a['noFile']).compareTo(s(b['noFile']));
  }
  if (na != null) return -1;
  if (nb != null) return 1;
  return s(a['noFile']).compareTo(s(b['noFile']));
}

int? _nameTier(_Idx f, String token) {
  if (f.nama == token) return 0;
  if (f.nama.startsWith(token)) return 1;
  for (final w in f.namaW) {
    if (w.startsWith(token)) return 2;
  }
  if (f.nama.contains(token)) return 3;
  return null;
}

final _digits = RegExp(r'^\d+$');

/// 0 = sama persis, 1 = mirip, -1 = tidak cocok
int _tokenScore(Rec p, String token, _Idx f) {
  if (_unitWords.contains(token)) return 0;
  final isGender = genderLookup.containsKey(token);
  if (isGender && p['gender'] == genderLookup[token]) return 0;
  if (isGender && token.length == 1) return -1;

  if (_digits.hasMatch(token)) {
    final tp = token.length >= 7 ? normPhone(token) : token;
    if (f.noFile == token || f.umur == token || f.telp == tp || f.telpRaw == token) return 0;
    if (f.namaW.contains(token) || f.alamatW.contains(token)) return 0;
    if (token.length >= 3) {
      if (f.noFile.contains(token) || f.telp.contains(tp) || f.telpRaw.contains(token)) return 1;
    }
    if (token.length >= 4 && token.length <= 6 && f.noFile.isNotEmpty && editDistance(token, f.noFile, 1) <= 1) return 1;
    return -1;
  }

  if (f.namaW.contains(token) || f.alamatW.contains(token)) return 0;
  if (f.nama.contains(token) || f.alamat.contains(token)) return 1;
  if (f.telp.contains(token) || f.noFile.contains(token)) return 1;

  final tpk = phon(token);
  if (f.namaP.contains(tpk) || f.alamatP.contains(tpk)) return 1;
  if (tpk.length >= 3 && (f.namaPj.contains(tpk) || f.alamatPj.contains(tpk))) return 1;
  if (token.length >= 5 && f.namaJoin.contains(token)) return 1;
  if (fuzzyWordHit(token, f.namaW) || fuzzyWordHit(token, f.alamatW)) return 1;
  if (fuzzyWordHit(tpk, f.namaP) || fuzzyWordHit(tpk, f.alamatP)) return 1;
  return -1;
}

bool _isStrong(String tok) {
  if (_unitWords.contains(tok) || genderLookup.containsKey(tok)) return false;
  if (_digits.hasMatch(tok)) return tok.length >= 3;
  return true;
}

class SearchResult {
  final List<Rec> exact, similar, other;
  SearchResult(this.exact, this.similar, this.other);
  bool get isEmpty => exact.isEmpty && similar.isEmpty && other.isEmpty;
  int get total => exact.length + similar.length + other.length;
}

class _Hit {
  final Rec p;
  final double tier;
  _Hit(this.p, this.tier);
}

SearchResult searchPatientsGrouped(List<Rec> pasien, String query, {bool relevanceOnly = false}) {
  final q = norm(query).replaceAllMapped(RegExp(r'(\d+)(th|thn|tahun)\b'), (m) => '${m[1]} ${m[2]}');
  final tokens = q.split(RegExp(r'[,\s]+')).where((x) => x.isNotEmpty).toList();
  final meaningful = tokens.where((t) => !_unitWords.contains(t)).toList();
  if (meaningful.isEmpty) return SearchResult([], [], []);
  final exact = <_Hit>[], similar = <_Hit>[], other = <_Hit>[];

  for (final p in pasien) {
    final f = _fieldsFor(p);
    final rmHit = meaningful.any((t) => f.noFile.isNotEmpty && f.noFile == t);
    final telpHit = !rmHit &&
        f.telp.isNotEmpty &&
        meaningful.any((t) => f.telp == t || (t.length >= 7 && f.telp == normPhone(t)));

    var allMatch = true;
    var matched = 0, strong = 0, worst = 0;
    for (final t in meaningful) {
      final sc = _tokenScore(p, t, f);
      if (sc < 0) {
        allMatch = false;
        continue;
      }
      matched++;
      if (_isStrong(t)) strong++;
      if (sc > worst) worst = sc;
    }

    var tier = 5;
    for (final tok in meaningful) {
      if (_digits.hasMatch(tok) || genderLookup.containsKey(tok)) continue;
      final nt = _nameTier(f, tok);
      final v = nt ?? 4;
      if (v < tier) tier = v;
    }

    if (rmHit || telpHit) {
      exact.add(_Hit(p, (rmHit ? -20 : -10) + tier * 0.01));
    } else if (allMatch) {
      (worst == 0 ? exact : similar).add(_Hit(p, tier.toDouble()));
    } else if (meaningful.length > 1 && strong > 0) {
      other.add(_Hit(p, (10 - matched).toDouble()));
    }
  }

  int byRelevance(_Hit a, _Hit b) {
    final d = a.tier.compareTo(b.tier);
    return d != 0 ? d : s(a.p['nama']).compareTo(s(b.p['nama']));
  }

  int byRm(_Hit a, _Hit b) => rmCompare(a.p, b.p);
  int byTierThenRm(_Hit a, _Hit b) {
    final d = a.tier.compareTo(b.tier);
    return d != 0 ? d : rmCompare(a.p, b.p);
  }

  List<Rec> sorted(List<_Hit> l, int Function(_Hit, _Hit) cmp) {
    l.sort(cmp);
    return l.map((x) => x.p).toList();
  }

  return SearchResult(
    sorted(exact, byRelevance),
    sorted(similar, relevanceOnly ? byRelevance : byRm),
    sorted(other, relevanceOnly ? byRelevance : byTierThenRm),
  );
}

List<Rec> searchPatients(List<Rec> pasien, String query) {
  final g = searchPatientsGrouped(pasien, query, relevanceOnly: true);
  return [...g.exact, ...g.similar];
}
