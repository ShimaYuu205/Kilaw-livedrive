import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'auth_service.dart';
import 'browser_screen.dart';
import 'drive_service.dart';

void main() => runApp(const LiveDriveApp());

class LiveDriveApp extends StatelessWidget {
  const LiveDriveApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'LiveDrive',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: const Color(0xFF0F766E),
          useMaterial3: true,
        ),
        home: const Gate(),
      );
}

/// Alur: login Google -> pilih folder root (sekali, disimpan) -> file manager.
class Gate extends StatefulWidget {
  const Gate({super.key});

  @override
  State<Gate> createState() => _GateState();
}

class _GateState extends State<Gate> {
  static const _store = FlutterSecureStorage();
  static const _kRoot = 'root_folder_id';

  final _auth = AuthService();
  DriveService? _service;
  String? _rootId;
  bool _busy = true;
  String? _error;
  final _ctl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      _rootId = await _store.read(key: _kRoot);
      final client = await _auth.signIn();
      if (client != null) _service = DriveService(client);
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _busy = false);
  }

  /// Menerima ID folder ATAU link penuh folder Drive.
  String? _parseFolderId(String input) {
    final s = input.trim();
    final m = RegExp(r'/folders/([A-Za-z0-9_-]+)').firstMatch(s);
    if (m != null) return m.group(1);
    return RegExp(r'^[A-Za-z0-9_-]{10,}$').hasMatch(s) ? s : null;
  }

  Future<void> _saveRoot() async {
    final id = _parseFolderId(_ctl.text);
    if (id == null) {
      setState(() => _error = 'Link/ID folder tidak valid');
      return;
    }
    await _store.write(key: _kRoot, value: id);
    setState(() {
      _rootId = id;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_service == null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('LiveDrive', style: TextStyle(fontSize: 28)),
                const SizedBox(height: 16),
                if (_error != null)
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                FilledButton(
                  onPressed: () {
                    setState(() => _busy = true);
                    _start();
                  },
                  child: const Text('Masuk dengan Google'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_rootId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pilih folder Kilaw')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              TextField(
                controller: _ctl,
                decoration: InputDecoration(
                  labelText: 'Link atau ID folder Google Drive',
                  errorText: _error,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _saveRoot, child: const Text('Simpan')),
            ],
          ),
        ),
      );
    }
    return BrowserScreen(service: _service!, rootId: _rootId!);
  }
}
