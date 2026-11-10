import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'odo.dart';
import 'payments.dart';
import 'stock.dart';
import 'store.dart';
import 'util.dart';

const klNama = 'KILAW DENTAL CLINIC';
const klAlamat = 'Jl. Taman Safari II, Pekunden, Pakukerto,\nKec. Sukorejo, Pasuruan, Jawa Timur 67161';
const hubungan = ['Diri Sendiri', 'Orang Tua', 'Suami / Istri', 'Wali Hukum'];
const pernyataan =
    'Saya sudah mendengarkan penjelasan dokter, membaca, dan MEMAHAMI SEPENUHNYA semua risiko yang dijelaskan. Saya menyetujui tindakan ini tanpa paksaan, bersedia menerima risiko medis yang wajar terjadi, mengizinkan foto kondisi gigi dan mulut saya digunakan sebagai bahan edukasi kepada masyarakat luas baik secara online maupun offline, serta berjanji akan mematuhi semua anjuran perawatan yang diberikan oleh dokter gigi demi kesembuhan saya.';

Future<Uint8List> defaultSig() async => (await rootBundle.load('assets/ttd.png')).buffer.asUint8List();

/// Tanda tangan untuk dokumen: tanda tangan dokter jaga (bila ada) -> tersimpan -> bawaan.
Future<Uint8List> signatureFor(AppStore st, {Rec? dokter}) async {
  final b64 = s(dokter?['sig']).isNotEmpty ? s(dokter!['sig']) : (st.jaga != null ? s(st.jaga!['sig']) : '');
  if (b64.isNotEmpty) {
    try {
      return base64Decode(b64.contains(',') ? b64.split(',').last : b64);
    } catch (_) {}
  }
  if (st.savedSig.isNotEmpty) {
    try {
      return base64Decode(st.savedSig.contains(',') ? st.savedSig.split(',').last : st.savedSig);
    } catch (_) {}
  }
  return defaultSig();
}

pw.Widget _kop() => pw.Column(children: [
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.center, children: [
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: pw.BoxDecoration(color: PdfColor.fromHex('#1D5A50'), borderRadius: pw.BorderRadius.circular(4)),
          child: pw.Text('KILAW', style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 14)),
        ),
        pw.SizedBox(width: 10),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(klNama, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 15)),
          pw.Text(klAlamat, style: const pw.TextStyle(fontSize: 8.5)),
        ]),
      ]),
      pw.SizedBox(height: 4),
      pw.Divider(thickness: 1.5),
      pw.SizedBox(height: 6),
    ]);

pw.Widget _title(String t, {String? nomor}) => pw.Column(children: [
      pw.Center(child: pw.Text(t, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13, decoration: pw.TextDecoration.underline))),
      if (nomor != null) pw.Center(child: pw.Text(nomor, style: const pw.TextStyle(fontSize: 9))),
      pw.SizedBox(height: 10),
    ]);

pw.Widget _kv(List<List<String>> rows, {double w = 110}) => pw.Column(children: [
      for (final r in rows)
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.SizedBox(width: w, child: pw.Text(r[0], style: const pw.TextStyle(fontSize: 10))),
            pw.Expanded(child: pw.Text(': ${r[1].isEmpty ? '-' : r[1]}', style: const pw.TextStyle(fontSize: 10))),
          ]),
        ),
    ]);

pw.Widget _tbl(List<String> head, List<List<String>> rows, {List<double>? widths}) => pw.Table(
      border: pw.TableBorder.all(width: .6),
      columnWidths: widths == null ? null : {for (var i = 0; i < widths.length; i++) i: pw.FlexColumnWidth(widths[i])},
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey300),
          children: [for (final h in head) pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(h, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9.5)))],
        ),
        if (rows.isEmpty)
          pw.TableRow(children: [for (var i = 0; i < head.length; i++) pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(i == 0 ? 'Tidak ada.' : '', style: const pw.TextStyle(fontSize: 9.5)))]),
        for (final r in rows) pw.TableRow(children: [for (final c in r) pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(c, style: const pw.TextStyle(fontSize: 9.5)))]),
      ],
    );

