# LiveDrive (Flutter) – Kilaw Dental Clinic

Rebuild LiveDrive/KilawRM dari Expo + JavaScript ke **Flutter (Dart)** untuk Android dan desktop.

## Yang berubah dari versi lama

| Masalah lama | Solusi di versi ini |
|---|---|
| Tidak bisa tambah/hapus file | Upload, buat folder, ganti nama, hapus (ke Sampah, bisa diurungkan) langsung dari app |
| Harus export/import untuk lihat perubahan | Drive Changes API di-poll tiap 5 detik, daftar file ter-update otomatis |
| Data corrupt saat >1 pengguna | Cek md5 sebelum menimpa (tolak jika sudah diubah orang lain) + salinan cadangan `nama.bak-TANGGAL-JAM` |
| Perlu Apps Script + token + API key | OAuth Google langsung (baca & tulis), tanpa Apps Script |

## Setup (sekali)

1. Google Cloud Console -> buat project -> aktifkan **Google Drive API**.
2. OAuth consent screen: tipe External, tambahkan email Anda dan staf sebagai **Test users**.
3. Buat 2 OAuth client:
   - **Desktop app** -> isi `desktopClientId` dan `desktopClientSecret` di `lib/auth_service.dart`.
   - **Android** -> package name `com.shimayuu.kilawrm` + SHA-1 keystore (`./gradlew signingReport`).
4. Buat project platform dan jalankan:
   ```
   flutter create --org com.shimayuu --project-name livedrive .
   flutter pub get
   flutter run -d windows      # atau linux / macos / android
   ```
5. Saat pertama dibuka: login Google, lalu tempel link folder Drive Kilaw.

Catatan: scope `drive` penuh dibutuhkan agar folder yang sudah ada bisa dikelola. Untuk pemakaian internal, mode "Testing" sudah cukup.

## Roadmap (agar data tidak corrupt lagi)

Akar masalah lama bukan hanya JavaScript, tetapi arsitektur: data di `localStorage`, sinkron dengan **menimpa seluruh file xlsx**. Flutter saja tidak menyelesaikan itu. Tahap berikutnya:

1. **Tahap 1 (paket ini):** file manager Drive real-time dengan CRUD penuh.
2. **Tahap 2:** database lokal SQLite (drift) untuk Pasien, Entry Harian, Stok, Mutasi. Satu baris = satu record, bukan satu file besar.
3. **Tahap 3:** sinkron per-record (id + updatedAt, last-write-wins per baris) dan xlsx hanya untuk impor/ekspor laporan.
4. **Tahap 4:** porting layar Rekam Medis dan Kilaw Note ke widget Flutter native (WebView di desktop kurang andal).

Data pasien adalah data kesehatan: token tersimpan di `flutter_secure_storage`, jangan commit client secret ke repo publik.
