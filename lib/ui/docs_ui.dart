import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../core/docs.dart';
import '../core/io_util.dart';
import '../core/store.dart';
import '../core/util.dart';
import 'common.dart';
import 'odo_page.dart';

// ============================ Tanda tangan ============================
class SignPad extends StatefulWidget {
  final void Function(List<List<Offset>> strokes, Size size) onChanged;
  const SignPad({super.key, required this.onChanged});
  @override
  State<SignPad> createState() => SignPadState();
}

class SignPadState extends State<SignPad> {
  final List<List<Offset>> strokes = [];
  Size size = const Size(300, 140);
  void clear() {
    setState(strokes.clear);
    widget.onChanged(strokes, size);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (c, cs) {
        size = Size(cs.maxWidth, 150);
        return Container(
          height: 150,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: pal.border)),
          child: GestureDetector(
            onPanStart: (d) => setState(() => strokes.add([d.localPosition])),
            onPanUpdate: (d) => setState(() => strokes.last.add(d.localPosition)),
            onPanEnd: (_) => widget.onChanged(strokes, size),
            child: CustomPaint(painter: _SignPainter(strokes), size: Size.infinite),
          ),
        );
      });
}

class _SignPainter extends CustomPainter {
  final List<List<Offset>> strokes;
  _SignPainter(this.strokes);
  @override
  void paint(Canvas canvas, Size size) => paintStrokes(canvas, strokes);
  @override
  bool shouldRepaint(covariant _SignPainter old) => true;
}

void paintStrokes(Canvas canvas, List<List<Offset>> strokes) {
  final p = Paint()..color = const Color(0xFF111111)..strokeWidth = 2.4..style = PaintingStyle.stroke..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
  for (final s in strokes) {
    if (s.length == 1) {
      canvas.drawCircle(s.first, 1.2, p..style = PaintingStyle.fill);
      p.style = PaintingStyle.stroke;
    } else {
      final path = Path()..moveTo(s.first.dx, s.first.dy);
      for (final o in s.skip(1)) {
        path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(path, p);
    }
  }
}

Future<Uint8List> strokesToPng(List<List<Offset>> strokes, Size size) async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  paintStrokes(c, strokes);
  final img = await rec.endRecording().toImage(size.width.round().clamp(1, 2000), size.height.round().clamp(1, 2000));
  final bd = await img.toByteData(format: ui.ImageByteFormat.png);
  return bd!.buffer.asUint8List();
}

/// Dialog tanda tangan -> PNG transparan (base64) atau null.
Future<String?> askSignature(BuildContext c, String title) async {
  List<List<Offset>> st = [];
  Size sz = const Size(300, 150);
  final key = GlobalKey<SignPadState>();
  String? out;
  await showSheet<void>(c, title: title, maxWidth: 480, body: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    SignPad(key: key, onChanged: (s, z) { st = s; sz = z; }),
    gap(),
    Row(children: [
      Btn('Hapus', () => key.currentState?.clear(), small: true),
      const Spacer(),
      Btn('Pakai', () async {
        if (st.isEmpty) { toast('Belum ada tanda tangan', 'warn'); return; }
        out = base64Encode(await strokesToPng(st, sz));
        if (ctx.mounted) Navigator.pop(ctx);
      }, accent: true),
    ]),
  ]));
  return out;
}

// ============================ Pratinjau PDF ============================
Future<void> previewPdf(BuildContext c, AppStore st, String name, Uint8List bytes, {String folder = 'export'}) {
  return Navigator.of(c).push(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (ctx) => Scaffold(
      appBar: AppBar(title: Text(name, style: const TextStyle(fontSize: 14)), actions: [
        IconButton(tooltip: 'Kirim / simpan', icon: const Icon(Icons.ios_share), onPressed: () => deliver(ctx, st, name, bytes, 'application/pdf', folder: folder)),
      ]),
      body: PdfPreview(
        build: (_) async => bytes,
        pdfFileName: name,
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
      ),
    ),
  ));
}

