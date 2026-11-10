import 'package:flutter/material.dart';

import '../core/stock.dart';
import '../core/store.dart';
import '../core/util.dart';
import 'common.dart';

/// Spesifikasi kolom formulir generik: kunci, label, jenis (text|num|date|pick:a,b,c|area).
class FS {
  final String key, label, kind;
  const FS(this.key, this.label, [this.kind = 'text']);
}

Future<bool> recordForm(BuildContext c, AppStore st, String set, String title, List<FS> fields, {Rec? edit, Rec? preset, void Function(Rec)? beforeSave}) async {
  final r = edit ?? <String, dynamic>{'id': newId(set[0]), 'addedAt': nowMs(), ...?preset};
  final ctr = {for (final f in fields) f.key: TextEditingController(text: s(r[f.key]))};
  final vals = {for (final f in fields) f.key: s(r[f.key])};
  var saved = false;
  await showSheet<void>(c, title: title, body: (ctx) => StatefulBuilder(builder: (ctx, set2) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final f in fields)
        if (f.kind == 'date')
          DateField(f.label, vals[f.key]!, (v) => set2(() => vals[f.key] = v))
        else if (f.kind.startsWith('pick:'))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(f.label, style: TextStyle(color: pal.dim, fontSize: 12, fontWeight: FontWeight.w700))),
              Pills([for (final o in f.kind.substring(5).split(',')) (o, o)], vals[f.key]!, (v) => set2(() => vals[f.key] = v)),
            ]),
          )
        else
          Field(f.label, ctr[f.key]!, lines: f.kind == 'area' ? 3 : 1, type: f.kind == 'num' ? const TextInputType.numberWithOptions(decimal: true) : null),
      gap(),
      Btn('Simpan', () {
        for (final f in fields) {
          final v = (f.kind == 'date' || f.kind.startsWith('pick:')) ? vals[f.key]! : ctr[f.key]!.text.trim();
          r[f.key] = f.kind == 'num' && v.isNotEmpty ? (num.tryParse(v.replaceAll(',', '.')) ?? 0) : v;
        }
        beforeSave?.call(r);
        st.upsert(set, r);
        saved = true;
        Navigator.pop(ctx);
      }, accent: true),
    ]);
  }));
  return saved;
}

Widget _head(String title, int n, {List<Widget> actions = const []}) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [Expanded(child: H3(title, count: n)), ...actions]),
    );

Widget _item(BuildContext c, {required String title, String sub = '', Widget? trailing, List<Widget> chips = const [], VoidCallback? onTap, Color? bar}) => Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: bar == null ? null : BoxDecoration(border: Border(left: BorderSide(color: bar, width: 4))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800))), if (trailing != null) trailing]),
            if (sub.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(sub, style: TextStyle(color: pal.dim, fontSize: 12.5))),
            if (chips.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Wrap(spacing: 6, runSpacing: 6, children: chips)),
          ]),
        ),
      ),
    );

Widget _chip(String t, Color c) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: c.withOpacity(.16), borderRadius: BorderRadius.circular(20)),
      child: Text(t, style: TextStyle(color: c, fontSize: 11.5, fontWeight: FontWeight.w800)),
    );

// ============================ Prospek ============================
class ProspekPage extends StatelessWidget {
  final AppStore store;
  const ProspekPage({super.key, required this.store});
  static const fields = [
    FS('nama', 'Nama'), FS('telp', 'No. WA', 'text'), FS('rencana', 'Rencana perawatan', 'area'),
    FS('status', 'Status', 'pick:Menunggu,Dihubungi,Selesai,Batal'), FS('catatan', 'Catatan', 'area'),
  ];
  @override
  Widget build(BuildContext context) {
    final l = store.data['prospek']!.toList()..sort((a, b) => n(b['updatedAt']).compareTo(n(a['updatedAt'])));
    return ListView(children: [
      _head('Prospek WA', l.where(prWait).length, actions: [Btn('➕ Tambah', () => recordForm(context, store, 'prospek', 'Prospek baru', fields, preset: {'status': 'Menunggu'}), accent: true, small: true)]),
      if (l.isEmpty) const Empty('Belum ada prospek.'),
      for (final p in l)
        _item(context,
            title: s(p['nama']),
            sub: [s(p['telp']), s(p['rencana'])].where((x) => x.isNotEmpty).join(' · '),
            bar: prWait(p) ? pal.accent : pal.faint,
            trailing: _chip(s(p['status']).isEmpty ? 'Menunggu' : s(p['status']), prWait(p) ? pal.accent : pal.faint),
            onTap: () => recordForm(context, store, 'prospek', 'Ubah prospek', fields, edit: p)),
    ]);
  }
}