pw.Widget _ttd(String label, String who, Uint8List sig) => pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Container(
        width: 190,
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
          pw.Text('Pasuruan, ${tglID()}', style: const pw.TextStyle(fontSize: 10)),
          pw.Text(label, style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 60, child: pw.Image(pw.MemoryImage(sig), fit: pw.BoxFit.contain)),
          pw.Text('( $who )', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        ]),
      ),
    );

pw.Document _doc() => pw.Document(title: 'Kilaw Dental Clinic', author: klNama);

pw.Page _page(List<pw.Widget> Function() build, {PdfPageFormat? fmt}) =>
    pw.Page(pageFormat: fmt ?? PdfPageFormat.a4, margin: const pw.EdgeInsets.fromLTRB(40, 34, 40, 34), build: (c) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: build()));

// ============================ Laporan bulanan ============================
Future<Uint8List> laporanBulananPdf(AppStore st, String ym, {Uint8List? sig}) async {
  final parts = ym.split('-');
  final bl = '${bulanNama[int.parse(parts[1]) - 1]} ${parts[0]}';
  final k = st.entry.where((e) => ymOfDmy(s(e['tanggal'])) == ym).toList();
  num tot = 0, cash = 0, qr = 0;
  final pr = <String, List<num>>{};
  for (final e in k) {
    final a = entryAmounts(e);
    tot += n(e['biaya']);
    cash += a.cash;
    qr += a.qr;
    final nm = s(e['paraf']).isEmpty ? 'Owner' : s(e['paraf']);
    final v = pr.putIfAbsent(nm, () => [0, 0]);
    v[0]++;
    v[1] += n(e['biaya']);
  }
  final unik = k.map((e) => s(e['noFile']).isEmpty ? s(e['nama']) : s(e['noFile'])).toSet().length;
  final ur = [
    ['Jumlah kunjungan', '${k.length} kunjungan'],
    ['Pasien unik', '$unik pasien'],
    ['Pendapatan total', rp(tot)],
    ['Pembayaran cash', rp(cash)],
    ['Pembayaran QR', rp(qr)],
  ];
  final signature = sig ?? await signatureFor(st);
  final d = _doc();
  d.addPage(_page(() => [
        _kop(),
        _title('LAPORAN BULANAN KLINIK', nomor: 'Nomor: LBK/KDC/${parts[0]}/${parts[1]}'),
        _kv([
          ['Perihal', 'Laporan kunjungan dan pendapatan bulan $bl'],
          ['Lampiran', '-'],
          ['Kepada', 'Pemilik / Penanggung Jawab Klinik']
        ]),
        pw.SizedBox(height: 8),
        pw.Text('Dengan hormat,', style: const pw.TextStyle(fontSize: 10)),
        pw.SizedBox(height: 4),
        pw.Text('Bersama ini kami sampaikan laporan kunjungan dan pendapatan Kilaw Dental Clinic untuk bulan $bl sebagai berikut:', style: const pw.TextStyle(fontSize: 10)),
        pw.SizedBox(height: 8),
        _tbl(['No', 'Uraian', 'Keterangan'], [for (var i = 0; i < ur.length; i++) ['${i + 1}', ur[i][0], ur[i][1]]], widths: [1, 5, 5]),
        pw.SizedBox(height: 12),
        pw.Text('Rincian per paraf:', style: const pw.TextStyle(fontSize: 10)),
        pw.SizedBox(height: 4),
        _tbl(['No', 'Paraf', 'Kunjungan', 'Pendapatan'], [
          for (var i = 0; i < pr.length; i++) ['${i + 1}', pr.keys.elementAt(i), '${pr.values.elementAt(i)[0].round()}', rp(pr.values.elementAt(i)[1])]
        ], widths: [1, 4, 3, 4]),
        pw.SizedBox(height: 14),
        pw.Text('Demikian laporan ini kami sampaikan. Atas perhatian Bapak/Ibu, kami ucapkan terima kasih.', style: const pw.TextStyle(fontSize: 10)),
        pw.SizedBox(height: 10),
        _ttd('Hormat kami,', st.jaga != null ? s(st.jaga!['nama']) : 'Penanggung jawab', signature),
      ]));
  return d.save();
}

