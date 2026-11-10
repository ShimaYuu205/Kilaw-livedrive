import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../ui/common.dart';
import 'io_util.dart';
import 'payments.dart';
import 'search.dart';
import 'store.dart';
import 'util.dart';

String _cellStr(Data? d) {
  final dynamic v = d?.value;
  if (v == null) return '';
  if (v is TextCellValue) {
    final dynamic t = v.value;
    return t is String ? t : (t.toPlainText() as String);
  }
  if (v is IntCellValue) return '${v.value}';
  if (v is DoubleCellValue) {
    final x = v.value;
    return x == x.roundToDouble() ? '${x.round()}' : '$x';
  }
  if (v is DateCellValue) {
    final dynamic dt = v.asDateTimeLocal();
    return dmyOf(dt as DateTime);
  }
  if (v is DateTimeCellValue) {
    return dmyOf(v.asDateTimeLocal());
  }
  return v.toString();
}

String _genderFromFill(Data? d) {
  try {
    final dynamic hex = d?.cellStyle?.backgroundColor.colorHex;
    final h = s(hex).replaceAll('#', '');
    if (h.length < 6 || h.toUpperCase() == 'NONE') return '';
    final v = h.substring(h.length - 6);
    final r = int.parse(v.substring(0, 2), radix: 16), b = int.parse(v.substring(4, 6), radix: 16);
    if (b > r + 20) return 'l';
    if (r > b + 20) return 'p';
  } catch (_) {}
  return '';
}

int _col(List<String> head, List<String> keys) {
  for (var i = 0; i < head.length; i++) {
    final h = head[i];
    if (keys.any((k) => h == k || h.contains(k))) return i;
  }
  return -1;
}

String _at(List<Data?> row, int i) => i >= 0 && i < row.length ? _cellStr(row[i]).trim() : '';

/// Mengimpor sheet pasien & entry dari berkas .xlsx. Mengembalikan ringkasan.
String importExcelBytes(AppStore st, Uint8List bytes) {
  final ex = Excel.decodeBytes(bytes);
  var pNew = 0, pUpd = 0, eNew = 0, eSkip = 0;
  for (final name in ex.tables.keys) {
    final rows = ex.tables[name]!.rows;
    if (rows.isEmpty) continue;
    var hi = 0;
    for (var i = 0; i < rows.length && i < 6; i++) {
      final t = rows[i].map(_cellStr).join(' ').toLowerCase();
      if (t.contains('nama')) {
        hi = i;
        break;
      }
    }
    final head = rows[hi].map((d) => _cellStr(d).toLowerCase().trim()).toList();
    final cNama = _col(head, ['nama']);
    final cRm = _col(head, ['no. rm', 'no rm', 'norm', 'no.rm', 'rm', 'no file', 'nofile']);
    if (cNama < 0) continue;
    final cTgl = _col(head, ['tanggal', 'tgl']);
    final cUmur = _col(head, ['umur', 'usia']);
    final cAlamat = _col(head, ['alamat']);
    final cTelp = _col(head, ['telp', 'telepon', 'hp', 'wa']);
    final cJk = _col(head, ['jk', 'jenis kelamin', 'gender']);
    final isEntry = cTgl >= 0 && _col(head, ['perawatan', 'tindakan', 'diagnosa']) >= 0;
    final cGigi = _col(head, ['gigi']), cDx = _col(head, ['diagnosa']), cRw = _col(head, ['perawatan', 'tindakan']);
    final cBiaya = _col(head, ['biaya', 'bayar']), cParaf = _col(head, ['paraf']), cDok = _col(head, ['dokter']);
    for (var i = hi + 1; i < rows.length; i++) {
      final r = rows[i];
      final nama = _at(r, cNama);
      if (nama.isEmpty) continue;
      final rm = normNoFile(_at(r, cRm));
      if (isEntry) {
        final pm = splitParafMetode(_at(r, cParaf));
        final bi = toK(_at(r, cBiaya));
        final fin = finalizePay(bi, pm);
        final e = <String, dynamic>{
          'noFile': rm, 'nama': nama, 'umur': normUmur(_at(r, cUmur)), 'alamat': _at(r, cAlamat),
          'tanggal': _at(r, cTgl), 'gigi': _at(r, cGigi), 'diagnosa': _at(r, cDx), 'perawatan': _at(r, cRw),
          'biaya': bi, 'metode': fin.metode, 'qr': fin.qr, 'bank': fin.bank, 'paraf': pm.paraf,
          if (cDok >= 0 && _at(r, cDok).isNotEmpty) 'dokter': _at(r, cDok),
        };
        final dup = st.entry.any((x) => s(x['noFile']) == rm && x['tanggal'] == e['tanggal'] && x['gigi'] == e['gigi'] && x['perawatan'] == e['perawatan'] && n(x['biaya']) == bi);
        if (dup) {
          eSkip++;
        } else {
          st.insertEntryByDate(e);
          eNew++;
        }
      } else if (rm.isNotEmpty) {
        var g = '';
        if (cJk >= 0) {
          final v = _at(r, cJk).toLowerCase();
          g = genderLookup[v] ?? (v.startsWith('l') ? 'l' : v.startsWith('p') ? 'p' : '');
        }
        if (g.isEmpty) g = _genderFromFill(r[cNama]);
        var p = st.findPasien(rm);
        final isNew = p == null;
        p ??= {'noFile': rm, 'addedAt': nowMs()};
        p['nama'] = nama;
        if (_at(r, cUmur).isNotEmpty) p['umur'] = normUmur(_at(r, cUmur));
        if (_at(r, cAlamat).isNotEmpty) p['alamat'] = _at(r, cAlamat);
        if (_at(r, cTelp).isNotEmpty) p['telp'] = _at(r, cTelp);
        if (g.isNotEmpty) p['gender'] = g;
        p['isIncomplete'] = s(p['gender']).isEmpty;
        st.upsert('pasien', p);
        isNew ? pNew++ : pUpd++;
      }
    }
  }
  st.notifyExternal();
  return 'Pasien baru $pNew, diperbarui $pUpd · Entry baru $eNew, duplikat dilewati $eSkip';
}

