import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:googleapis/drive/v3.dart' as drive;

import 'drive_service.dart';

class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key, required this.service, required this.rootId});
  final DriveService service;
  final String rootId;

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  final _stack = <({String id, String name})>[];
  List<drive.File> _files = [];
  bool _loading = true;
  bool _live = false;
  StreamSubscription<bool>? _sub;

  String get _cur => _stack.isEmpty ? widget.rootId : _stack.last.id;

  @override
  void initState() {
    super.initState();
    _reload();
    _sub = widget.service.changes().listen((_) {
      if (mounted) setState(() => _live = true);
      _reload(silent: true);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _reload({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final f = await widget.service.list(_cur);
      if (mounted) setState(() => _files = f);
    } catch (e) {
      _snack('Gagal memuat: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _upload() async {
    final res = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (res == null) return;
    for (final pf in res.files) {
      if (pf.path == null) continue;
      try {
        await widget.service.upload(_cur, File(pf.path!));
        _snack('Terunggah: ${pf.name}');
      } catch (e) {
        _snack('Gagal unggah ${pf.name}: $e');
      }
    }
    _reload(silent: true);
  }

  Future<void> _newFolder() async {
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Folder baru'),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(context, c.text.trim()),
              child: const Text('Buat')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await widget.service.createFolder(_cur, name);
    _reload(silent: true);
  }

  Future<void> _rename(drive.File f) async {
    final c = TextEditingController(text: f.name);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Ganti nama'),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(context, c.text.trim()),
              child: const Text('Simpan')),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == f.name) return;
    await widget.service.rename(f.id!, name);
    _reload(silent: true);
  }

  Future<void> _delete(drive.File f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus file?'),
        content: Text(
            '"${f.name}" akan dipindah ke Sampah Drive (bisa dipulihkan 30 hari).'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Hapus')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.service.trash(f.id!);
    _reload(silent: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('"${f.name}" dihapus'),
      action: SnackBarAction(
        label: 'URUNGKAN',
        onPressed: () async {
          await widget.service.restore(f.id!);
          _reload(silent: true);
        },
      ),
    ));
  }

  String _size(String? s) {
    final n = int.tryParse(s ?? '');
    if (n == null) return '';
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    return '${(n / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final title = _stack.isEmpty ? 'LiveDrive' : _stack.last.name;
    return PopScope(
      canPop: _stack.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          setState(() => _stack.removeLast());
          _reload();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: [
            Tooltip(
              message: _live ? 'Tersinkron real-time' : 'Menunggu perubahan',
              child: Icon(Icons.circle,
                  size: 12, color: _live ? Colors.green : Colors.grey),
            ),
            IconButton(
                icon: const Icon(Icons.refresh), onPressed: () => _reload()),
            IconButton(
                icon: const Icon(Icons.create_new_folder_outlined),
                onPressed: _newFolder),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _upload,
          icon: const Icon(Icons.upload_file),
          label: const Text('Tambah file'),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _reload,
                child: _files.isEmpty
                    ? ListView(children: const [
                        SizedBox(height: 120),
                        Center(child: Text('Folder kosong')),
                      ])
                    : ListView.separated(
                        itemCount: _files.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final f = _files[i];
                          final isDir = f.mimeType == kFolderMime;
                          return ListTile(
                            leading: Icon(isDir
                                ? Icons.folder
                                : Icons.insert_drive_file_outlined),
                            title: Text(f.name ?? '-'),
                            subtitle: Text([
                              if (!isDir) _size(f.size),
                              f.modifiedTime
                                  ?.toLocal()
                                  .toString()
                                  .substring(0, 16),
                            ].whereType<String>().join(' • ')),
                            onTap: isDir
                                ? () {
                                    setState(() => _stack
                                        .add((id: f.id!, name: f.name!)));
                                    _reload();
                                  }
                                : null,
                            trailing: PopupMenuButton<String>(
                              onSelected: (v) =>
                                  v == 'rename' ? _rename(f) : _delete(f),
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                    value: 'rename',
                                    child: Text('Ganti nama')),
                                PopupMenuItem(
                                    value: 'delete', child: Text('Hapus')),
                              ],
                            ),
                          );
                        },
                      ),
              ),
      ),
    );
  }
}