// ============================ Status & stok ============================
Future<Uint8List> statusPdf(AppStore st, {Uint8List? sig}) async {
  final now = DateTime.now();
  final open = st.data['gigi']!.where((g) => !gDone(g)).toList();
  final sk = stokRows(st.data['stok']!, st.data['mutasi']!).where((r) => r.st.tone > 0).toList();
  final wait = st.data['prospek']!.where(prWait).toList();
  final signature = sig ?? await signatureFor(st);
  final d = _doc();
  d.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(40, 34, 40, 34),
    build: (c) => [
      _kop(),
      _title('LAPORAN STATUS & PERINGATAN STOK KLINIK', nomor: 'Nomor: MUT/KDC/${now.year}/${pad2(now.month)}'),
      _kv([
        ['Perihal', 'Status pekerjaan gigi tiruan, prospek, dan peringatan stok'],
        ['Tanggal', tglID()]
      ]),
      pw.SizedBox(height: 8),
      pw.Text('Dengan hormat,', style: const pw.TextStyle(fontSize: 10)),
      pw.Text('Berikut kami laporkan kondisi klinik per tanggal ${tglID()}:', style: const pw.TextStyle(fontSize: 10)),
      pw.SizedBox(height: 8),
      pw.Text('A. Gigi tiruan berjalan', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
      pw.SizedBox(height: 3),
      _tbl(['No', 'Pasien', 'Tahap', 'Keterangan'], [
        for (var i = 0; i < open.length; i++) ['${i + 1}', '${s(open[i]['nama'])}${s(open[i]['jenis']).isEmpty ? '' : '\n${open[i]['jenis']}'}', gStage(open[i]), gStuck(open[i]) ? 'Macet > $gtStuckDays hari' : '-']
      ], widths: [1, 5, 4, 4]),
      pw.SizedBox(height: 10),
      pw.Text('B. Prospek menunggu', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
      pw.SizedBox(height: 3),
      _tbl(['No', 'Nama', 'Rencana', 'Tanggal'], [
        for (var i = 0; i < wait.length; i++) ['${i + 1}', s(wait[i]['nama']), s(wait[i]['rencana']).isEmpty ? '-' : s(wait[i]['rencana']), s(wait[i]['tanggal']).isEmpty ? '-' : s(wait[i]['tanggal'])]
      ], widths: [1, 4, 6, 3]),
      pw.SizedBox(height: 10),
      pw.Text('C. Stok kritis / habis', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
      pw.SizedBox(height: 3),
      _tbl(['No', 'Item', 'Status', 'Sisa'], [
        for (var i = 0; i < sk.length; i++) ['${i + 1}', s(sk[i].item['nama']), sk[i].st.label.replaceAll(RegExp(r'[^\x00-\x7F]'), '').trim(), '${fmtQty(sk[i].akhir)} ${s(sk[i].item['satuan'])}']
      ], widths: [1, 5, 3, 3]),
      pw.SizedBox(height: 12),
      pw.Text('Mohon tindak lanjut untuk pekerjaan yang macet dan pengadaan stok yang kritis. Terima kasih.', style: const pw.TextStyle(fontSize: 10)),
      pw.SizedBox(height: 10),
      _ttd('Hormat kami,', st.jaga != null ? s(st.jaga!['nama']) : 'Penanggung jawab', signature),
    ],
  ));
  return d.save();
}

// ============================ Rekam medis / nota / odontogram ============================
pw.Widget _pInfo(Rec p) => _kv([
      ['No. File', s(p['noFile'])],
      ['Nama', s(p['nama'])],
      ['Alamat', s(p['alamat'])],
      ['No. Telp', ph(p['telp'])],
      ['Tanggal', tglID()]
    ]);

Future<Uint8List> rekamMedisPdf(AppStore st, Rec p) async {
  final hist = st.entry.where((e) => s(e['noFile']) == s(p['noFile'])).toList();
  final d = _doc();
  d.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 30, 36, 30),
    build: (c) => [
      _kop(),
      _title('REKAM MEDIS PASIEN'),
      _pInfo(p),
      pw.SizedBox(height: 10),
      _tbl(['Tanggal', 'Gigi', 'Diagnosa', 'Perawatan', 'Biaya', 'Paraf'], [
        for (final e in hist) [s(e['tanggal']), s(e['gigi']), s(e['diagnosa']), s(e['perawatan']), rp(n(e['biaya'])), combineParafMetode(e)]
      ], widths: [2, 1.4, 3, 4, 2, 2]),
    ],
  ));
  return d.save();
}

