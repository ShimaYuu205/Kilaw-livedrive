import 'package:flutter/material.dart';

import '../core/payments.dart';
import '../core/store.dart';
import '../core/util.dart';
import 'common.dart';

class RekapPage extends StatelessWidget {
  final AppStore store;
  const RekapPage({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    final months = buildMonthlyRekap(store.entry);
    final keys = months.keys.toList()..sort((a, b) => b.compareTo(a));
    MonthAgg sum = MonthAgg();
    for (final m in months.values) {
      sum.total += m.total; sum.cash += m.cash; sum.qr += m.qr; sum.visits += m.visits; sum.newPatients += m.newPatients;
    }
    return ListView(children: [
      Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const H3('Ringkasan keseluruhan'),
        gap(),
        StatGrid([
          StatCard('Total pendapatan', rp(sum.total), color: pal.accent),
          StatCard('Cash', rp(sum.cash)),
          StatCard('QR', rp(sum.qr)),
          StatCard('Kunjungan', '${sum.visits}'),
          StatCard('Pasien baru', '${sum.newPatients}'),
          StatCard('Pasien terdaftar', '${store.pasien.length}'),
        ]),
      ])),
      if (keys.isEmpty) const Empty('Belum ada entry.'),
      for (final k in keys)
        Panel(
          margin: const EdgeInsets.only(bottom: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('${bulanNama[int.parse(k.substring(4)) - 1]} ${k.substring(0, 4)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
              Text(rp(months[k]!.total), style: TextStyle(color: pal.accent, fontWeight: FontWeight.w800)),
            ]),
            gap(6),
            Wrap(spacing: 14, runSpacing: 4, children: [
              Text('Cash ${rp(months[k]!.cash)}', style: TextStyle(color: pal.dim, fontSize: 12.5)),
              Text('QR ${rp(months[k]!.qr)}', style: TextStyle(color: pal.dim, fontSize: 12.5)),
              Text('${months[k]!.visits} kunjungan', style: TextStyle(color: pal.dim, fontSize: 12.5)),
              Text('${months[k]!.newPatients} pasien baru', style: TextStyle(color: pal.dim, fontSize: 12.5)),
            ]),
            gap(6),
            Text('Tindakan ${months[k]!.tindakanTotal}: ${months[k]!.tindakan.entries.map((e) => '${e.key} ${e.value}').join(' · ')}', style: const TextStyle(fontSize: 12.5)),
            Text('Premedikasi ${months[k]!.premedTotal}: ${months[k]!.premed.entries.map((e) => '${e.key} ${e.value}').join(' · ')}', style: const TextStyle(fontSize: 12.5)),
          ]),
        ),
    ]);
  }
}
