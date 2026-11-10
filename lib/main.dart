import 'package:flutter/material.dart';

import 'app.dart';
import 'core/store.dart';
import 'core/sync.dart';

final AppStore store = AppStore();
late final SyncService sync;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await store.init();
  sync = SyncService(store)..start();
  runApp(KilawApp(store: store, sync: sync));
}
