# Kilaw Dental Clinic — Flutter (Android · Tablet · Desktop)

Port Flutter dari web app `app.js / index.html / style.css`. Satu basis kode untuk Android, tablet, Windows, macOS, Linux.
Butuh **Flutter ≥ 3.27** (Dart ≥ 3.6).

## 1. Buat proyek & salin kode
```bash
flutter create --org id.kilaw --project-name kilaw_clinic --platforms=android,windows,linux,macos kilaw_clinic
# salin folder lib/, assets/, pubspec.yaml, analysis_options.yaml dari paket ini (timpa), lalu:
cd kilaw_clinic && flutter pub get
```

## 2. Izin & pengaturan platform
- **Android** (`android/app/src/main/AndroidManifest.xml`): tambahkan di dalam `<manifest>`
  `<uses-permission android:name="android.permission.INTERNET"/>`
  Di `android/app/build.gradle(.kts)` pastikan `minSdk = 23`.
- **macOS**: di `macos/Runner/DebugProfile.entitlements` dan `Release.entitlements` tambahkan
  `com.apple.security.network.client` = true dan `com.apple.security.files.user-selected.read-write` = true.
- Windows/Linux: tanpa konfigurasi tambahan (Linux: `sudo apt install libgtk-3-dev`).

## 3. Build
```bash
flutter run -d <perangkat>            # uji
flutter build apk --release           # Android (HP & tablet)  -> build/app/outputs/flutter-apk/
flutter build appbundle --release     # Play Store
flutter build windows --release       # build/windows/x64/runner/Release/
flutter build linux --release
flutter build macos --release
```

## 4. Backend real-time (Apps Script)
1. Buka script.google.com, buat proyek, tempel `apps_script/Code.gs`.
2. Jalankan `setup()` sekali, salin TOKEN dari log.
3. Deploy → Aplikasi web (Jalankan sebagai: Saya, Akses: Siapa saja) → salin URL `/exec`.
4. Di aplikasi: menu **Sinkron** → isi URL + token → Simpan → Tes koneksi.
5. Setelah mengubah Code.gs: Deploy → Kelola deployment → Edit → **Versi baru**.

### Cara kerja sinkron real-time
- Semua data disimpan lokal dulu (offline-first, tulis atomik + cadangan `.bak`).
- Tiap perubahan menandai dataset "kotor"; dikirim ±2 dtk kemudian (antrian ±0,7 dtk), hanya file yang berubah, dikompres gzip, format kolom ringkas.
- Polling ringan tiap ±12 dtk: satu panggilan `meta` (cepat, dari PropertiesService) → hanya file yang berubah diunduh.
- Penggabungan per rekaman (updatedAt terbaru menang) + tombstone penghapusan, sehingga dua perangkat bisa mengedit bersamaan tanpa saling menimpa.
- Gagal jaringan → antre dan coba ulang dengan backoff; kirim otomatis saat online/aplikasi dibuka kembali.
- Format file di Drive tetap kompatibel dengan web app lama (`data/*.json.gz`).

## 5. Catatan penting
- Kode ditulis tanpa SDK Flutter di lingkungan penyusun, jadi **belum dikompilasi**. Jalankan `flutter analyze`; perbaiki galat kecil bila ada (sebagian besar mungkin terkait versi paket `excel`).
- Alamat klinik/kop surat ada di `lib/core/docs.dart` (`klNama`, `klAlamat`).
- Edit bersamaan antara web app lama dan Flutter: rekaman tanpa `updatedAt` dianggap lebih lama, jadi gunakan Flutter di semua perangkat untuk hasil terbaik.
