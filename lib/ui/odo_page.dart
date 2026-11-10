import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/odo.dart';
import '../core/util.dart';
import '../core/store.dart';
import '../core/util.dart';
import 'common.dart';

const _modes = <(String, String)>[
  ('tambal', 'Tambal'), ('exo', 'Cabut'), ('cabut', 'Sudah dicabut'), ('gt', 'GT'), ('hapus', 'Hapus'),
];

Color stateColor(String st, [String? k]) {
  switch (st) {
    case 'tambal':
      return k == 'PR' ? const Color(0xFF2E7D32) : k == 'PI' ? const Color(0xFFF9A825) : const Color(0xFF1565C0);
    case 'exo':
      return const Color(0xFFC62828);
    case 'cabut':
      return const Color(0xFF616161);
    default:
      return Colors.transparent;
  }
}

/// Peta kolom -> posisi sel 38x38 sesuai bagan (608 x 285).
Rect cellRect(int col, int y) => Rect.fromLTWH(col * 38.0 + 0, y.toDouble(), 38, 38);

class OdoPainter extends CustomPainter {
  final OdoModel m;
  final bool dark;
  OdoPainter(this.m, this.dark);

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 608, sy = size.height / 285;
    canvas.scale(sx, sy);
    final line = Paint()..color = dark ? const Color(0xFF8FA3AB) : const Color(0xFF445A63)..style = PaintingStyle.stroke..strokeWidth = 1.3;
    for (final row in odoRows) {
      var col = row.$2;
      for (final t in row.$1) {
        final r = cellRect(col++, row.$3);
        // gigi tiruan (latar muda)
        if (m.hasGt(t)) {
          canvas.drawRRect(RRect.fromRectAndRadius(r.deflate(1), const Radius.circular(6)), Paint()..color = const Color(0x55E58AB0));
        }
        final tt = m.tooth(t);
        final box = Rect.fromLTWH(r.left + 4, r.top + 3, 30, 30);
        if (tt != null) {
          final c = stateColor(s(tt['s']), s(tt['k']));
          if (tt['s'] == 'exo' || tt['s'] == 'cabut') {
            canvas.drawRect(box, Paint()..color = c.withOpacity(.35));
          } else {
            canvas.drawRect(box, Paint()..color = c.withOpacity(.75));
          }
        }
        canvas.drawRect(box, line);
        canvas.drawRect(Rect.fromLTWH(box.left + 9, box.top + 11, 12, 8), line);
        canvas.drawLine(box.topLeft, Offset(box.left + 9, box.top + 11), line);
        canvas.drawLine(box.topRight, Offset(box.left + 21, box.top + 11), line);
        canvas.drawLine(box.bottomLeft, Offset(box.left + 9, box.top + 19), line);
        canvas.drawLine(box.bottomRight, Offset(box.left + 21, box.top + 19), line);
        if (tt != null && (tt['s'] == 'exo' || tt['s'] == 'cabut')) {
          final x = Paint()..color = stateColor(s(tt['s']))..strokeWidth = 2.2;
          canvas.drawLine(box.topLeft, box.bottomRight, x);
          canvas.drawLine(box.topRight, box.bottomLeft, x);
        }
        final tp = TextPainter(
          text: TextSpan(text: '$t', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: dark ? Colors.white70 : Colors.black87)),
          textDirection: TextDirection.ltr,
        )..layout();
        final above = row.$3 < 100;
        tp.paint(canvas, Offset(r.left + 19 - tp.width / 2, above ? r.top - 11 : r.bottom - 1));
        if (tt != null && tt['s'] == 'tambal') {
          final lb = TextPainter(text: TextSpan(text: s(tt['k']), style: const TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.w800)), textDirection: TextDirection.ltr)..layout();
          lb.paint(canvas, Offset(box.center.dx - lb.width / 2, box.top - 0.5 + (box.height - lb.height) / 2 - 8));
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant OdoPainter old) => true;
}

/// Render bagan ke PNG (untuk PDF / ekspor).
Future<Uint8List> renderOdoPng(OdoModel m, {double scale = 2.0}) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 608 * 2, 285 * 2), Paint()..color = Colors.white);
  canvas.scale(scale);
  final size = Size(608, 285);
  OdoPainter(m, false).paint(canvas, size);
  final img = await rec.endRecording().toImage((608 * scale).round(), (285 * scale).round());
  final bd = await img.toByteData(format: ui.ImageByteFormat.png);
  return bd!.buffer.asUint8List();
}


Future<void> openOdontogram(BuildContext c, AppStore st, {Rec? pasien}) {
  if (pasien != null) {
    st.odo.loadSnapshot(pasien['odo'] as Map?, {'rm': s(pasien['noFile']), 'nama': s(pasien['nama']), 'alamat': s(pasien['alamat']), 'telp': s(pasien['telp'])});
    st.odoChanged();
  }
  return Navigator.of(c).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => OdoScreen(store: st)));
}