// ============================ Gigi tiruan ============================
class GigiPage extends StatelessWidget {
  final AppStore store;
  const GigiPage({super.key, required this.store});
  static const fields = [
    FS('nama', 'Nama pasien'), FS('telp', 'No. telepon'), FS('jenis', 'Jenis gigi tiruan'),
    FS('transferLab', 'Dibayar ke lab', 'pick:Belum,Sudah'), FS('kirimLab', 'Dikirim ke lab', 'pick:Belum,Sudah'),
    FS('datang', 'Sudah datang', 'pick:Belum,Sudah'), FS('insersi', 'Insersi', 'pick:Belum,Sudah'), FS('catatan', 'Catatan', 'area'),
  ];
  @override
  Widget build(BuildContext context) {
    final l = store.data['gigi']!.toList()..sort((a, b) => (gDone(a) ? 1 : 0).compareTo(gDone(b) ? 1 : 0));
    return ListView(children: [
      _head('Gigi Tiruan', l.where((g) => !gDone(g)).length, actions: [Btn('➕ Tambah', () => recordForm(context, store, 'gigi', 'Gigi tiruan baru', fields, preset: {'transferLab': 'Belum', 'kirimLab': 'Belum', 'datang': 'Belum', 'insersi': 'Belum'}), accent: true, small: true)]),
      if (l.isEmpty) const Empty('Belum ada data.'),
      for (final g in l)
        _item(context,
            title: s(g['nama']),
            sub: '${s(g['jenis'])} · ${gStage(g)}',
            bar: gDone(g) ? pal.good : gStuck(g) ? pal.warn : pal.accent,
            trailing: gStuck(g) ? _chip('Tertahan', pal.warn) : gDone(g) ? _chip('Selesai', pal.good) : null,
            onTap: () => recordForm(context, store, 'gigi', 'Ubah gigi tiruan', fields, edit: g)),
    ]);
  }
}

// ============================ Stok obat ============================
class StokPage extends StatelessWidget {
  final AppStore store;
  const StokPage({super.key, required this.store});
  static const fields = [FS('nama', 'Nama obat/bahan'), FS('satuan', 'Satuan'), FS('stokAwal', 'Stok awal', 'num')];
  static const beliF = [FS('nama', 'Barang'), FS('jumlah', 'Jumlah'), FS('catatan', 'Catatan')];

  @override
  Widget build(BuildContext context) {
    final rows = stokRows(store.data['stok']!, store.data['mutasi']!)..sort((a, b) => b.st.tone.compareTo(a.st.tone));
    final ex = expList(store.data['stok']!, store.data['mutasi']!);
    final beli = store.data['beli']!;
    return ListView(children: [
      _head('Stok Obat', rows.length, actions: [
        Btn('➕ Obat', () => recordForm(context, store, 'stok', 'Obat baru', fields, preset: {'stokAwal': 0}), small: true),
        const SizedBox(width: 6),
        Btn('📦 Mutasi', () => showMutasiDialog(context, store), accent: true, small: true),
      ]),
      if (ex.isNotEmpty)
        Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('⏳ Expired / hampir expired', style: TextStyle(color: pal.danger, fontWeight: FontWeight.w800)),
          for (final e in ex.take(10)) Text('${e.nama} · ${e.t} · ${e.days < 0 ? 'lewat ${-e.days} hari' : '${e.days} hari lagi'} · sisa ${fmtQty(e.q)} ${e.satuan}', style: const TextStyle(fontSize: 12.5)),
        ])),
      if (rows.isEmpty) const Empty('Belum ada data stok.'),
      for (final r in rows)
        _item(context,
            title: s(r.item['nama']),
            sub: 'Awal ${fmtQty(n(r.item['stokAwal']))} · masuk ${fmtQty(r.mv.masuk)} · keluar ${fmtQty(r.mv.keluar)}',
            bar: r.st.tone == 2 ? pal.danger : r.st.tone == 1 ? pal.warn : pal.good,
            trailing: Text('${fmtQty(r.akhir)} ${s(r.item['satuan'])}', style: TextStyle(fontWeight: FontWeight.w900, color: r.st.tone == 2 ? pal.danger : r.st.tone == 1 ? pal.warn : pal.text)),
            chips: [_chip(r.st.label, r.st.tone == 2 ? pal.danger : r.st.tone == 1 ? pal.warn : pal.good)],
            onTap: () => recordForm(context, store, 'stok', 'Ubah stok', fields, edit: r.item)),
      gap(8),
      _head('Daftar beli', beli.length, actions: [Btn('➕', () => recordForm(context, store, 'beli', 'Barang dibeli', beliF), small: true)]),
      for (final b in beli)
        _item(context, title: s(b['nama']), sub: '${s(b['jumlah'])} ${s(b['catatan'])}'.trim(),
            trailing: IconButton(icon: const Icon(Icons.check_circle_outline), onPressed: () => store.removeKey('beli', s(b['id']))),
            onTap: () => recordForm(context, store, 'beli', 'Ubah', beliF, edit: b)),
    ]);
  }
}

