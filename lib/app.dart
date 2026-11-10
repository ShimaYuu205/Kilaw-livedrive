import 'package:flutter/material.dart';

import 'core/store.dart';
import 'core/sync.dart';
import 'ui/common.dart';
import 'ui/beranda.dart';
import 'ui/antrian.dart';
import 'ui/input_page.dart';
import 'ui/storage_page.dart';
import 'ui/rekap_page.dart';
import 'ui/catatan_pages.dart';
import 'ui/laporan_page.dart';
import 'ui/sinkron_page.dart';

/// Navigasi global supaya halaman lain bisa berpindah tab (mis. kartu Pengingat).
final ValueNotifier<String> navTab = ValueNotifier<String>('antrian');
void goTab(String id) => navTab.value = id;

class _Tab {
  final String id, label, icon;
  const _Tab(this.id, this.label, this.icon);
}

const _groups = <(String, List<_Tab>)>[
  ('Beranda', [_Tab('antrian', 'Antrian', '🏠'), _Tab('datapasien', 'Data Pasien', '👥')]),
  ('Rekam Medis', [_Tab('input', 'Input', '✍️'), _Tab('storage', 'Storage', '🗄️'), _Tab('rekap', 'Rekap', '📈')]),
  ('Catatan Klinik', [
    _Tab('prospek', 'Prospek WA', '💬'),
    _Tab('gigitiruan', 'Gigi Tiruan', '🦷'),
    _Tab('stokobat', 'Stok Obat', '💊'),
    _Tab('mutasi', 'Riwayat Mutasi', '📦'),
  ]),
  ('Laporan & Pengaturan', [_Tab('laporan', 'Laporan Bulanan', '📄'), _Tab('sinkron', 'Sinkron', '☁️')]),
];

class KilawApp extends StatelessWidget {
  final AppStore store;
  final SyncService sync;
  const KilawApp({super.key, required this.store, required this.sync});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => MaterialApp(
        title: 'Kilaw Dental Clinic',
        debugShowCheckedModeBanner: false,
        scaffoldMessengerKey: messengerKey,
        theme: buildTheme(store.lightTheme),
        home: Shell(store: store, sync: sync),
      ),
    );
  }
}

class Shell extends StatelessWidget {
  final AppStore store;
  final SyncService sync;
  const Shell({super.key, required this.store, required this.sync});

  Widget _page(String id) {
    switch (id) {
      case 'datapasien':
        return DataPasienPage(store: store, sync: sync);
      case 'input':
        return InputPage(store: store);
      case 'storage':
        return StoragePage(store: store);
      case 'rekap':
        return RekapPage(store: store);
      case 'prospek':
        return ProspekPage(store: store);
      case 'gigitiruan':
        return GigiPage(store: store);
      case 'stokobat':
        return StokPage(store: store);
      case 'mutasi':
        return MutasiPage(store: store);
      case 'laporan':
        return LaporanPage(store: store, sync: sync);
      case 'sinkron':
        return SinkronPage(store: store, sync: sync);
      default:
        return BerandaPage(store: store, sync: sync);
    }
  }

  Widget _nav(BuildContext context, String cur, {bool drawer = false}) {
    return Container(
      color: pal.surface,
      child: ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(children: [
            Container(
              width: 30, height: 30, alignment: Alignment.center,
              decoration: BoxDecoration(color: pal.accent, borderRadius: BorderRadius.circular(8)),
              child: Text('+', style: TextStyle(color: pal.accentInk, fontWeight: FontWeight.w900, fontSize: 18)),
            ),
            const SizedBox(width: 10),
            const Expanded(child: Text('Kilaw Dental Clinic', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
          ]),
        ),
        for (final g in _groups) ...[
          Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4), child: Text(g.$1.toUpperCase(), style: TextStyle(color: pal.faint, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .6))),
          for (final t in g.$2)
            ListTile(
              dense: true,
              selected: cur == t.id,
              selectedColor: pal.accent,
              selectedTileColor: pal.accentDim.withOpacity(.4),
              leading: Text(t.icon, style: const TextStyle(fontSize: 18)),
              title: Text(t.label, style: const TextStyle(fontWeight: FontWeight.w700)),
              onTap: () {
                navTab.value = t.id;
                if (drawer) Navigator.pop(context);
              },
            ),
        ],
      ]),
    );
  }

  String _title(String id) {
    for (final g in _groups) {
      for (final t in g.$2) {
        if (t.id == id) return t.label;
      }
    }
    return 'Antrian';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: navTab,
      builder: (context, cur, _) {
        final wide = MediaQuery.of(context).size.width >= 900;
        final body = Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: wide ? 1100 : 900),
            child: Padding(padding: const EdgeInsets.all(14), child: _page(cur)),
          ),
        );
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 0,
            title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Kilaw Dental Clinic', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              Text(_title(cur), style: TextStyle(fontSize: 12, color: pal.accent, fontWeight: FontWeight.w700)),
            ]),
            actions: [
              ListenableBuilder(
                listenable: sync,
                builder: (_, __) => Tooltip(
                  message: sync.status,
                  child: InkWell(
                    onTap: () => store.syncReady ? sync.syncNow() : goTab('sinkron'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: sync.busy
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : Icon(!store.syncReady ? Icons.cloud_off : store.dirty.isNotEmpty ? Icons.cloud_upload_outlined : Icons.cloud_done_outlined,
                              color: !store.syncReady ? pal.faint : store.dirty.isNotEmpty ? pal.warn : pal.good),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Ganti tema',
                icon: Icon(store.lightTheme ? Icons.dark_mode_outlined : Icons.light_mode_outlined),
                onPressed: () => store.setLight(!store.lightTheme),
              ),
            ],
          ),
          drawer: wide ? null : Drawer(child: _nav(context, cur, drawer: true)),
          body: wide
              ? Row(children: [
                  SizedBox(width: 240, child: _nav(context, cur)),
                  VerticalDivider(width: 1, color: pal.border),
                  Expanded(child: body),
                ])
              : body,
        );
      },
    );
  }
}