// ============================ Dokumen pasien ============================
Future<void> showPatientDocs(BuildContext c, AppStore st, Rec p) {
  return showSheet<void>(c, title: 'Dokumen · ${p['nama']}', maxWidth: 480, body: (ctx) {
    Widget item(String t, String sub, Future<void> Function() fn) => ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(t, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(sub, style: TextStyle(color: pal.dim, fontSize: 12)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            Navigator.pop(ctx);
            await fn();
          },
        );
    final rm = s(p['noFile']);
    return Column(children: [
      item('Rekam medis', 'Riwayat kunjungan seluruhnya', () async {
        await previewPdf(c, st, 'Rekam-Medis-${fname([rm, p['nama']])}.pdf', await rekamMedisPdf(st, p));
      }),
      item('Nota biaya', 'Pilih kunjungan yang ditagih', () async {
        final hist = st.entry.where((e) => s(e['noFile']) == rm).toList().reversed.toList();
        if (hist.isEmpty) { toast('Belum ada kunjungan', 'warn'); return; }
        final sel = <Rec>{...hist.take(1)};
        if (!c.mounted) return;
        final ok = await showSheet<bool>(c, title: 'Nota ${p['nama']}', body: (c2) => StatefulBuilder(builder: (c2, set) => Column(children: [
          for (final e in hist.take(30))
            CheckboxListTile(
              dense: true,
              value: sel.contains(e),
              onChanged: (v) => set(() => v == true ? sel.add(e) : sel.remove(e)),
              title: Text('${e['tanggal']} · ${s(e['perawatan'])}', maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(rp(n(e['biaya']))),
            ),
          gap(),
          Btn('Buat nota', () => Navigator.pop(c2, true), accent: true),
        ])));
        if (ok == true && c.mounted) {
          await previewPdf(c, st, 'Nota-${fname([rm, p['nama']])}.pdf', await notaPdf(st, p, sel.toList()));
        }
      }),
      item('Odontogram', 'Bagan + rencana perawatan', () async {
        st.odo.loadSnapshot(p['odo'] as Map?, {'rm': rm, 'nama': s(p['nama']), 'alamat': s(p['alamat']), 'telp': s(p['telp'])});
        final png = await renderOdoPng(st.odo);
        if (c.mounted) await previewPdf(c, st, 'Odontogram-${fname([rm, p['nama']])}.pdf', await odontogramPdf(st, p, png));
      }),
      item('Inform consent', 'Persetujuan tindakan medis + tanda tangan', () async {
        if (c.mounted) await showConsentForm(c, st, p);
      }),
    ]);
  });
}

// ============================ Inform consent ============================
Future<void> showConsentForm(BuildContext c, AppStore st, Rec p) {
  final tindakan = TextEditingController(), tgl = TextEditingController(text: todayIso());
  final penanda = TextEditingController(text: s(p['nama']));
  var hub = hubungan.first, setuju = 'SETUJU';
  String? sigPas;
  var dokId = st.jagaId;
  return showSheet<void>(c, title: 'Inform consent · ${p['nama']}', body: (ctx) => StatefulBuilder(builder: (ctx, set) {
    final dok = firstWhereOrNull(st.dokterVis, (d) => d['id'] == dokId);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Dokter pelaksana', style: TextStyle(color: pal.dim, fontSize: 12, fontWeight: FontWeight.w700)),
      gap(4),
      if (st.dokterVis.isEmpty) const Hint('Belum ada dokter. Tambahkan lewat tombol Dokter jaga di Beranda.')
      else Pills([for (final d in st.dokterVis) (s(d['id']), s(d['nama']))], dokId, (v) => set(() => dokId = v)),
      gap(),
      Text('Hubungan dengan pasien', style: TextStyle(color: pal.dim, fontSize: 12, fontWeight: FontWeight.w700)),
      gap(4),
      Pills([for (final h in hubungan) (h, h)], hub, (v) => set(() => hub = v)),
      gap(),
      Field('Yang membuat pernyataan (nama)', penanda),
      Pills(const [('SETUJU', 'Setuju'), ('TIDAK', 'Tidak setuju')], setuju, (v) => set(() => setuju = v)),
      gap(),
      Field('Tindakan medis', tindakan, lines: 3, hint: 'mis. Pencabutan gigi 48 dengan anestesi lokal'),
      DateField('Tanggal', tgl.text, (v) => set(() => tgl.text = v.isEmpty ? todayIso() : v), allowClear: false),
      Row(children: [
        Btn(sigPas == null ? '✍️ Tanda tangan pasien' : '✅ Tanda tangan ada (ulangi)', () async {
          final r = await askSignature(ctx, 'Tanda tangan pasien / wali');
          if (r != null) set(() => sigPas = r);
        }, small: true),
      ]),
      gap(14),
      Btn('Simpan & buat PDF', () async {
        if (tindakan.text.trim().isEmpty) { toast('Isi tindakan medis', 'warn'); return; }
        final rec = <String, dynamic>{
          'id': newId('c'), 'rm': s(p['noFile']), 'nama': s(p['nama']), 'umur': s(p['umur']), 'alamat': s(p['alamat']), 'telp': s(p['telp']),
          'hub': hub, 'penanda': penanda.text.trim(), 'setuju': setuju, 'tindakan': tindakan.text.trim(), 'tgl': tgl.text,
          'dokter': dok == null ? '' : s(dok['nama']), 'dsig': dok == null ? '' : 'dok:${dok['id']}', if (sigPas != null) 'sig': sigPas,
        };
        st.upsert('consent', rec);
        Navigator.pop(ctx);
        if (c.mounted) await previewPdf(c, st, 'Inform-Consent-${fname([rec['rm'], rec['nama']])}.pdf', await consentPdf(st, rec));
      }, accent: true),
    ]);
  }));
}

