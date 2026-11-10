import 'package:flutter/material.dart';

import '../core/payments.dart';
import '../core/search.dart';
import '../core/store.dart';
import '../core/sync.dart';
import '../core/util.dart';
import 'common.dart';
import 'patient_dialogs.dart';

const _statusLabel = {'antri': 'Antri', 'proses': 'Diproses', 'selesai': 'Selesai'};

/// Menambahkan pasien lama ke antrian (tanpa dialog).
void addToQueue(AppStore st, Rec p) {
  if (st.inQueue(s(p['noFile']))) {
    toast('${p['nama']} sudah ada di antrian', 'warn');
    return;
  }
  final items = st.aqItems;
  items.add({
    'id': newId('q'), 'no': items.length + 1, 'rm': s(p['noFile']), 'nama': s(p['nama']), 'umur': s(p['umur']),
    'gender': s(p['gender']), 'alamat': s(p['alamat']), 'telp': s(p['telp']), 'isNew': false, 'status': 'antri',
    'tanggal': todayIso(), 'u': nowMs(),
  });
  st.setAqItems(items);
  toast('${p['nama']} masuk antrian #${items.length}');
}

/// Dialog antrian: cari pasien lama atau daftarkan pasien baru.
Future<void> showQueueDialog(BuildContext c, AppStore st) {
  final q = TextEditingController();
  return showSheet<void>(c, title: 'Tambah antrian', body: (ctx) => StatefulBuilder(builder: (ctx, set) {
    final res = q.text.trim().isEmpty ? <Rec>[] : searchPatients(st.pasien, q.text).take(8).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Field('Cari nama / No. RM / telepon', q, onChanged: (_) => set(() {})),
      for (final p in res)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: GenderDot(s(p['gender'])),
          title: Text(s(p['nama']), style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('RM ${p['noFile']} · ${s(p['umur'])} · ${s(p['alamat'])}', maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: st.inQueue(s(p['noFile'])) ? Text('di antrian', style: TextStyle(color: pal.warn, fontSize: 12)) : null,
          onTap: () {
            addToQueue(st, p);
            Navigator.pop(ctx);
          },
        ),
      gap(),
      Btn('➕ Pasien baru', () async {
        Navigator.pop(ctx);
        final p = await showPatientForm(c, st);
        if (p != null) addToQueue(st, p);
      }, accent: true),
    ]);
  }));
}

Future<void> editQueueItem(BuildContext c, AppStore st, Rec it) {
  final gigi = TextEditingController(text: s(it['gigi']));
  final dx = TextEditingController(text: s(it['diagnosa']));
  final rw = TextEditingController(text: s(it['perawatan']));
  final bayar = TextEditingController(text: s(it['bayar']));
  final paraf = TextEditingController(text: s(it['paraf']));
  var tgl = s(it['tanggal']).isEmpty ? todayIso() : s(it['tanggal']);
  return showSheet<void>(c, title: '${it['nama']} · RM ${it['rm']}', body: (ctx) => StatefulBuilder(builder: (ctx, set) {
    final pay = parsePembayaran(bayar.text);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      DateField('Tanggal', tgl, (v) => set(() => tgl = v.isEmpty ? todayIso() : v), allowClear: false),
      Field('Gigi', gigi, hint: 'mis. 36'),
      Field('Diagnosa', dx),
      Field('Perawatan', rw, lines: 2),
      Field('Pembayaran', bayar, hint: '200 · 200 qr · cash 100, qr 150 bca', onChanged: (_) => set(() {})),
      Hint('Terbaca: ${rp(pay.biaya)} (${pay.metode}${pay.bank.isEmpty ? '' : ' ${pay.bank}'})'),
      Field('Paraf', paraf),
      gap(),
      Btn('Simpan', () {
        it['gigi'] = gigi.text.trim();
        it['diagnosa'] = dx.text.trim();
        it['perawatan'] = rw.text.trim();
        it['bayar'] = bayar.text.trim();
        it['paraf'] = paraf.text.trim();
        it['tanggal'] = tgl;
        it['u'] = nowMs();
        st.aqSave();
        Navigator.pop(ctx);
      }, accent: true),
    ]);
  }));
}

class DataPasienPage extends StatelessWidget {
  final AppStore store;
  final SyncService sync;
  const DataPasienPage({super.key, required this.store, required this.sync});

