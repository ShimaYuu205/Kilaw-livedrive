import 'util.dart';

class StokMv {
  num masuk = 0, keluar = 0;
}

StokMv computeStok(List<Rec> mutasi, String nama) {
  final key = normNama(nama);
  final r = StokMv();
  for (final m in mutasi) {
    if (normNama(m['nama']) != key) continue;
    final q = n(m['jumlah']);
    final j = s(m['jenis']).toUpperCase();
    if (j == 'MASUK') {
      r.masuk += q;
    } else if (j == 'KELUAR') {
      r.keluar += q;
    }
  }
  return r;
}

class StokStatus {
  final String label, key;
  final int tone; // 0 aman, 1 kritis, 2 habis
  const StokStatus(this.label, this.key, this.tone);
}

StokStatus stokStatus(num akhir) {
  if (akhir < 0) return const StokStatus('🚨 MINUS', 'habis', 2);
  if (akhir == 0) return const StokStatus('🚨 HABIS', 'habis', 2);
  if (akhir <= 2) return const StokStatus('⚠️ KRITIS', 'kritis', 1);
  return const StokStatus('✅ AMAN', 'aman', 0);
}

class Sisa {
  final Rec? item;
  final num awal, masuk, keluar, akhir;
  Sisa(this.item, this.awal, this.masuk, this.keluar, this.akhir);
}

Sisa hitungSisa(List<Rec> stok, String nama, List<Rec> list, {num? awalOverride}) {
  final key = normNama(nama);
  final item = firstWhereOrNull(stok, (x) => normNama(x['nama']) == key);
  final awal = awalOverride ?? (item != null ? n(item['stokAwal']) : 0);
  num masuk = 0, keluar = 0;
  for (final m in list) {
    if (normNama(m['nama']) != key) continue;
    final q = n(m['jumlah']);
    final j = s(m['jenis']).toUpperCase();
    if (j == 'MASUK') {
      masuk += q;
    } else if (j == 'KELUAR') {
      keluar += q;
    }
  }
  return Sisa(item, awal, masuk, keluar, round3(awal + masuk - keluar));
}

class StokMinus {
  final String nama, satuan;
  final num akhir;
  StokMinus(this.nama, this.akhir, this.satuan);
}

StokMinus? cariStokMinus(List<Rec> stok, List<Rec> list, List<String> namaList) {
  final seen = <String>{};
  for (final nm in namaList) {
    final k = normNama(nm);
    if (k.isEmpty || !seen.add(k)) continue;
    final r = hitungSisa(stok, nm, list);
    if (r.akhir < 0) return StokMinus(nm, r.akhir, r.item != null ? s(r.item!['satuan']) : '');
  }
  return null;
}

String joinedExpired(List<Rec> mutasi, String nama) {
  final k = normNama(nama);
  final l = <String>[];
  for (final m in mutasi) {
    if (normNama(m['nama']) == k && s(m['jenis']).toUpperCase() == 'MASUK' && s(m['expired']).isNotEmpty) l.add(s(m['expired']));
  }
  return l.isEmpty ? '-' : l.join(', ');
}

/// Urut kronologis: tanggal, lalu waktu input, lalu id (stabil).
int cmpMutasiAsc(Rec a, Rec b) {
  final t = s(a['tanggal']).compareTo(s(b['tanggal']));
  if (t != 0) return t;
  final w = n(a['addedAt']).compareTo(n(b['addedAt']));
  if (w != 0) return w;
  return s(a['id']).compareTo(s(b['id']));
}

DateTime? parseExp(dynamic t) {
  final str = s(t).trim();
  var m = RegExp(r'^(\d{1,2})\s*[/.\-]\s*(\d{1,2})\s*[/.\-]\s*(\d{2,4})$').firstMatch(str);
  if (m != null) {
    final y = int.parse(m[3]!);
    return DateTime(y < 100 ? 2000 + y : y, int.parse(m[2]!), int.parse(m[1]!));
  }
  m = RegExp(r'^(\d{1,2})\s*[/.\-]\s*(\d{2,4})$').firstMatch(str);
  if (m != null) {
    final y = int.parse(m[2]!);
    return DateTime(y < 100 ? 2000 + y : y, int.parse(m[1]!) + 1, 0); // hari terakhir bulan
  }
  m = RegExp(r'^(\d{4})-(\d{2})(?:-(\d{2}))?$').firstMatch(str);
  if (m != null) {
    return m[3] != null
        ? DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!))
        : DateTime(int.parse(m[1]!), int.parse(m[2]!) + 1, 0);
  }
  return null;
}

