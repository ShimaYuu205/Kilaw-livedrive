import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../ui/common.dart';
import 'store.dart';
import 'sync.dart';
import 'util.dart';

/// Mengirim berkas ke folder Drive (laporan/export/excel) bila Sinkron aktif.
Future<bool> uploadToDrive(AppStore st, String folder, String name, Uint8List bytes, String mime) async {
  final sy = syncInstance;
  if (sy == null || !st.syncReady) return false;
  try {
    await sy.api('putfile', {'folder': folder, 'name': name, 'mime': mime, 'b64': base64Encode(bytes)});
    return true;
  } catch (e) {
    toast('Gagal kirim ke Drive: $e', 'err');
    return false;
  }
}

/// Simpan ke perangkat. Di desktop membuka dialog "Simpan sebagai"; di Android/iOS membuka pemilih lokasi.
Future<String?> saveToDevice(String name, Uint8List bytes) async {
  try {
    final path = await FilePicker.platform.saveFile(dialogTitle: 'Simpan berkas', fileName: name, bytes: bytes);
    if (path != null && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      final f = File(path);
      if (!await f.exists() || await f.length() == 0) await f.writeAsBytes(bytes);
    }
    return path;
  } catch (e) {
    toast('Gagal menyimpan: $e', 'err');
    return null;
  }
}

Future<void> shareBytes(String name, Uint8List bytes, String mime) async {
  final dir = Directory.systemTemp;
  final f = File('${dir.path}/$name');
  await f.writeAsBytes(bytes);
  await Share.shareXFiles([XFile(f.path, mimeType: mime)]);
}

/// Pilihan keluaran: Drive / simpan / bagikan.
Future<void> deliver(BuildContext c, AppStore st, String name, Uint8List bytes, String mime, {String folder = 'export'}) async {
  final choice = await showModalBottomSheet<String>(
    context: c,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(title: Text(name, style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text('${(bytes.length / 1024).round()} KB')),
        if (st.syncReady) ListTile(leading: const Icon(Icons.cloud_upload_outlined), title: const Text('Kirim ke Google Drive'), onTap: () => Navigator.pop(ctx, 'drive')),
        ListTile(leading: const Icon(Icons.save_alt), title: const Text('Simpan ke perangkat'), onTap: () => Navigator.pop(ctx, 'save')),
        ListTile(leading: const Icon(Icons.share), title: const Text('Bagikan…'), onTap: () => Navigator.pop(ctx, 'share')),
      ]),
    ),
  );
  if (choice == 'drive') {
    if (await uploadToDrive(st, folder, name, bytes, mime)) toast('Terkirim ke Drive/$folder');
  } else if (choice == 'save') {
    if (await saveToDevice(name, bytes) != null) toast('Tersimpan');
  } else if (choice == 'share') {
    await shareBytes(name, bytes, mime);
  }
}
