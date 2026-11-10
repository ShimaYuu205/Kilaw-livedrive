import 'util.dart';

class Pay {
  int biaya, cash, qr;
  String bank, metode;
  Pay(this.biaya, this.cash, this.qr, this.bank, this.metode);
}

String detectBank(String low) {
  if (RegExp(r'\bbca\b').hasMatch(low)) return 'BCA';
  if (RegExp(r'\bmandiri\b').hasMatch(low)) return 'Mandiri';
  if (RegExp(r'(^|[^a-z])b([^a-z]|$)').hasMatch(low)) return 'BCA'; // "B" = BCA
  if (RegExp(r'(^|[^a-z])m([^a-z]|$)').hasMatch(low)) return 'Mandiri'; // "M" = Mandiri
  return '';
}

final _qrWords = RegExp(r'\b(qr|qris|tf|trf|transfer|tranfer)\b');
final _splitPay = RegExp(r'\s*(?:,|\+|&|\bdan\b)\s*', caseSensitive: false);

/// "200" | "200 (QR)" | "cash 200, qr 250" | "qr 250 bca" | "cash 100 + tf m 150"
Pay parsePembayaran(dynamic raw) {
  final str = s(raw).trim();
  var cash = 0, qr = 0;
  var bank = '';
  for (final seg in str.split(_splitPay)) {
    if (seg.isEmpty) continue;
    final nm = RegExp(r'\d+').firstMatch(seg);
    final amt = nm != null ? int.parse(nm[0]!) : 0;
    final low = seg.toLowerCase();
    final b = detectBank(low);
    if (_qrWords.hasMatch(low) || b.isNotEmpty) {
      qr += amt;
      if (b.isNotEmpty) bank = b;
    } else {
      cash += amt;
    }
  }
  final total = cash + qr;
  final metode = qr == 0 ? 'cash' : (cash == 0 ? 'qr' : 'split');
  return Pay(total, cash, qr, bank, metode);
}

void applyPay(Rec e, Pay pay) {
  e['biaya'] = pay.biaya;
  e['metode'] = pay.metode;
  e['qr'] = pay.metode == 'cash' ? 0 : pay.qr;
  e['bank'] = pay.metode == 'cash' ? '' : pay.bank;
}

({num cash, num qr}) entryAmounts(Rec e) {
  final b = n(e['biaya']);
  if (e['metode'] == 'split') {
    final q = n(e['qr']).clamp(0, b);
    return (cash: b - q, qr: q);
  }
  if (e['metode'] == 'qr') return (cash: 0, qr: b);
  return (cash: b, qr: 0);
}

String formatPembayaran(Rec e) {
  final a = entryAmounts(e);
  final bank = s(e['bank']).isNotEmpty ? ' ${e['bank']}' : '';
  if (e['metode'] == 'split') return 'cash ${a.cash.round()}, qr ${a.qr.round()}$bank';
  if (e['metode'] == 'qr') return 'qr ${a.qr.round()}$bank';
  return '';
}

class ParafMetode {
  String paraf, metode, bank;
  int qr;
  ParafMetode(this.paraf, this.metode, this.qr, this.bank);
}

/// Kolom Paraf di Excel: "S", "S (QR)", "S (QR BCA)", "S (QR 250 BCA)".
ParafMetode splitParafMetode(dynamic raw) {
  final str = s(raw).trim();
  if (str.isEmpty) return ParafMetode('', 'cash', 0, '');
  var qrAmt = 0;
  var bank = '';
  var isQr = RegExp('qr', caseSensitive: false).hasMatch(str);
  for (final g in RegExp(r'\([^)]*\)').allMatches(str)) {
    final inner = g[0]!.substring(1, g[0]!.length - 1);
    final low = inner.toLowerCase();
    if (_qrWords.hasMatch(low) || low.contains('qr') || detectBank(low).isNotEmpty) {
      isQr = true;
      final nm = RegExp(r'\d+').firstMatch(inner);
      if (nm != null) qrAmt = int.parse(nm[0]!);
      final b = detectBank(low.replaceAll(RegExp(r'qris|qr|transfer|tranfer|trf|tf'), ' '));
      if (b.isNotEmpty) bank = b;
    }
  }
  var paraf = str.replaceAll(RegExp(r'\([^)]*\)'), '').trim();
  if (paraf == '-' || paraf == '.') paraf = '';
  return ParafMetode(paraf, isQr ? 'qr' : 'cash', qrAmt, bank);
}

({String metode, int qr, String bank}) finalizePay(num biaya, ParafMetode pm) {
  if (pm.metode != 'qr') return (metode: 'cash', qr: 0, bank: '');
  final b = biaya.round();
  if (pm.qr > 0 && pm.qr < b) return (metode: 'split', qr: pm.qr, bank: pm.bank);
  return (metode: 'qr', qr: b, bank: pm.bank);
}