  Future<void> _endShift(BuildContext c) async {
    final items = store.aqItems;
    final done = items.where((i) => i['status'] == 'selesai').toList();
    if (done.isEmpty) {
      toast('Belum ada pasien berstatus Selesai', 'warn');
      return;
    }
    if (!await confirmDialog(c, 'End Shift: masukkan ${done.length} pasien selesai ke Data Pasien & Entry, lalu keluarkan dari antrian?', ok: 'End Shift')) return;
    final jaga = store.jaga;
    final pts = <({Rec pasien, Map? odo, bool isNew})>[];
    final visits = <Rec>[];
    for (final i in done) {
      pts.add((
        pasien: {'noFile': s(i['rm']), 'nama': s(i['nama']), 'umur': s(i['umur']), 'gender': s(i['gender']), 'alamat': s(i['alamat']), 'telp': s(i['telp'])},
        odo: null,
        isNew: i['isNew'] == true,
      ));
      final pay = parsePembayaran(i['bayar']);
      final v = <String, dynamic>{
        'noFile': s(i['rm']), 'nama': s(i['nama']), 'umur': s(i['umur']), 'alamat': s(i['alamat']),
        'tanggal': isoToDmy(s(i['tanggal']).isEmpty ? todayIso() : s(i['tanggal'])),
        'gigi': s(i['gigi']), 'diagnosa': s(i['diagnosa']), 'perawatan': s(i['perawatan']), 'paraf': s(i['paraf']),
        if (jaga != null) 'dokter': s(jaga['nama']),
      };
      applyPay(v, pay);
      visits.add(v);
    }
    final r = store.applyShift(pts, visits);
    store.setAqItems(items.where((i) => i['status'] != 'selesai').toList());
    toast('Shift selesai: ${r.baru} pasien baru, ${r.diperbarui} diperbarui, ${r.kunjungan} kunjungan'
        '${r.dilewati > 0 ? ', ${r.dilewati} duplikat dilewati' : ''}');
  }

  @override
  Widget build(BuildContext context) {
    final items = store.aqItems..sort((a, b) => n(a['no']).compareTo(n(b['no'])));
    num total = 0;
    for (final i in items) {
      total += parsePembayaran(i['bayar']).biaya;
    }
    return ListView(children: [
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: H3('Antrian hari ini')),
            Btn('➕ Tambah', () => showQueueDialog(context, store), accent: true, small: true),
          ]),
          gap(),
          StatGrid([
            StatCard('Pasien', '${items.length}'),
            StatCard('Selesai', '${items.where((i) => i['status'] == 'selesai').length}', color: pal.good),
            StatCard('Pendapatan', rp(total), color: pal.accent),
          ]),
          gap(),
          Row(children: [
            Expanded(child: Btn('🏁 End Shift', () => _endShift(context), accent: true)),
          ]),
        ]),
      ),
      if (items.isEmpty) const Empty('Antrian kosong.'),
      for (final it in items)
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 28, height: 28, alignment: Alignment.center,
                  decoration: BoxDecoration(color: pal.accentDim, shape: BoxShape.circle),
                  child: Text('${it['no']}', style: TextStyle(color: pal.accent, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 10),
                GenderDot(s(it['gender'])),
                Expanded(child: Text(s(it['nama']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                if (it['isNew'] == true) Text('BARU', style: TextStyle(color: pal.warn, fontSize: 11, fontWeight: FontWeight.w800)),
              ]),
              Padding(
                padding: const EdgeInsets.only(left: 38, top: 2),
                child: Text('RM ${it['rm']} · ${s(it['umur'])}${s(it['perawatan']).isEmpty ? '' : ' · ${it['perawatan']}'}${s(it['bayar']).isEmpty ? '' : ' · ${rp(parsePembayaran(it['bayar']).biaya)}'}',
                    style: TextStyle(color: pal.dim, fontSize: 12.5)),
              ),
              gap(8),
              Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                for (final k in ['antri', 'proses', 'selesai'])
                  InkWell(
                    onTap: () {
                      it['status'] = k;
                      it['u'] = nowMs();
                      store.aqSave();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: it['status'] == k ? (k == 'selesai' ? pal.good : pal.accent) : pal.surface2,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(_statusLabel[k]!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: it['status'] == k ? pal.accentInk : pal.dim)),
                    ),
                  ),
                Btn('✏️ Isi', () => editQueueItem(context, store, it), small: true),
                Btn('Hapus', () async {
                  if (await confirmDialog(context, 'Keluarkan ${it['nama']} dari antrian?', ok: 'Keluarkan')) {
                    final l = store.aqItems..removeWhere((x) => x['id'] == it['id']);
                    store.tomb['antrian']![s(it['id'])] = nowMs();
                    var k = 1;
                    for (final x in l) {
                      x['no'] = k++;
                      x['u'] = nowMs();
                    }
                    store.setAqItems(l);
                  }
                }, small: true, color: pal.danger),
              ]),
            ]),
          ),
        ),
    ]);
  }
}