Future<Uint8List> notaPdf(AppStore st, Rec p, List<Rec> lines, {Uint8List? sig}) async {
  num tot = 0;
  for (final e in lines) {
    tot += n(e['biaya']);
  }
  final signature = sig ?? await signatureFor(st);
  final d = _doc();
  d.addPage(_page(() => [
        _kop(),
        _title('NOTA BIAYA PERAWATAN'),
        _pInfo(p),
        pw.SizedBox(height: 10),
        _tbl(['No', 'Tanggal', 'Perawatan', 'Biaya'], [
          for (var i = 0; i < lines.length; i++) ['${i + 1}', s(lines[i]['tanggal']), '${s(lines[i]['gigi'])} ${s(lines[i]['perawatan'])}'.trim(), rp(n(lines[i]['biaya']))]
        ], widths: [1, 2, 6, 3]),
        pw.SizedBox(height: 6),
        pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('Total: ${rp(tot)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12))),
        pw.SizedBox(height: 14),
        _ttd('Hormat kami,', st.jaga != null ? s(st.jaga!['nama']) : 'Penanggung jawab', signature),
      ]));
  return d.save();
}

Future<Uint8List> odontogramPdf(AppStore st, Rec p, Uint8List chartPng, {Uint8List? sig}) async {
  final m = st.odo;
  final o = m.calc();
  final signature = sig ?? await signatureFor(st);
  final d = _doc();
  d.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 30, 36, 30),
    build: (c) => [
      _kop(),
      _title('ODONTOGRAM & RENCANA PERAWATAN'),
      _pInfo(p),
      pw.SizedBox(height: 8),
      pw.Image(pw.MemoryImage(chartPng), fit: pw.BoxFit.contain),
      pw.SizedBox(height: 4),
      pw.Text('Keterangan: Tambal (hijau/kuning/biru) · EXO (merah, silang) · Dicabut (abu-abu) · GT (latar merah muda)', style: const pw.TextStyle(fontSize: 8.5)),
      pw.SizedBox(height: 8),
      pw.Text('Catatan', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
      for (final t in m.notes()) pw.Text('- $t', style: const pw.TextStyle(fontSize: 10)),
      if (o.lines.isNotEmpty) ...[
        pw.SizedBox(height: 8),
        _tbl(['Tindakan', 'Rincian', 'Biaya'], [for (final l in o.lines) [l[0], l[1], l[2]]], widths: [4, 6, 3]),
        pw.SizedBox(height: 4),
        pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('TOTAL: ${fr(o.tot)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
      ],
      pw.SizedBox(height: 14),
      _ttd('Dokter,', st.jaga != null ? s(st.jaga!['nama']) : 'Dokter', signature),
    ],
  ));
  return d.save();
}

