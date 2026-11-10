import 'package:flutter/material.dart';

import '../app.dart';
import '../core/search.dart';
import '../core/stock.dart';
import '../core/store.dart';
import '../core/sync.dart';
import '../core/util.dart';
import 'antrian.dart';
import 'common.dart';
import 'docs_ui.dart';
import 'odo_page.dart';
import 'patient_dialogs.dart';

class BerandaPage extends StatefulWidget {
  final AppStore store;
  final SyncService sync;
  const BerandaPage({super.key, required this.store, required this.sync});
  @override
  State<BerandaPage> createState() => _BerandaState();
}

class _BerandaState extends State<BerandaPage> {
  final q = TextEditingController();
  AppStore get st => widget.store;

  Widget _row(Rec p) => ListTile(
        dense: true,
        leading: GenderDot(s(p['gender'])),
        title: Text(s(p['nama']), style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('RM ${p['noFile']} · ${s(p['umur'])} · ${s(p['alamat'])}', maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Text(s(p['telp']).isEmpty ? '' : ph(p['telp']), style: TextStyle(color: pal.faint, fontSize: 12)),
        onTap: () => showPatientDetail(context, st, p,
            onQueue: (x) => addToQueue(st, x),
            onOdo: (x) => openOdontogram(context, st, pasien: x),
            onDoc: (x) => showPatientDocs(context, st, x)),
      );

  Widget _group(String title, List<Rec> l, Color c) => l.isEmpty
      ? const SizedBox.shrink()
      : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.fromLTRB(4, 10, 4, 2), child: Text('$title (${l.length})', style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 12.5))),
          for (final p in l.take(40)) _row(p),
        ]);

  List<Widget> _pengingat() {
    final out = <Widget>[];
    Widget card(String t, String sub, String tab, Color c) => InkWell(
          onTap: () => goTab(tab),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(10), border: Border(left: BorderSide(color: c, width: 4), top: BorderSide(color: pal.border), right: BorderSide(color: pal.border), bottom: BorderSide(color: pal.border))),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t, style: const TextStyle(fontWeight: FontWeight.w800)), Text(sub, style: TextStyle(color: pal.dim, fontSize: 12.5))])),
              Icon(Icons.chevron_right, color: pal.faint),
            ]),
          ),
        );
    final wait = st.data['prospek']!.where(prWait).length;
    if (wait > 0) out.add(card('$wait prospek menunggu', 'Buka Prospek WA untuk tindak lanjut', 'prospek', pal.accent));
    final stuck = st.data['gigi']!.where(gStuck).length;
    if (stuck > 0) out.add(card('$stuck gigi tiruan tertahan', 'Tidak ada kemajuan > $gtStuckDays hari', 'gigitiruan', pal.warn));
    final rows = stokRows(st.data['stok']!, st.data['mutasi']!);
    final hab = rows.where((r) => r.st.tone == 2).length, kr = rows.where((r) => r.st.tone == 1).length;
    if (hab + kr > 0) out.add(card('Stok perlu perhatian', '$hab habis/minus · $kr kritis', 'stokobat', hab > 0 ? pal.danger : pal.warn));
    final ex = expList(st.data['stok']!, st.data['mutasi']!);
    if (ex.isNotEmpty) out.add(card('${ex.length} batch hampir/sudah expired', ex.first.nama, 'stokobat', pal.danger));
    final inc = st.pasienBelumLengkap.length;
    if (inc > 0) out.add(card('$inc pasien belum lengkap', 'Lengkapi di Storage → Pasien', 'storage', pal.warn));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final g = q.text.trim().isEmpty ? null : searchPatientsGrouped(st.pasien, q.text);
    final jaga = st.jaga;
    return ListView(children: [
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: H3('Cari pasien')),
            Text('${st.pasien.length} pasien', style: TextStyle(color: pal.dim, fontSize: 12)),
          ]),
          gap(),
          TextField(
            controller: q,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Nama, No. RM, telepon, alamat, umur…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: q.text.isEmpty ? null : IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(q.clear)),
            ),
          ),
          if (g != null) ...[
            if (g.isEmpty) const Empty('Tidak ada yang cocok.'),
            _group('Sama persis', g.exact, pal.good),
            _group('Mirip / mendekati', g.similar, pal.warn),
            _group('Lainnya', g.other, pal.dim),
          ],
          gap(10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            Btn('➕ Antrian', () => showQueueDialog(context, st), accent: true, small: true),
            Btn('🧑 Pasien baru', () => showPatientForm(context, st), small: true),
            Btn('🦷 Odontogram', () => openOdontogram(context, st), small: true),
            Btn('👨‍⚕️ Dokter jaga${jaga == null ? '' : ': ${jaga['nama']}'}', () => showDokterDialog(context, st), small: true),
          ]),
        ]),
      ),
      ..._pengingat(),
    ]);
  }
}