String combineParafMetode(Rec e) {
  final p = s(e['paraf']).isNotEmpty ? '${e['paraf']} ' : '';
  final bank = s(e['bank']).isNotEmpty ? ' ${e['bank']}' : '';
  if (e['metode'] == 'split') return '$p(QR ${entryAmounts(e).qr.round()}$bank)';
  if (e['metode'] == 'qr') return '$p(QR$bank)';
  return s(e['paraf']);
}

// ---------- Klasifikasi kunjungan: Tindakan vs Premedikasi ----------
final _pascaExo = RegExp(r'(pasca|post)\s*(exo|ekstraksi|cabut)');
final _tindRules = <(String, RegExp)>[
  ('Exo', RegExp(r'exo|ekstraksi|cabut')),
  ('Devit', RegExp(r'devit')),
  ('Kontrol', RegExp(r'kontrol|control')),
];
final _tindOther = RegExp(r'tambal|scaling|rct|saluran akar|\bts\b');
final _premRules = <(String, RegExp)>[
  ('Pasca Exo', _pascaExo),
  ('Medikasi', RegExp(r'medik')),
  ('Konsul', RegExp(r'konsul')),
  ('Abses', RegExp(r'abses|abcess')),
  ('Irigasi', RegExp(r'irigasi|irrigasi')),
  ('OB', RegExp(r'\bob\b|obat')),
];

List<String> _match(List<(String, RegExp)> rules, String text) =>
    rules.where((r) => r.$2.hasMatch(text)).map((r) => r.$1).toList();

({String group, List<String> cats}) classifyVisit(Rec e) {
  final raw = s(e['perawatan']).toLowerCase();
  final noPasca = raw.replaceAll(RegExp(_pascaExo.pattern), ' ');
  final tind = _match(_tindRules, noPasca);
  if (tind.isNotEmpty) return (group: 'tindakan', cats: tind);
  if (_tindOther.hasMatch(noPasca)) return (group: 'tindakan', cats: ['Lainnya']);
  final prem = _match(_premRules, raw);
  if (prem.isNotEmpty) return (group: 'premed', cats: prem);
  return (group: 'tindakan', cats: ['Lainnya']);
}

class MonthAgg {
  num cash = 0, qr = 0, total = 0;
  int visits = 0, newPatients = 0, tindakanTotal = 0, premedTotal = 0;
  Map<String, int> tindakan = {}, premed = {};
}

/// Ringkasan per bulan (kunci 'yyyymm').
Map<String, MonthAgg> buildMonthlyRekap(List<Rec> entries) {
  final months = <String, MonthAgg>{};
  final firstVisit = <String, String>{};
  for (final e in entries) {
    final rm = s(e['noFile']);
    if (rm.isEmpty) continue;
    final dk = dateKey(s(e['tanggal']));
    if (dk.isNotEmpty && (!firstVisit.containsKey(rm) || dk.compareTo(firstVisit[rm]!) < 0)) firstVisit[rm] = dk;
  }
  for (final e in entries) {
    final dk = dateKey(s(e['tanggal']));
    if (dk.isEmpty) continue;
    final m = months.putIfAbsent(dk.substring(0, 6), () => MonthAgg());
    m.total += n(e['biaya']);
    final am = entryAmounts(e);
    m.cash += am.cash;
    m.qr += am.qr;
    m.visits++;
    final c = classifyVisit(e);
    final bucket = c.group == 'premed' ? m.premed : m.tindakan;
    if (c.group == 'premed') {
      m.premedTotal++;
    } else {
      m.tindakanTotal++;
    }
    for (final k in c.cats) {
      bucket[k] = (bucket[k] ?? 0) + 1;
    }
  }
  firstVisit.forEach((rm, k) {
    final m = months[k.substring(0, 6)];
    if (m != null) m.newPatients++;
  });
  return months;
}

List<List<dynamic>> buildRekapAoa(List<Rec> entries) {
  final months = buildMonthlyRekap(entries);
  final aoa = <List<dynamic>>[
    ['Bulan / Tahun', 'Cash', 'QR', 'Total Pendapatan', 'Total Kunjungan', 'Pasien Baru', 'Tindakan', 'Premedikasi', 'Total (Tindakan + Premedikasi)']
  ];
  final sum = MonthAgg();
  final keys = months.keys.toList()..sort();
  for (final mk in keys) {
    final m = months[mk]!;
    aoa.add([
      '${bulanNama[int.parse(mk.substring(4)) - 1]} ${mk.substring(0, 4)}',
      m.cash, m.qr, m.total, m.visits, m.newPatients, m.tindakanTotal, m.premedTotal, m.tindakanTotal + m.premedTotal
    ]);
    sum.cash += m.cash;
    sum.qr += m.qr;
    sum.total += m.total;
    sum.visits += m.visits;
    sum.newPatients += m.newPatients;
    sum.tindakanTotal += m.tindakanTotal;
    sum.premedTotal += m.premedTotal;
  }
  aoa.add(['Total', sum.cash, sum.qr, sum.total, sum.visits, sum.newPatients, sum.tindakanTotal, sum.premedTotal, sum.tindakanTotal + sum.premedTotal]);
  return aoa;
}
