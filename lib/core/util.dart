import 'dart:math';

typedef Rec = Map<String, dynamic>;

final _rnd = Random();
String newId(String p) =>
    p + DateTime.now().millisecondsSinceEpoch.toRadixString(36) + List.generate(5, (_) => _rnd.nextInt(36).toRadixString(36)).join();

String s(dynamic v) => v == null ? '' : v.toString();
num n(dynamic v) {
  if (v is num) return v;
  return num.tryParse(s(v).trim().replaceAll(',', '.')) ?? 0;
}

int nowMs() => DateTime.now().millisecondsSinceEpoch;
String pad2(int v) => v.toString().padLeft(2, '0');

const bulanNama = ['Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'];
const hariNama = ['Minggu', 'Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu'];

String groupId(int v) {
  final neg = v < 0;
  final str = v.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < str.length; i++) {
    if (i > 0 && (str.length - i) % 3 == 0) b.write('.');
    b.write(str[i]);
  }
  return (neg ? '-' : '') + b.toString();
}

String rupiah(num v) => 'Rp ${groupId(v.round())}';

/// Nominal di data disimpan dalam ribuan (250 = Rp 250.000).
String rp(num k) => 'Rp ${groupId((k * 1000).round())}';

String isoOf(DateTime d) => '${d.year}-${pad2(d.month)}-${pad2(d.day)}';
String todayIso() => isoOf(DateTime.now());
String isoDaysAgo(int k) => isoOf(DateTime.now().subtract(Duration(days: k)));

final _isoRe = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
final _dmyRe = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{2,4})$');

DateTime? parseIso(String? iso) {
  final m = _isoRe.firstMatch(s(iso));
  if (m == null) return null;
  return DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
}

String hariFromIso(String? iso) {
  final d = parseIso(iso);
  return d == null ? '' : hariNama[d.weekday % 7];
}

String fmtIsoShort(String? iso) {
  final m = _isoRe.firstMatch(s(iso));
  return m == null ? '-' : '${m[3]}/${m[2]}/${m[1]!.substring(2)}';
}

String tglID([String? iso]) {
  final d = (iso != null && iso.isNotEmpty ? parseIso(iso) : null) ?? DateTime.now();
  return '${d.day} ${bulanNama[d.month - 1]} ${d.year}';
}

/// yyyy-MM-dd -> dd/MM/yy
String isoToDmy(String? v) {
  final m = _isoRe.firstMatch(s(v));
  return m == null ? '' : '${m[3]}/${m[2]}/${m[1]!.substring(2)}';
}

/// dd/MM/yy -> yyyy-MM-dd
String dmyToIso(String? v) {
  final m = _dmyRe.firstMatch(s(v));
  if (m == null) return '';
  var y = int.parse(m[3]!);
  if (y < 100) y += 2000;
  return '$y-${pad2(int.parse(m[2]!))}-${pad2(int.parse(m[1]!))}';
}

String dmyOf(DateTime d) => '${pad2(d.day)}/${pad2(d.month)}/${pad2(d.year % 100)}';

/// kunci urut yyyymmdd dari dd/mm/yy(yy)
String dateKey(String? t) {
  final m = _dmyRe.firstMatch(s(t));
  if (m == null) return '';
  final yy = m[3]!.length == 2 ? '20${m[3]}' : m[3]!;
  return '$yy${pad2(int.parse(m[2]!))}${pad2(int.parse(m[1]!))}';
}

/// yyyy-MM dari dd/mm/yy(yy)
String ymOfDmy(String? t) {
  final k = dateKey(t);
  return k.length == 8 ? '${k.substring(0, 4)}-${k.substring(4, 6)}' : '';
}

String ageDigits(dynamic umur) {
  final m = RegExp(r'\d+').firstMatch(s(umur));
  return m == null ? '' : m[0]!;
}

String normNoFile(dynamic v) {
  var t = s(v).trim();
  if (RegExp(r'^\d+\.0$').hasMatch(t)) t = t.substring(0, t.length - 2);
  return t;
}

String normUmur(dynamic v) {
  if (v == null || s(v).isEmpty) return '';
  final t = s(v).trim();
  if (RegExp(r'^\d+(\.0)?$').hasMatch(t)) {
    final k = double.parse(t).round();
    final yr = DateTime.now().year;
    if (k >= 1900 && k <= yr) return '${yr - k} th';
    return '$k th';
  }
  return t;
}

String ageFromDob(String? iso) {
  final d = parseIso(iso);
  if (d == null) return '';
  final now = DateTime.now();
  var a = now.year - d.year;
  if (now.month < d.month || (now.month == d.month && now.day < d.day)) a--;
  return a >= 0 && a < 130 ? '$a th' : '';
}

double round3(num v) => (v * 1000).round() / 1000;
String fmtQty(num v) {
  final r = round3(v);
  final t = r == r.roundToDouble() ? r.round().toString() : r.toString();
  return t.replaceAll('.', ',');
}

/// "250" atau "250.000" sama-sama jadi 250 (= Rp 250.000).
int toK(dynamic v) {
  final k = int.tryParse(s(v).replaceAll(RegExp(r'\D'), '')) ?? 0;
  return k >= 10000 ? (k / 1000).round() : k;
}

String safeFileName(String v) => v.replaceAll(RegExp(r'[\\/:*?"<>|]'), '').trim();
String fname(List<dynamic> p) =>
    p.map((x) => safeFileName(s(x))).where((x) => x.isNotEmpty).join('-').replaceAll(RegExp(r'\s+'), '-');

String ph(dynamic v) => s(v).trim() == '0' ? '' : s(v);

T? firstWhereOrNull<T>(Iterable<T> it, bool Function(T) f) {
  for (final x in it) {
    if (f(x)) return x;
  }
  return null;
}

String normNama(dynamic v) => s(v).trim().toLowerCase();
