import 'package:flutter/material.dart';

import '../core/excel_io.dart';
import '../core/payments.dart';
import '../core/search.dart';
import '../core/store.dart';
import '../core/util.dart';
import 'common.dart';
import 'docs_ui.dart';
import 'odo_page.dart';
import 'patient_dialogs.dart';

class StoragePage extends StatefulWidget {
  final AppStore store;
  const StoragePage({super.key, required this.store});
  @override
  State<StoragePage> createState() => _StorageState();
}

class _StorageState extends State<StoragePage> {
  AppStore get st => widget.store;
  String tab = 'pasien', periode = 'semua';
  final q = TextEditingController();
  int page = 1;
  static const per = 100;

  Future<void> _editEntry(Rec e) {
    final gigi = TextEditingController(text: s(e['gigi'])), dx = TextEditingController(text: s(e['diagnosa']));
    final rw = TextEditingController(text: s(e['perawatan'])), paraf = TextEditingController(text: s(e['paraf']));
    final bayar = TextEditingController(text: e['metode'] == 'cash' || e['metode'] == null ? '${n(e['biaya']).round()}' : '${formatPembayaran(e)}');
    var tgl = dmyToIso(s(e['tanggal']));
    return showSheet<void>(context, title: '${e['nama']} · ${e['tanggal']}', body: (ctx) => StatefulBuilder(builder: (ctx, set) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        DateField('Tanggal', tgl, (v) => set(() => tgl = v), allowClear: false),
        Field('Gigi', gigi), Field('Diagnosa', dx), Field('Perawatan', rw, lines: 2),
        Field('Pembayaran', bayar), Field('Paraf', paraf),
        gap(),
        Row(children: [
          Expanded(child: Btn('Simpan', () {
            e['tanggal'] = tgl.isEmpty ? s(e['tanggal']) : isoToDmy(tgl);
            e['gigi'] = gigi.text.trim(); e['diagnosa'] = dx.text.trim(); e['perawatan'] = rw.text.trim(); e['paraf'] = paraf.text.trim();
            applyPay(e, parsePembayaran(bayar.text));
            st.saveEntry(e);
            Navigator.pop(ctx);
          }, accent: true)),
          const SizedBox(width: 8),
          Btn('Hapus', () async {
            if (await confirmDialog(ctx, 'Hapus entry ini?', ok: 'Hapus')) {
              st.entry.remove(e);
              st.tomb['entry']![s(e['id'])] = nowMs();
              st.changed('entry');
              if (ctx.mounted) Navigator.pop(ctx);
            }
          }, color: pal.danger),
        ]),
      ]);
    }));
  }

  List<Rec> _entries() {
    var l = st.entry.toList();
    if (periode != 'semua') {
      final days = periode == '7' ? 7 : periode == '30' ? 30 : 0;
      final from = days > 0 ? dateKey(isoToDmy(isoDaysAgo(days))) : '${DateTime.now().year}${pad2(DateTime.now().month)}01';
      l = l.where((e) => dateKey(s(e['tanggal'])).compareTo(from) >= 0).toList();
    }
    final t = norm(q.text);
    if (t.isNotEmpty) {
      l = l.where((e) => norm('${e['nama']} ${e['noFile']} ${e['diagnosa']} ${e['perawatan']} ${e['gigi']}').contains(t)).toList();
    }
    l.sort((a, b) => dateKey(s(b['tanggal'])).compareTo(dateKey(s(a['tanggal']))));
    return l;
  }

  @override
  Widget build(BuildContext context) {
    final isP = tab == 'pasien';
    final list = isP
        ? (q.text.trim().isEmpty ? (st.pasien.toList()..sort(rmCompare)) : searchPatients(st.pasien, q.text))
        : _entries();
    final pages = (list.length / per).ceil().clamp(1, 9999);
    if (page > pages) page = pages;
    final slice = list.skip((page - 1) * per).take(per).toList();
    return ListView(children: [
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Pills(const [('pasien', 'Pasien'), ('entry', 'Entry')], tab, (v) => setState(() { tab = v; page = 1; })),
            const Spacer(),
            Text('${list.length}', style: TextStyle(color: pal.dim)),
          ]),
          gap(),
          TextField(controller: q, onChanged: (_) => setState(() => page = 1), decoration: const InputDecoration(hintText: 'Cari…', prefixIcon: Icon(Icons.search))),
          if (!isP) ...[
            gap(8),
            Pills(const [('semua', 'Semua'), ('7', '7 hari'), ('30', '30 hari'), ('bulan', 'Bulan ini')], periode, (v) => setState(() { periode = v; page = 1; })),
          ],
          gap(8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            Btn('⬇️ Impor Excel', () => importExcelFlow(context, st), small: true),
            Btn('⬆️ Ekspor Excel', () => exportExcelFlow(context, st), small: true),
          ]),
        ]),
      ),
      if (slice.isEmpty) const Empty('Tidak ada data.'),
      for (final r in slice)
        if (isP)
          Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              dense: true,
              leading: GenderDot(s(r['gender'])),
              title: Text(s(r['nama']), style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('RM ${r['noFile']} · ${s(r['umur'])} · ${s(r['alamat'])}', maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: r['isIncomplete'] == true ? Icon(Icons.warning_amber, color: pal.warn, size: 18) : null,
              onTap: () => showPatientDetail(context, st, r, onOdo: (x) => openOdontogram(context, st, pasien: x), onDoc: (x) => showPatientDocs(context, st, x)),
            ),
          )
        else
          Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              dense: true,
              title: Text('${r['tanggal']} · ${s(r['nama'])}', style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${s(r['gigi'])} ${s(r['diagnosa'])} — ${s(r['perawatan'])}', maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: Text(rp(n(r['biaya'])), style: TextStyle(color: pal.accent, fontWeight: FontWeight.w800)),
              onTap: () => _editEntry(r),
            ),
          ),
      if (pages > 1)
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(onPressed: page > 1 ? () => setState(() => page--) : null, icon: const Icon(Icons.chevron_left)),
          Text('$page / $pages'),
          IconButton(onPressed: page < pages ? () => setState(() => page++) : null, icon: const Icon(Icons.chevron_right)),
        ]),
    ]);
  }
}
