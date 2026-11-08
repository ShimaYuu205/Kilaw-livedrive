import 'dart:async';
import 'dart:io';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

const kFolderMime = 'application/vnd.google-apps.folder';

class ConflictException implements Exception {
  ConflictException(this.message);
  final String message;
  @override
  String toString() => message;
}

class DriveService {
  DriveService(http.Client client) : _api = drive.DriveApi(client);
  final drive.DriveApi _api;

  static const _fields =
      'id,name,mimeType,size,modifiedTime,md5Checksum,parents';

  // ---------- BACA ----------
  Future<List<drive.File>> list(String folderId) async {
    final out = <drive.File>[];
    String? token;
    do {
      final res = await _api.files.list(
        q: "'$folderId' in parents and trashed = false",
        $fields: 'nextPageToken,files($_fields)',
        orderBy: 'folder,name',
        pageSize: 200,
        pageToken: token,
        supportsAllDrives: true,
        includeItemsFromAllDrives: true,
      );
      out.addAll(res.files ?? []);
      token = res.nextPageToken;
    } while (token != null);
    return out;
  }

  Future<File> download(String fileId, String savePath) async {
    final media = await _api.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
      supportsAllDrives: true,
    ) as drive.Media;
    final f = File(savePath);
    await f.parent.create(recursive: true);
    final sink = f.openWrite();
    await media.stream.pipe(sink);
    return f;
  }

  // ---------- TAMBAH ----------
  Future<drive.File> upload(String folderId, File file) {
    final meta = drive.File()
      ..name = p.basename(file.path)
      ..parents = [folderId];
    return _api.files.create(
      meta,
      uploadMedia: drive.Media(file.openRead(), file.lengthSync()),
      supportsAllDrives: true,
      $fields: _fields,
    );
  }

  Future<drive.File> createFolder(String parentId, String name) {
    final meta = drive.File()
      ..name = name
      ..mimeType = kFolderMime
      ..parents = [parentId];
    return _api.files.create(meta, supportsAllDrives: true, $fields: _fields);
  }

  // ---------- UBAH ----------
  Future<void> rename(String id, String newName) => _api.files
      .update(drive.File()..name = newName, id, supportsAllDrives: true);

  /// Timpa isi file dengan aman:
  /// 1) tolak jika file sudah diubah orang lain (md5 beda dari yang dilihat user)
  /// 2) buat salinan cadangan bernama tanggal-jam sebelum menimpa
  Future<drive.File> updateContent(
    drive.File current,
    File newContent, {
    bool backup = true,
  }) async {
    final id = current.id!;
    final latest = await _api.files
        .get(id, $fields: 'md5Checksum,name,parents', supportsAllDrives: true)
        as drive.File;
    if (current.md5Checksum != null &&
        latest.md5Checksum != current.md5Checksum) {
      throw ConflictException(
          '"${latest.name}" sudah diubah pengguna lain. Muat ulang dulu.');
    }
    if (backup) {
      final t = DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      final stamp =
          '${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}';
      await _api.files.copy(
        drive.File()..name = '${latest.name}.bak-$stamp',
        id,
        supportsAllDrives: true,
      );
    }
    return _api.files.update(
      drive.File(),
      id,
      uploadMedia: drive.Media(newContent.openRead(), newContent.lengthSync()),
      supportsAllDrives: true,
      $fields: _fields,
    );
  }

  // ---------- HAPUS ----------
  /// Pindah ke Sampah Drive (bisa dipulihkan 30 hari), bukan hapus permanen.
  Future<void> trash(String id) => _api.files
      .update(drive.File()..trashed = true, id, supportsAllDrives: true);

  Future<void> restore(String id) => _api.files
      .update(drive.File()..trashed = false, id, supportsAllDrives: true);

  // ---------- REAL-TIME ----------
  /// Polling Drive Changes API tiap beberapa detik. Hanya mengambil DELTA
  /// perubahan (murah), bukan memuat ulang semua file.
  /// Emit `true` setiap ada perubahan dari pengguna/perangkat lain.
  Stream<bool> changes({Duration every = const Duration(seconds: 5)}) async* {
    var token =
        (await _api.changes.getStartPageToken(supportsAllDrives: true))
            .startPageToken!;
    while (true) {
      await Future.delayed(every);
      try {
        var page = token;
        var changed = false;
        while (true) {
          final r = await _api.changes.list(
            page,
            $fields: 'nextPageToken,newStartPageToken,changes(fileId)',
            pageSize: 100,
            supportsAllDrives: true,
            includeItemsFromAllDrives: true,
          );
          if ((r.changes ?? const []).isNotEmpty) changed = true;
          if (r.nextPageToken != null) {
            page = r.nextPageToken!;
          } else {
            token = r.newStartPageToken ?? page;
            break;
          }
        }
        if (changed) yield true;
      } catch (_) {
        // jaringan putus: coba lagi di putaran berikutnya
      }
    }
  }
}
