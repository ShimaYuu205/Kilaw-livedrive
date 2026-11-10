import 'package:flutter/material.dart';

import '../core/docs.dart';
import '../core/excel_io.dart';
import '../core/payments.dart';
import '../core/store.dart';
import '../core/sync.dart';
import '../core/util.dart';
import 'common.dart';
import 'docs_ui.dart';

class LaporanPage extends StatefulWidget {
  final AppStore store;
  final SyncService sync;
  const LaporanPage({super.key, required this.store, required this.sync});
  @override
  State<LaporanPage> createState() => _LaporanState();
}

class _LaporanState extends State<LaporanPage> {
  AppStore get st => widget.store;
  String? ym;

  List<String> get _months {
    final k = st.entry.map((e) => ymOfDmy(s(e['tanggal']))).where((x) => x.isNotEmpty).toSet().toList()..sort((a, b) => b.compareTo(a));
    if (k.isEmpty) k.add(todayIso().substring(0, 7));
    return k;
  }

  @override
  Widget build(BuildContext context) {
    final months = _months;
    ym ??= months.first;
    if (!months.contains(ym)) ym = months.first;
    final agg = buildMonthlyRekap(st.entry)[ym!.replaceAll('-', '')];
    final consents = st.data['consent']!.toList()..sort((a, b) => n(b['updatedAt']).compareTo(n(a['updatedAt'])));
    return ListView(children: [
      Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const H3('Laporan bulanan'),
        gap(),
        Pills([for (final m in months.take(12)) (m, '${bulanNama[int.parse(m.substring(5)) - 1].substring(0, 3)} ${m.substring(0, 4)}')], ym!, (v) => setState(() => ym = v)),
        gap(),
        if (agg != null)
          StatGrid([
            StatCard('Pendapatan', rp(agg.total), color: pal.accent),
            StatCard('Kunjungan', '${agg.visits}'),
            StatCard('Pasien baru', '${agg.newPatients}'),
          ]),
        gap(),
        Wrap(spacing: 8, runSpacing: 8, children: [
          Btn('📄 Laporan bulanan (PDF)', () async => previewPdf(context, st, 'Laporan-Bulanan-$ym.pdf', await laporanBulananPdf(st, ym!), folder: 'laporan'), accent: true, small: true),
          Btn('📄 Status & stok (PDF)', () async => previewPdf(context, st, 'Laporan-Status-Clinic-${todayIso()}.pdf', await statusPdf(st), folder: 'laporan'), small: true),
          Btn('📊 Ekspor Excel', () => exportExcelFlow(context, st), small: true),
        ]),
      ])),
      Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        H3('Inform consent', count: consents.length),
        gap(6),
        if (consents.isEmpty) const Hint('Belum ada. Buat dari detail pasien → Dokumen.'),
        for (final r in consents.take(30))
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(s(r['nama']), style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('RM ${r['rm']} · ${s(r['tgl'])} · ${s(r['tindakan'])}', maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: IconButton(icon: Icon(Icons.delete_outline, color: pal.danger, size: 18), onPressed: () async {
              if (await confirmDialog(context, 'Hapus consent ${r['nama']}?', ok: 'Hapus')) st.removeKey('consent', s(r['id']));
            }),
            onTap: () async => previewPdf(context, st, 'Inform-Consent-${fname([r['rm'], r['nama']])}.pdf', await consentPdf(st, r)),
          ),
      ])),
    ]);
  }
}