// ============================ Dokter ============================
Future<void> showDokterDialog(BuildContext c, AppStore st) {
  return showSheet<void>(c, title: 'Dokter jaga', maxWidth: 480, body: (ctx) => StatefulBuilder(builder: (ctx, set) {
    final l = st.dokterVis;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (l.isEmpty) const Hint('Belum ada dokter.'),
      for (final d in l)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(st.jagaId == d['id'] ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: pal.accent),
          title: Text(s(d['nama']), style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('Paraf: ${s(d['paraf']).isEmpty ? '-' : d['paraf']} · TTD: ${s(d['sig']).isEmpty ? 'bawaan' : 'tersimpan'}'),
          onTap: () { st.setJaga(s(d['id'])); set(() {}); },
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(icon: const Icon(Icons.edit, size: 18), onPressed: () async { await _editDokter(ctx, st, d); set(() {}); }),
            IconButton(icon: Icon(Icons.delete_outline, size: 18, color: pal.danger), onPressed: () async {
              if (await confirmDialog(ctx, 'Hapus ${d['nama']}?', ok: 'Hapus')) { st.deleteDokter(s(d['id'])); set(() {}); }
            }),
          ]),
        ),
      gap(),
      Btn('➕ Tambah dokter', () async { await _editDokter(ctx, st, null); set(() {}); }, accent: true),
    ]);
  }));
}

Future<void> _editDokter(BuildContext c, AppStore st, Rec? d) {
  final nama = TextEditingController(text: s(d?['nama'])), paraf = TextEditingController(text: s(d?['paraf']));
  var sig = s(d?['sig']);
  return showSheet<void>(c, title: d == null ? 'Dokter baru' : 'Ubah dokter', maxWidth: 440, body: (ctx) => StatefulBuilder(builder: (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Field('Nama (mis. drg. Nama)', nama),
    Field('Paraf (inisial)', paraf),
    if (sig.isNotEmpty) Container(height: 70, color: Colors.white, child: Image.memory(base64Decode(sig))),
    gap(6),
    Btn(sig.isEmpty ? '✍️ Buat tanda tangan' : '✍️ Ganti tanda tangan', () async {
      final r = await askSignature(ctx, 'Tanda tangan dokter');
      if (r != null) set(() => sig = r);
    }, small: true),
    gap(14),
    Btn('Simpan', () {
      if (nama.text.trim().isEmpty) { toast('Nama wajib', 'warn'); return; }
      st.saveDokter({'id': d == null ? newId('d') : s(d['id']), 'nama': nama.text.trim(), 'paraf': paraf.text.trim(), 'sig': sig});
      Navigator.pop(ctx);
    }, accent: true),
  ])));
}