/// Catat mutasi (masuk/keluar) satu barang; menolak bila stok jadi minus.
Future<void> showMutasiDialog(BuildContext c, AppStore st) {
  final stok = st.data['stok']!;
  if (stok.isEmpty) {
    toast('Tambahkan obat dulu di Stok Obat', 'warn');
    return Future.value();
  }
  var pick = s(stok.first['nama']), jenis = 'MASUK', tgl = todayIso();
  final jml = TextEditingController(), exp = TextEditingController(), ket = TextEditingController();
  return showSheet<void>(c, title: 'Catat mutasi', body: (ctx) => StatefulBuilder(builder: (ctx, set) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Pills([for (final o in stok) (s(o['nama']), s(o['nama']))], pick, (v) => set(() => pick = v)),
      gap(),
      Pills(const [('MASUK', 'Masuk'), ('KELUAR', 'Keluar')], jenis, (v) => set(() => jenis = v)),
      gap(),
      DateField('Tanggal', tgl, (v) => set(() => tgl = v.isEmpty ? todayIso() : v), allowClear: false),
      Field('Jumlah', jml, type: const TextInputType.numberWithOptions(decimal: true)),
      if (jenis == 'MASUK') Field('Expired (dd/mm/yy atau mm/yy)', exp),
      Field('Keterangan', ket),
      Btn('Simpan', () {
        final q = n(jml.text);
        if (q <= 0) {
          toast('Jumlah harus > 0', 'warn');
          return;
        }
        final rec = <String, dynamic>{'id': newId('m'), 'addedAt': nowMs(), 'tanggal': tgl, 'nama': pick, 'jenis': jenis, 'jumlah': q, 'expired': exp.text.trim(), 'ket': ket.text.trim()};
        if (jenis == 'KELUAR') {
          final neg = cariStokMinus(st.data['stok']!, [...st.data['mutasi']!, rec], [pick]);
          if (neg != null) {
            toast('Stok ${neg.nama} akan minus (${fmtQty(neg.akhir)} ${neg.satuan})', 'err');
            return;
          }
        }
        st.saveMutasiBatch([rec]);
        toast('Mutasi tersimpan');
        Navigator.pop(ctx);
      }, accent: true),
    ]);
  }));
}

// ============================ Riwayat mutasi ============================
class MutasiPage extends StatelessWidget {
  final AppStore store;
  const MutasiPage({super.key, required this.store});
  @override
  Widget build(BuildContext context) {
    final l = store.data['mutasi']!.toList()..sort((a, b) => cmpMutasiAsc(b, a));
    return ListView(children: [
      _head('Riwayat Mutasi', l.length, actions: [Btn('➕ Catat', () => showMutasiDialog(context, store), accent: true, small: true)]),
      if (l.isEmpty) const Empty('Belum ada mutasi.'),
      for (final m in l.take(300))
        _item(context,
            title: '${s(m['nama'])}',
            sub: '${fmtIsoShort(s(m['tanggal']))} · ${s(m['ket'])}${s(m['expired']).isEmpty ? '' : ' · exp ${m['expired']}'}',
            bar: s(m['jenis']).toUpperCase() == 'MASUK' ? pal.good : pal.warn,
            trailing: Text('${s(m['jenis']).toUpperCase() == 'MASUK' ? '+' : '-'}${fmtQty(n(m['jumlah']))}', style: const TextStyle(fontWeight: FontWeight.w900)),
            onTap: () async {
              if (await confirmDialog(context, 'Hapus mutasi ini?', ok: 'Hapus')) store.removeKey('mutasi', s(m['id']));
            }),
    ]);
  }
}