class ExpInfo {
  final String nama, t, satuan;
  final int days;
  final num q;
  ExpInfo(this.nama, this.t, this.days, this.q, this.satuan);
}

/// Stok awal dianggap terpakai lebih dulu, lalu batch Masuk yang paling cepat expired (FIFO).
List<ExpInfo> expList(List<Rec> stok, List<Rec> mutasi) {
  final out = <ExpInfo>[];
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  for (final o in stok) {
    final k = normNama(o['nama']);
    num keluar = 0;
    final bt = <({DateTime d, String t, num q})>[];
    final qs = <num>[];
    for (final x in mutasi) {
      if (normNama(x['nama']) != k) continue;
      final q = n(x['jumlah']);
      final j = s(x['jenis']).toUpperCase();
      if (j == 'KELUAR') {
        keluar += q;
      } else if (j == 'MASUK') {
        final d = parseExp(x['expired']);
        if (d != null) {
          bt.add((d: d, t: s(x['expired']), q: q));
          qs.add(q);
        }
      }
    }
    var rest = keluar - n(o['stokAwal']);
    final idx = List<int>.generate(bt.length, (i) => i)..sort((a, b) => bt[a].d.compareTo(bt[b].d));
    for (final i in idx) {
      if (rest > 0) {
        final u = rest < qs[i] ? rest : qs[i];
        qs[i] -= u;
        rest -= u;
      }
    }
    for (final i in idx) {
      if (qs[i] > 0) {
        final days = bt[i].d.difference(today).inDays;
        if (days <= 60) out.add(ExpInfo(s(o['nama']), bt[i].t, days, round3(qs[i]), s(o['satuan'])));
      }
    }
  }
  out.sort((a, b) => a.days.compareTo(b.days));
  return out;
}

class StokRow {
  final Rec item;
  final StokMv mv;
  final num akhir;
  final StokStatus st;
  StokRow(this.item, this.mv, this.akhir, this.st);
}

List<StokRow> stokRows(List<Rec> stok, List<Rec> mutasi) {
  // indeks sekali jalan: O(stok + mutasi)
  final mv = <String, StokMv>{};
  for (final m in mutasi) {
    final r = mv.putIfAbsent(normNama(m['nama']), () => StokMv());
    final q = n(m['jumlah']);
    final j = s(m['jenis']).toUpperCase();
    if (j == 'MASUK') {
      r.masuk += q;
    } else if (j == 'KELUAR') {
      r.keluar += q;
    }
  }
  return stok.map((it) {
    final m = mv[normNama(it['nama'])] ?? StokMv();
    final akhir = n(it['stokAwal']) + m.masuk - m.keluar;
    return StokRow(it, m, akhir, stokStatus(akhir));
  }).toList();
}

// ---------- Gigi tiruan & prospek ----------
const gtStuckDays = 7;
bool gDone(Rec g) => g['transferLab'] == 'Sudah' && g['kirimLab'] == 'Sudah' && g['datang'] == 'Sudah' && g['insersi'] == 'Sudah';
bool gStuck(Rec g) => !gDone(g) && n(g['updatedAt']) > 0 && (nowMs() - n(g['updatedAt'])) / 864e5 > gtStuckDays;
String gStage(Rec g) => g['insersi'] == 'Sudah'
    ? 'Insersi'
    : g['datang'] == 'Sudah'
        ? 'Sudah datang'
        : g['kirimLab'] == 'Sudah'
            ? 'Sudah dikirim ke lab'
            : g['transferLab'] == 'Sudah'
                ? 'Sudah dibayar ke lab'
                : 'Belum dimulai';
bool prWait(Rec p) => p['status'] != 'Selesai' && p['status'] != 'Batal';