class OdoScreen extends StatefulWidget {
  final AppStore store;
  const OdoScreen({super.key, required this.store});
  @override
  State<OdoScreen> createState() => _OdoScreenState();
}

class _OdoScreenState extends State<OdoScreen> {
  AppStore get st => widget.store;
  OdoModel get m => st.odo;
  String tab = 'bagan';

  void _tap(Offset p, Size sz) {
    final x = p.dx / (sz.width / 608), y = p.dy / (sz.height / 285);
    for (final row in odoRows) {
      var col = row.$2;
      for (final t in row.$1) {
        final r = cellRect(col++, row.$3).inflate(row.$3 < 100 ? 4 : 4);
        if (r.contains(Offset(x, y))) {
          final msg = m.tap(t);
          if (msg != null) toast(msg, 'warn');
          st.odoChanged();
          setState(() {});
          return;
        }
      }
    }
  }

  Widget _chart() {
    final double zoom = n(m.S['zoom']).toDouble().clamp(1.0, 3.0).toDouble();
    return LayoutBuilder(builder: (c, cs) {
      final w = cs.maxWidth * zoom, h = w * 285 / 608;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: GestureDetector(
          onTapUp: (d) => _tap(d.localPosition, Size(w, h)),
          child: Container(
            width: w, height: h,
            decoration: BoxDecoration(color: pal.surface, border: Border.all(color: pal.border), borderRadius: BorderRadius.circular(8)),
            child: CustomPaint(painter: OdoPainter(m, !st.lightTheme)),
          ),
        ),
      );
    });
  }

  Future<void> _patientDialog() async {
    final nama = TextEditingController(text: s(m.pat['nama'])), rm = TextEditingController(text: s(m.pat['rm']));
    final alamat = TextEditingController(text: s(m.pat['alamat'])), telp = TextEditingController(text: s(m.pat['telp']));
    await showSheet<void>(context, title: 'Pasien odontogram', body: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Field('No. RM', rm, type: TextInputType.number, onChanged: (v) {
        final p = st.findPasien(normNoFile(v));
        if (p != null) {
          nama.text = s(p['nama']);
          alamat.text = s(p['alamat']);
          telp.text = ph(p['telp']);
        }
      }),
      Field('Nama', nama), Field('Alamat', alamat), Field('Telepon', telp),
      Btn('Simpan', () {
        m.S['p'] = {'rm': normNoFile(rm.text), 'nama': nama.text.trim(), 'alamat': alamat.text.trim(), 'telp': telp.text.trim()};
        st.odoChanged();
        Navigator.pop(ctx);
      }, accent: true),
    ]));
    setState(() {});
  }

  Future<void> _editHarga(Rec h) async {
    final nama = TextEditingController(text: s(h['nama'])), hh = TextEditingController(text: s(h['h']));
    final hb = TextEditingController(text: s(h['hb'])), a = TextEditingController(text: s(h['a']));
    await showSheet<void>(context, title: 'Harga ${h['nama']}', body: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Field('Nama', nama),
      Field('Harga (ribuan, boleh rentang 150-200)', hh),
      if (h['k'] == 'cabut') Field('Harga rahang bawah (kosong = sama)', hb),
      if (h['k'] == 'lepasan') Field('Tambahan per gigi (ribuan)', a),
      gap(),
      Row(children: [
        Expanded(child: Btn('Simpan', () {
          h['nama'] = nama.text.trim();
          h['h'] = hh.text.trim();
          if (h['k'] == 'cabut') h['hb'] = hb.text.trim();
          if (h['k'] == 'lepasan') h['a'] = a.text.trim();
          st.odoChanged();
          Navigator.pop(ctx);
        }, accent: true)),
        if (!['tam_ant', 'tam_post', 'psa'].contains(h['id'])) ...[
          const SizedBox(width: 8),
          Btn('Hapus', () { m.H.remove(h); st.odoChanged(); Navigator.pop(ctx); }, color: pal.danger),
        ],
      ]),
    ]));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final o = m.calc();
    final notes = m.notes();
    final c = m.cnt();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Odontogram', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          TextButton(onPressed: _patientDialog, child: Text(s(m.pat['nama']).isEmpty ? 'Pasien' : s(m.pat['nama']))),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: ListView(padding: const EdgeInsets.all(14), children: [
            Pills(const [('bagan', 'Bagan'), ('hitung', 'Hitung GT'), ('harga', 'Harga')], tab, (v) => setState(() => tab = v)),
            gap(),
            if (tab == 'bagan') ...[
              Pills(_modes, s(m.S['mode']), (v) => setState(() { m.S['mode'] = v; st.odoChanged(); })),
              if (m.S['mode'] == 'exo')
                Padding(padding: const EdgeInsets.only(top: 8), child: Pills([for (final it in m.cab()) (s(it['id']), s(it['nama']))], s(m.curExo()?['id']), (v) => setState(() { m.S['exoKind'] = v; st.odoChanged(); }))),
              gap(),
              Row(children: [
                Text('Zoom', style: TextStyle(color: pal.dim, fontSize: 12)),
                Expanded(child: Slider(value: n(m.S['zoom']).toDouble().clamp(1.0, 3.0).toDouble(), min: 1, max: 3, divisions: 8, onChanged: (v) => setState(() { m.S['zoom'] = v; st.odoSaved(); }))),
              ]),
              _chart(),
              gap(),
              Hint('Tambal: ketuk bergantian PR (hijau) → PI (kuning) → NP (biru). GT: ketuk gigi yang akan dibuatkan gigi tiruan.'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                Btn('Hapus semua', () async {
                  if (await confirmDialog(context, 'Kosongkan seluruh bagan?')) { m.clearChart(); st.odoChanged(); setState(() {}); }
                }, small: true, color: pal.danger),
                Btn('GT penuh RA', () { m.full('atas', allTeeth.where((t) => arch(t) == 'atas' && !ud.contains(t)).toList()); st.odoChanged(); setState(() {}); }, small: true),
                Btn('GT penuh RB', () { m.full('bawah', allTeeth.where((t) => arch(t) == 'bawah' && !ld.contains(t)).toList()); st.odoChanged(); setState(() {}); }, small: true),
                Btn('💾 Simpan ke pasien', () {
                  final rm = s(m.pat['rm']);
                  if (rm.isEmpty || st.findPasien(rm) == null) { toast('Pilih pasien terdaftar (No. RM) dulu', 'warn'); return; }
                  st.saveOdoToPasien(rm, m.snapshot());
                  toast('Odontogram tersimpan di data pasien');
                }, accent: true, small: true),
              ]),
              gap(14),
              Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const H3('Catatan'),
                gap(6),
                for (final t in notes) Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text('• $t')),
              ])),
            ],
            if (tab == 'hitung') ...[
              for (final a in ['atas', 'bawah'])
                Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Rahang ${a == 'atas' ? 'atas (RA)' : 'bawah (RB)'} · ${c.G[a]} gigi', style: const TextStyle(fontWeight: FontWeight.w800)),
                  gap(6),
                  Pills([for (final h in m.H.where((x) => ['lepasan', 'permanen', 'full'].contains(x['k']))) (s(h['id']), s(h['nama']))], s(m.item(a)['id']), (v) => setState(() { m.gtSel[a] = v; st.odoChanged(); })),
                  if (m.item(a)['k'] == 'permanen') Row(children: [
                    const Text('Pegangan'),
                    IconButton(onPressed: () => setState(() { m.peg[a] = ((m.peg[a] ?? 0) as int) > 0 ? (m.peg[a] as int) - 1 : 0; st.odoChanged(); }), icon: const Icon(Icons.remove_circle_outline)),
                    Text('${m.peg[a] ?? 0}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    IconButton(onPressed: () => setState(() { m.peg[a] = ((m.peg[a] ?? 0) as int) + 1; st.odoChanged(); }), icon: const Icon(Icons.add_circle_outline)),
                  ]),
                ])),
              Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const H3('Rincian biaya'),
                gap(6),
                if (o.lines.isEmpty) const Hint('Belum ada tindakan.'),
                for (final l in o.lines)
                  Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [Expanded(child: Text(l[0], style: const TextStyle(fontWeight: FontWeight.w700))), Text(l[2], style: TextStyle(color: pal.accent, fontWeight: FontWeight.w800))]),
                    Text(l[1], style: TextStyle(color: pal.dim, fontSize: 12)),
                  ])),
                const Divider(),
                Row(children: [const Expanded(child: Text('TOTAL', style: TextStyle(fontWeight: FontWeight.w900))), Text(fr(o.tot), style: TextStyle(color: pal.accent, fontWeight: FontWeight.w900, fontSize: 16))]),
              ])),
              Btn('➕ Simpan sebagai prospek', () {
                final pl = m.plan();
                if (pl.list.isEmpty) { toast('Belum ada rencana', 'warn'); return; }
                st.upsert('prospek', {'id': newId('p'), 'nama': s(m.pat['nama']), 'telp': s(m.pat['telp']), 'rencana': '${pl.list.join('; ')} — ${fr(o.tot)}', 'status': 'Menunggu', 'addedAt': nowMs()});
                toast('Masuk Prospek WA');
              }, small: true),
            ],
            if (tab == 'harga') ...[
              for (final h in m.H)
                Card(margin: const EdgeInsets.only(bottom: 6), child: ListTile(
                  dense: true,
                  title: Text(s(h['nama']), style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${h['k']}${h['z'] != null ? ' · ${h['z']}' : ''}'),
                  trailing: Text(fr(rng(h['h'])), style: TextStyle(color: pal.accent, fontWeight: FontWeight.w800)),
                  onTap: () => _editHarga(h),
                )),
              Btn('➕ Jenis cabut baru', () {
                m.H.add({'id': newId('x'), 'nama': 'Baru', 'k': 'cabut', 'h': '0', 'hb': '', 's8': false});
                st.odoChanged();
                setState(() {});
              }, small: true),
            ],
          ]),
        ),
      ),
    );
  }
}
