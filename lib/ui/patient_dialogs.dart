import 'package:flutter/material.dart';

import '../core/payments.dart';
import '../core/store.dart';
import '../core/util.dart';
import 'common.dart';

/// Formulir pasien (baru / ubah). Mengembalikan record tersimpan atau null.
Future<Rec?> showPatientForm(BuildContext c, AppStore st, {Rec? edit, String? rm}) {
  final nama = TextEditingController(text: s(edit?['nama']));
  final umur = TextEditingController(text: s(edit?['umur']));
  final alamat = TextEditingController(text: s(edit?['alamat']));
  final telp = TextEditingController(text: ph(edit?['telp']));
  final noFile = TextEditingController(text: edit != null ? s(edit['noFile']) : (rm ?? '${st.nextRm()}'));
  var gender = s(edit?['gender']);
  return showSheet<Rec>(
    c,
    title: edit == null ? 'Pasien baru' : 'Ubah data pasien',
    body: (ctx) => StatefulBuilder(builder: (ctx, set) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Field('No. RM', noFile, readOnly: edit != null, type: TextInputType.number),
        Field('Nama', nama),
        Row(children: [
          Expanded(child: Field('Umur', umur, hint: 'mis. 35 th')),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('Jenis kelamin', style: TextStyle(color: pal.dim, fontSize: 12, fontWeight: FontWeight.w700))),
              Pills(const [('l', 'Laki-laki'), ('p', 'Perempuan')], gender, (v) => set(() => gender = v)),
            ]),
          ),
        ]),
        gap(),
        Field('Alamat', alamat, lines: 2),
        Field('No. telepon', telp, type: TextInputType.phone),
        gap(),
        Row(children: [
          Expanded(
            child: Btn('Simpan', () {
              final rmv = normNoFile(noFile.text);
              if (rmv.isEmpty || nama.text.trim().isEmpty) {
                toast('No. RM dan nama wajib diisi', 'warn');
                return;
              }
              if (edit == null && st.findPasien(rmv) != null) {
                toast('No. RM $rmv sudah dipakai', 'err');
                return;
              }
              final r = edit ?? <String, dynamic>{'noFile': rmv, 'addedAt': nowMs()};
              r['nama'] = nama.text.trim();
              r['umur'] = normUmur(umur.text);
              r['gender'] = gender;
              r['alamat'] = alamat.text.trim();
              r['telp'] = telp.text.trim();
              r['isIncomplete'] = r['nama'].toString().isEmpty || gender.isEmpty;
              st.upsert('pasien', r);
              if (edit != null && st.syncEntryFromPasien(r)) toast('Riwayat entry ikut diperbarui');
              Navigator.pop(ctx, r);
            }, accent: true),
          ),
        ]),
      ]);
    }),
  );
}

/// Detail pasien + riwayat kunjungan.
Future<void> showPatientDetail(BuildContext c, AppStore st, Rec p, {void Function(Rec)? onQueue, void Function(Rec)? onOdo, void Function(Rec)? onDoc}) {
  return showSheet<void>(
    c,
    title: '${p['nama']}',
    maxWidth: 640,
    body: (ctx) {
      final rm = s(p['noFile']);
      final hist = st.entry.where((e) => s(e['noFile']) == rm).toList().reversed.toList();
      num total = 0;
      for (final e in hist) {
        total += n(e['biaya']);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 14, runSpacing: 4, children: [
          Text('RM $rm', style: TextStyle(color: pal.accent, fontWeight: FontWeight.w800)),
          Text(s(p['umur'])),
          Text(p['gender'] == 'p' ? 'Perempuan' : p['gender'] == 'l' ? 'Laki-laki' : '-'),
          if (ph(p['telp']).isNotEmpty) Text(ph(p['telp'])),
        ]),
        if (s(p['alamat']).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(s(p['alamat']), style: TextStyle(color: pal.dim))),
        gap(),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (onQueue != null) Btn('➕ Antrian', () { Navigator.pop(ctx); onQueue(p); }, accent: true, small: true),
          Btn('✏️ Ubah', () async { Navigator.pop(ctx); await showPatientForm(c, st, edit: p); }, small: true),
          if (onOdo != null) Btn('🦷 Odontogram', () { Navigator.pop(ctx); onOdo(p); }, small: true),
          if (onDoc != null) Btn('📄 Dokumen', () { Navigator.pop(ctx); onDoc(p); }, small: true),
          Btn('🗑 Hapus', () async {
            if (await confirmDialog(ctx, 'Hapus pasien ${p['nama']} (RM $rm)? Riwayat entry tidak ikut terhapus.', ok: 'Hapus')) {
              st.removeKey('pasien', rm);
              if (ctx.mounted) Navigator.pop(ctx);
              toast('Pasien dihapus');
            }
          }, small: true, color: pal.danger),
        ]),
        gap(14),
        Text('Riwayat kunjungan (${hist.length}) · total ${rp(total)}', style: const TextStyle(fontWeight: FontWeight.w800)),
        gap(6),
        if (hist.isEmpty) const Empty('Belum ada kunjungan.'),
        for (final e in hist.take(60))
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: pal.surface2, borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(s(e['tanggal']), style: const TextStyle(fontWeight: FontWeight.w800)),
                const Spacer(),
                Text(rp(n(e['biaya'])), style: TextStyle(color: pal.accent, fontWeight: FontWeight.w800)),
              ]),
              if (s(e['gigi']).isNotEmpty || s(e['diagnosa']).isNotEmpty) Text('${s(e['gigi'])} ${s(e['diagnosa'])}'.trim(), style: TextStyle(color: pal.dim, fontSize: 13)),
              if (s(e['perawatan']).isNotEmpty) Text(s(e['perawatan']), style: const TextStyle(fontSize: 13)),
              if (formatPembayaran(e).isNotEmpty) Text(formatPembayaran(e), style: TextStyle(color: pal.faint, fontSize: 12)),
            ]),
          ),
      ]);
    },
  );
}
