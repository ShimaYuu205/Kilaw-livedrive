import 'package:flutter/material.dart';

import '../core/store.dart';
import '../core/sync.dart';
import '../core/util.dart';
import 'common.dart';

class SinkronPage extends StatefulWidget {
  final AppStore store;
  final SyncService sync;
  const SinkronPage({super.key, required this.store, required this.sync});
  @override
  State<SinkronPage> createState() => _SinkronState();
}

class _SinkronState extends State<SinkronPage> {
  late final url = TextEditingController(text: widget.store.url), token = TextEditingController(text: widget.store.token);
  String log = '';
  bool working = false;

  Future<void> _run(Future<String> Function() fn) async {
    setState(() { working = true; log = 'Memproses…'; });
    try {
      final r = await fn();
      if (mounted) setState(() => log = r);
    } catch (e) {
      if (mounted) setState(() => log = 'Gagal: $e');
      toast('$e', 'err');
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.store, sy = widget.sync;
    return ListenableBuilder(
      listenable: sy,
      builder: (context, _) => ListView(children: [
        Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const H3('Apps Script'),
          const Hint('Tempel URL Web app (berakhiran /exec) dan token dari setup() di Code.gs. Data tersimpan di perangkat dan otomatis disinkronkan.'),
          gap(6),
          Field('URL Web app', url, hint: 'https://script.google.com/macros/s/…/exec'),
          Field('Token', token),
          Wrap(spacing: 8, runSpacing: 8, children: [
            Btn('Simpan', () async { await st.saveConfig(url.text, token.text); toast('Pengaturan tersimpan'); sy.syncNow(); }, accent: true, small: true),
            Btn('Tes koneksi', working ? null : () => _run(() async { await st.saveConfig(url.text, token.text); return sy.ping(); }), small: true),
          ]),
        ])),
        Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const H3('Status real-time'),
          gap(6),
          StatGrid([
            StatCard('Status', sy.busy ? 'Menyinkron…' : !st.syncReady ? 'Belum diisi' : st.dirty.isEmpty ? 'Tersinkron' : 'Menunggu kirim', color: st.dirty.isEmpty ? pal.good : pal.warn),
            StatCard('Antrean kirim', '${st.dirty.length} dataset'),
            StatCard('Terakhir', sy.lastOk == null ? '-' : '${pad2(sy.lastOk!.hour)}:${pad2(sy.lastOk!.minute)}:${pad2(sy.lastOk!.second)}'),
          ]),
          gap(6),
          Hint(sy.status),
          Hint(sy.metaOk
              ? 'Perubahan dikirim ±2 detik setelah ditulis; perubahan dari perangkat lain ditarik otomatis tiap ±12 detik (hanya file yang berubah).'
              : 'Server belum mendukung real-time. Perbarui Code.gs ke versi 2 (aksi meta).', color: sy.metaOk ? null : pal.warn),
          Btn('Sinkron sekarang', working || !st.syncReady ? null : () => sy.syncNow(), small: true),
        ])),
        Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const H3('Kirim / muat manual'),
          gap(6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            Btn('⬆️ Kirim semua ke Drive', working ? null : () => _run(() => sy.uploadAll((m) => setState(() => log = m))), accent: true, small: true),
            Btn('⬇️ Gabungkan dari Drive', working ? null : () => _run(() => sy.downloadAll((m) => setState(() => log = m), replace: false)), small: true),
            Btn('⬇️ Timpa dengan Drive', working ? null : () async {
              if (await confirmDialog(context, 'Semua data di perangkat ini diganti dengan isi Drive. Lanjutkan?', ok: 'Timpa')) {
                await _run(() => sy.downloadAll((m) => setState(() => log = m), replace: true));
              }
            }, small: true, color: pal.danger),
          ]),
          if (log.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(log, style: TextStyle(color: pal.dim, fontSize: 12.5))),
        ])),
      ]),
    );
  }
}