Future<void> importExcelFlow(BuildContext c, AppStore st) async {
  final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx'], withData: true);
  if (r == null || r.files.isEmpty || r.files.first.bytes == null) return;
  try {
    toast(importExcelBytes(st, r.files.first.bytes!));
  } catch (e) {
    toast('Gagal membaca Excel: $e', 'err');
  }
}

Uint8List buildWorkbook(AppStore st) {
  final ex = Excel.createExcel();
  final def = ex.getDefaultSheet();
  final sp = ex['Data Pasien'], se = ex['Entry'], sr = ex['Rekap'];
  if (def != null && def != 'Data Pasien') ex.delete(def);
  CellStyle head() => CellStyle(bold: true, backgroundColorHex: ExcelColor.fromHexString('#1D5A50'), fontColorHex: ExcelColor.white);
  void put(Sheet sh, List<dynamic> row, {bool bold = false, ExcelColor? fill}) {
    sh.appendRow(row.map<CellValue?>((v) {
      if (v == null) return null;
      if (v is int) return IntCellValue(v);
      if (v is num) return DoubleCellValue(v.toDouble());
      return TextCellValue(v.toString());
    }).toList());
    final ri = sh.maxRows - 1;
    if (bold) {
      for (var ci = 0; ci < row.length; ci++) {
        sh.cell(CellIndex.indexByColumnRow(columnIndex: ci, rowIndex: ri)).cellStyle = head();
      }
    }
    if (fill != null) {
      sh.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: ri)).cellStyle = CellStyle(backgroundColorHex: fill);
    }
  }

  put(sp, ['No. RM', 'Nama', 'Umur', 'JK', 'Alamat', 'Telp'], bold: true);
  final ps = st.pasien.toList()..sort(rmCompare);
  for (final p in ps) {
    put(sp, [p['noFile'] is String && int.tryParse(s(p['noFile'])) != null ? int.parse(s(p['noFile'])) : s(p['noFile']), s(p['nama']), s(p['umur']), s(p['gender']).toUpperCase(), s(p['alamat']), ph(p['telp'])],
        fill: p['gender'] == 'p' ? ExcelColor.fromHexString('#F9D5E5') : p['gender'] == 'l' ? ExcelColor.fromHexString('#D6E8F7') : null);
  }
  put(se, ['Tanggal', 'No. RM', 'Nama', 'Umur', 'Alamat', 'Gigi', 'Diagnosa', 'Perawatan', 'Biaya (ribuan)', 'Paraf', 'Dokter'], bold: true);
  for (final e in st.entry) {
    put(se, [s(e['tanggal']), int.tryParse(s(e['noFile'])) ?? s(e['noFile']), s(e['nama']), s(e['umur']), s(e['alamat']), s(e['gigi']), s(e['diagnosa']), s(e['perawatan']), n(e['biaya']).round(), combineParafMetode(e), s(e['dokter'])]);
  }
  final aoa = buildRekapAoa(st.entry);
  for (var i = 0; i < aoa.length; i++) {
    put(sr, aoa[i], bold: i == 0);
  }
  return Uint8List.fromList(ex.encode()!);
}

Future<void> exportExcelFlow(BuildContext c, AppStore st) async {
  try {
    final bytes = buildWorkbook(st);
    await deliver(c, st, 'Kilaw-Data-${todayIso()}.xlsx', bytes, 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', folder: 'excel');
  } catch (e) {
    toast('Gagal membuat Excel: $e', 'err');
  }
}