// ============================ Informed consent ============================
Future<Uint8List> consentPdf(AppStore st, Rec r) async {
  Uint8List? pas;
  final ps = s(r['sig']);
  if (ps.isNotEmpty) {
    try {
      pas = base64Decode(ps.contains(',') ? ps.split(',').last : ps);
    } catch (_) {}
  }
  Rec? dok;
  final ds = s(r['dsig']);
  if (ds.startsWith('dok:')) dok = firstWhereOrNull(st.dokterVis, (x) => x['id'] == ds.substring(4));
  final dsig = ds.isEmpty ? null : await signatureFor(st, dokter: dok);
  final setuju = r['setuju'] == 'SETUJU';
  final pn = s(r['penanda']).isEmpty ? s(r['nama']) : s(r['penanda']);

  pw.Widget row(String a, String b) => pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Container(width: 150, padding: const pw.EdgeInsets.all(4), decoration: pw.BoxDecoration(border: pw.Border.all(width: .5)), child: pw.Text(a, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold))),
        pw.Expanded(child: pw.Container(padding: const pw.EdgeInsets.all(4), decoration: pw.BoxDecoration(border: pw.Border.all(width: .5)), child: pw.Text(b.isEmpty ? '-' : b, style: const pw.TextStyle(fontSize: 10)))),
      ]);

  pw.Widget sigBox(String head, Uint8List? img, String name) => pw.Expanded(
        child: pw.Column(children: [
          pw.Text(head, textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 70, child: img == null ? pw.SizedBox() : pw.Image(pw.MemoryImage(img), fit: pw.BoxFit.contain)),
          pw.Text(name.isEmpty ? '.......................' : name, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
          pw.Text('Tanda Tangan & Nama Jelas', style: const pw.TextStyle(fontSize: 8.5)),
        ]),
      );

  final d = _doc();
  d.addPage(_page(() => [
        _kop(),
        _title('PERSETUJUAN TINDAKAN MEDIS (INFORMED CONSENT)'),
        pw.Text('Yang bertanda tangan di bawah ini (selaku pasien sendiri atau perwakilan/wali sah pasien):', style: const pw.TextStyle(fontSize: 10)),
        pw.SizedBox(height: 6),
        row('Nama Pasien', s(r['nama'])),
        row('Nomor Rekam Medis (RM)', s(r['rm'])),
        row('Tanggal Lahir / Umur', [s(r['tglLahir']), s(r['umur'])].where((x) => x.isNotEmpty).join(' / ')),
        row('Alamat Rumah', s(r['alamat'])),
        row('Nomor HP / WhatsApp', ph(r['telp'])),
        row('Hubungan dengan Pasien', hubungan.map((h) => '${r['hub'] == h ? '[x]' : '[ ]'} $h').join('   ')),
        pw.SizedBox(height: 10),
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(border: pw.Border.all(width: .6)),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('PERNYATAAN PASIEN / WALI:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
            pw.SizedBox(height: 3),
            pw.Text(pernyataan, textAlign: pw.TextAlign.justify, style: const pw.TextStyle(fontSize: 10)),
          ]),
        ),
        pw.SizedBox(height: 8),
        pw.Text('Dengan ini menyatakan ${setuju ? 'SETUJU' : 'TIDAK SETUJU'} untuk dilakukannya tindakan medis berupa :', style: const pw.TextStyle(fontSize: 10)),
        pw.SizedBox(height: 3),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(6),
          decoration: pw.BoxDecoration(border: pw.Border.all(width: .5)),
          child: pw.Text(s(r['tindakan']), style: const pw.TextStyle(fontSize: 10)),
        ),
        pw.SizedBox(height: 14),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          sigBox('Dokter Pelaksana :\n ', dsig, s(r['dokter'])),
          sigBox('Pasuruan, ${tglID(s(r['tgl']).isEmpty ? null : s(r['tgl']))}\nYang membuat pernyataan,', pas, pn),
        ]),
        pw.SizedBox(height: 14),
        pw.Text('* Dokumen ini sah dan akan disimpan sebagai bagian dari berkas Rekam Medis pasien di Kilaw Dental Clinic Pasuruan.\n*Coret yang tidak perlu', style: const pw.TextStyle(fontSize: 8.5)),
      ]));
  return d.save();
}
