# Rencana perbaikan: isi web app, cara penyimpanan, setting STB

## Keputusan penyimpanan
- **STB = sumber data harian.** Satu log kecil (`log.ndjson`), hanya catatan yang berubah yang dikirim/ditarik. Sudah begitu cara kerja `server.js`; sekarang daftar dokter (termasuk tanda tangan) dan antrian ikut di sana, bukan lagi `ttd.json` / `antrian.json` di Drive.
- **Apps Script = tukang simpan file saja.** Tidak lagi menyimpan JSON data. Hanya `ping`, `putfile`, `putfiles` (banyak file satu panggilan), `getfile`.
- **Folder Drive:** `storage/` (Excel pasien, entry, note + `backup-stb/`), `cetak/` (rekam medis, nota, odontogram, consent), `laporan/` (laporan bulanan, status klinik).
- **Beban:** Excel dan PDF dibuat di HP; STB tidak membuat file apa pun selain cadangan 1 file kecil per hari; Apps Script dipanggil 1x untuk 3 Excel, bukan 3x.

## Perubahan per file
| File | Perubahan |
|---|---|
| `app.js` | Pengingat GT per tahap di tab Antrian; antrian dan dokter ikut sinkron real-time (tanpa Drive); folder `export`→`cetak`, `excel`→`storage`; ekspor Excel satu panggilan (`putfiles`, dipecah per ±6 MB bila besar); End Shift mengirim Excel ke `storage/` (menggantikan kirim JSON); kode JSON/gzip ke Drive dihapus (±40 baris) |
| `index.html` | Tab Sinkron dipangkas: tombol *Kirim semua ke Drive* / *Muat dari Drive* dihapus; panel Apps Script hanya URL + token + Tes koneksi; teks diperbarui |
| `sync.js` | Koleksi baru `dokter` |
| `server.js` | Koleksi `dokter`; file statis dikompres sekali lalu disimpan di memori + ETag/304 (sebelumnya dikompres ulang tiap muat); cadangan harian ke Drive lewat Apps Script (opsional, tanpa rclone) |
| `Code.gs` | Baru: token dan 3 link folder di Script Properties; `aturKonfigurasi`, `cekKonfigurasi`, `buatTokenBaru`; ganti file aman (buat baru dulu, lama ke tong sampah); kunci anti-duplikat; nama file dibersihkan |
| `PANDUAN-STB.md` | Struktur file di STB, Drive, Script Properties; flashdisk + fstab; `/etc/kilaw.env`; systemd diperkuat; pasang Apps Script; pemulihan; pemecahan masalah |
| `style.css` | Tidak berubah |

## Pengingat GT di tab Antrian
Satu kartu GT, empat baris, hanya yang sudah waktunya ditindaklanjuti:
- **Belum bayar lab**: semua GT yang belum dibayar.
- **Belum kirim**: semua GT yang belum dikirim.
- **Belum datang**: sudah dikirim, belum diterima dari lab.
- **Belum insersi**: sudah diterima, belum dipasang.
Tiap baris menampilkan jumlah + 2 nama pertama (⚠ bila macet > 7 hari). Ketuk kartu untuk ke tab GT. Bila ingin literal (semua yang belum, tanpa syarat tahap sebelumnya), ubah dua baris `datang` dan `insersi` di `GT_REM` (app.js) menjadi `g.datang !== 'Sudah'` dan `g.insersi !== 'Sudah'`.

## Urutan pasang (sudah berjalan sebelumnya)
1. Apps Script: tempel `Code.gs`, isi `KONFIGURASI`, jalankan `aturKonfigurasi`, kosongkan lagi, *New deployment*, catat URL + token. Untuk memakai folder Excel lama, isi `FOLDER_STORAGE` dengan link folder itu.
2. STB: salin `server.js` dan `public/*`; buat `/etc/kilaw.env` (opsional isi `APPSCRIPT_URL` + `APPSCRIPT_TOKEN`); ubah service jadi `EnvironmentFile=` (lihat panduan); `sudo systemctl daemon-reload && sudo systemctl restart kilaw`.
3. HP: muat ulang; tab Sinkron → isi URL `/exec` + token Apps Script baru → Tes koneksi (3 folder harus "siap").
4. Daftar dokter yang sebelumnya di `ttd.json` ada di HP lama: buka tab Antrian → Pilih Dokter di HP yang daftarnya lengkap; daftar itu naik ke server dan menyebar ke HP lain.

## Yang tidak diubah / perlu diketahui
- `ttd.json` dan `antrian.json` lama di Drive tidak dibaca lagi. Isinya tidak hilang, hanya tidak dipakai.
- Aturan bentrok (server menang, No RM kembar) sama seperti sebelumnya.
- Kode `Code.gs` diuji dengan Drive tiruan (12 skenario); `server.js` diuji lokal (sinkron dua perangkat, koleksi dokter, ETag/304, gzip, cadangan ke Apps Script tiruan). Belum diuji di Apps Script asli, STB asli, atau tampilan layar HP: coba dulu di satu HP sebelum dipakai klinik.
