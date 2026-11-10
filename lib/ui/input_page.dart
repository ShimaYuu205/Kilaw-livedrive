import 'package:flutter/material.dart';

import '../core/payments.dart';
import '../core/search.dart';
import '../core/store.dart';
import '../core/util.dart';
import 'common.dart';

class InputPage extends StatefulWidget {
  final AppStore store;
  const InputPage({super.key, required this.store});
  @override
  State<InputPage> createState() => _InputState();
}

class _InputState extends State<InputPage> {
  AppStore get st => widget.store;
  final cari = TextEditingController(), gigi = TextEditingController(), dx = TextEditingController();
  final rw = TextEditingController(), bayar = TextEditingController(), paraf = TextEditingController();
  final bulk = TextEditingController();
  Rec? picked;
  String tgl = todayIso();

  List<Rec> get _sug => picked != null || cari.text.trim().isEmpty ? [] : searchPatients(st.pasien, cari.text).take(6).toList();

  void _save() {
    final p = picked;
    if (p == null) {
      toast('Pilih pasien dulu', 'warn');
      return;
    }
    final e = <String, dynamic>{
      'noFile': s(p['noFile']), 'nama': s(p['nama']), 'umur': s(p['umur']), 'alamat': s(p['alamat']),
      'tanggal': isoToDmy(tgl), 'gigi': gigi.text.trim(), 'diagnosa': dx.text.trim(), 'perawatan': rw.text.trim(),
      'paraf': paraf.text.trim() .isEmpty ? (st.jaga != null ? s(st.jaga!['paraf']) : '') : paraf.text.trim(),
      if (st.jaga != null) 'dokter': s(st.jaga!['nama']),
    };
    applyPay(e, parsePembayaran(bayar.text));
    st.insertEntryByDate(e, notify: true);
    toast('Entry ${p['nama']} tersimpan${e['susulan'] == true ? ' (susulan)' : ''}');
    setState(() {
      picked = null;
      for (final c in [cari, gigi, dx, rw, bayar, paraf]) {
        c.clear();
      }
    });
  }

  /// Baris: RM | tanggal(dd/mm/yy) | gigi | diagnosa | perawatan | pembayaran | paraf  (pemisah | atau Tab)
  void _bulk() {
    var ok = 0, bad = 0;
    for (final line in bulk.text.split('\n')) {
      if (line.trim().isEmpty) continue;
      final c = line.contains('\t') ? line.split('\t') : line.split('|');
      String g(int i) => i < c.length ? c[i].trim() : '';
      final p = st.findPasien(normNoFile(g(0)));
      if (p == null) {
        bad++;
        continue;
      }
      final e = <String, dynamic>{
        'noFile': s(p['noFile']), 'nama': s(p['nama']), 'umur': s(p['umur']), 'alamat': s(p['alamat']),
        'tanggal': g(1).isEmpty ? isoToDmy(todayIso()) : g(1), 'gigi': g(2), 'diagnosa': g(3), 'perawatan': g(4), 'paraf': g(6),
      };
      applyPay(e, parsePembayaran(g(5)));
      st.insertEntryByDate(e);
      ok++;
    }
    st.notifyExternal();
    toast('$ok entry masuk${bad > 0 ? ', $bad baris dilewati (RM tidak ditemukan)' : ''}', bad > 0 ? 'warn' : 'ok');
    if (bad == 0) bulk.clear();
  }

  @override
  Widget build(BuildContext context) {
    final pay = parsePembayaran(bayar.text);
    return ListView(children: [
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const H3('Entry kunjungan'),
          gap(),
          if (picked == null) ...[
            Field('Pasien', cari, hint: 'Nama / No. RM', onChanged: (_) => setState(() {})),
            SuggestList([for (final p in _sug) (s(p['nama']), 'RM ${p['noFile']} · ${s(p['umur'])}')], (i) => setState(() => picked = _sug[i])),
          ] else
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s(picked!['nama']), style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('RM ${picked!['noFile']} · ${s(picked!['umur'])}'),
              trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => picked = null)),
            ),
          DateField('Tanggal', tgl, (v) => setState(() => tgl = v.isEmpty ? todayIso() : v), allowClear: false),
          Field('Gigi', gigi),
          Field('Diagnosa', dx),
          Field('Perawatan', rw, lines: 2),
          Field('Pembayaran', bayar, hint: '200 · 200 qr · cash 100, qr 150 bca', onChanged: (_) => setState(() {})),
          Hint('Terbaca: ${rp(pay.biaya)} (${pay.metode}${pay.bank.isEmpty ? '' : ' ${pay.bank}'})'),
          Field('Paraf', paraf),
          gap(),
          Btn('Simpan entry', _save, accent: true),
        ]),
      ),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const H3('Input massal'),
          const Hint('Satu kunjungan per baris: RM | dd/mm/yy | gigi | diagnosa | perawatan | pembayaran | paraf. Boleh tempel dari Excel (kolom dipisah Tab).'),
          Field('', bulk, lines: 6, hint: '1024 | 10/11/26 | 36 | Pulpitis | Devit | 250 | S'),
          Btn('Masukkan semua', _bulk, accent: true),
        ]),
      ),
    ]);
  }
}
