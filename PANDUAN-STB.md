# Kilaw di STB: real-time lewat domain, export ke Drive lewat Apps Script

Pembagian tugas (supaya STB dan Apps Script sama-sama ringan):

| Yang | Disimpan / dikerjakan di | Kenapa |
|---|---|---|
| Data harian (pasien, entry, antrian, catatan, consent, dokter) | **STB**, satu log kecil, hanya catatan yang berubah yang dikirim | cepat, real-time, tetap jalan offline di HP |
| Export Excel (pasien, entry, note) | dibuat di **HP**, dikirim sekali jalan lewat Apps Script ke Drive `storage/` | STB tidak ikut bekerja, Apps Script cukup menyimpan file |
| Cetak (rekam medis, nota, odontogram, consent) dan laporan | dibuat di **HP**, masuk Drive `cetak/` dan `laporan/` | sama |
| Cadangan harian | **STB** mengirim `log-<hari>.ndjson.gz` ke Drive `storage/backup-stb/` | aman bila STB atau flashdisk rusak |

Alur: **HP klinik ⇄ https://klinik.domainanda.com ⇄ (tunnel) ⇄ STB (server.js)**, dan **HP / STB → Apps Script → Drive** untuk file.

## 0. Struktur file

Di STB:
```text
/home/USERANDA/kilaw/              kode aplikasi (bisa diganti kapan saja)
├── server.js
└── public/                        yang disajikan ke HP
    ├── index.html
    ├── app.js
    ├── sync.js
    └── style.css

/etc/kilaw.env                     pengaturan + token (chmod 600, hanya root)
/etc/systemd/system/kilaw.service  menjalankan server otomatis
/etc/cloudflared/config.yml        tunnel ke domain

/mnt/data/                         flashdisk/SSD USB (jangan SD card/eMMC bawaan)
└── kilaw-data/                    DATA_DIR: seluruh data klinik
    ├── log.ndjson                 data utama (keadaan terakhir tiap catatan, dipadatkan otomatis)
    └── backup/
        ├── log-2026-11-11.ndjson  cadangan harian lokal, 14 hari terakhir
        └── .drive-last            penanda cadangan Drive hari ini sudah terkirim
```

Di Google Drive (tiga folder, boleh di mana saja, masing-masing punya link sendiri):
```text
storage/                           hasil export + cadangan
├── Data Pasien.xlsx
├── Entry Harian.xlsx
├── Kilaw_note.xlsx
└── backup-stb/
    └── log-senin.ndjson.gz … log-minggu.ndjson.gz     7 file, menimpa minggu lalu
cetak/                             RekamMedis-*.pdf, Nota-*.pdf, Odontogram-*.png, Inform-Consent-*.pdf
laporan/                           Laporan-Bulanan.pdf, Laporan-Status-Clinic.pdf
```
Nama file tetap, jadi export atau cetak ulang **menggantikan** yang lama; yang lama masuk tong sampah Drive (bisa dipulihkan 30 hari).

Di Apps Script (Project Settings → Script Properties):

| Kunci | Isi |
|---|---|
| `TOKEN` | kata sandi untuk web app dan STB (otomatis dibuat oleh `aturKonfigurasi`) |
| `FOLDER_STORAGE` | link folder `storage` |
| `FOLDER_CETAK` | link folder `cetak` |
| `FOLDER_LAPORAN` | link folder `laporan` |

## 1. Siapkan STB
Armbian/Debian, terhubung LAN/Wi-Fi, akses SSH.

```bash
sudo apt update && sudo apt install -y curl chrony
sudo timedatectl set-timezone Asia/Jakarta      # cadangan harian dihitung dari jam STB
# Node.js 18+ (20 LTS dianjurkan). arm64:
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo bash - && sudo apt install -y nodejs
node -v
```
Pada STB armv7 (32-bit) NodeSource Node 20 tidak tersedia; pakai `setup_18.x`, server ini jalan di Node 18.

**Flashdisk/SSD untuk data** (hindari tulis terus-menerus ke SD card/eMMC):
```bash
lsblk -f                                         # cari flashdisk, mis. /dev/sda1
# HANYA bila flashdisk baru/kosong (menghapus isinya!):  sudo mkfs.ext4 -L kilaw /dev/sda1
sudo mkdir -p /mnt/data && sudo blkid /dev/sda1  # salin UUID
echo 'UUID=ISI-UUID-DI-SINI /mnt/data ext4 defaults,noatime,nofail 0 2' | sudo tee -a /etc/fstab
sudo mount -a && df -h /mnt/data
sudo mkdir -p /mnt/data/kilaw-data && sudo chown USERANDA /mnt/data/kilaw-data
```
`nofail` membuat STB tetap menyala walau flashdisk lepas (server tidak akan jalan sampai terpasang lagi, data tidak rusak).

Batasi log sistem agar tidak memenuhi penyimpanan: di `/etc/systemd/journald.conf` isi `SystemMaxUse=100M`, lalu `sudo systemctl restart systemd-journald`.

## 2. Pasang server
```bash
mkdir -p ~/kilaw/public && cd ~/kilaw
# salin:  server.js  ->  ~/kilaw/
#         index.html app.js sync.js style.css  ->  ~/kilaw/public/
openssl rand -hex 24      # buat TOKEN server, simpan baik-baik
```
Pengaturan (token tidak ditaruh di file service karena file itu bisa dibaca semua user):
```bash
sudo tee /etc/kilaw.env >/dev/null <<'EOF'
KILAW_TOKEN=ISI_TOKEN_SERVER
DATA_DIR=/mnt/data/kilaw-data
PORT=8787
KEEP_BACKUPS=14
# Opsional: cadangan harian ke Drive lewat Apps Script (lihat bagian 4). Hapus dua baris ini bila tidak dipakai.
APPSCRIPT_URL=https://script.google.com/macros/s/ISI/exec
APPSCRIPT_TOKEN=ISI_TOKEN_APPS_SCRIPT
EOF
sudo chmod 600 /etc/kilaw.env
```
`/etc/systemd/system/kilaw.service`:
```ini
[Unit]
Description=Kilaw Sync Server
After=network-online.target mnt-data.mount
Wants=network-online.target
RequiresMountsFor=/mnt/data

[Service]
User=USERANDA
WorkingDirectory=/home/USERANDA/kilaw
EnvironmentFile=/etc/kilaw.env
Environment=NODE_OPTIONS=--max-old-space-size=192
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=3
Nice=5
OOMScoreAdjust=-300
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
```
`OOMScoreAdjust` membuat server klinik yang terakhir dimatikan bila memori STB habis (berguna bila STB juga dipakai program lain); server ini sendiri hanya butuh puluhan MB.
```bash
sudo systemctl daemon-reload && sudo systemctl enable --now kilaw
curl -H "Authorization: Bearer TOKEN_SERVER" http://127.0.0.1:8787/api/ping     # harus {"ok":true,...}
curl -H "Authorization: Bearer TOKEN_SERVER" http://127.0.0.1:8787/api/stats    # jumlah catatan per koleksi
journalctl -u kilaw -f
```

## 3. Domain lewat Cloudflare Tunnel
Syarat: domain memakai DNS Cloudflare (gratis). Tidak perlu buka port router.
```bash
# arm64 (armv7: ganti dengan cloudflared-linux-armhf.deb)
curl -L -o cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64.deb
sudo dpkg -i cloudflared.deb
cloudflared tunnel login
cloudflared tunnel create kilaw
cloudflared tunnel route dns kilaw klinik.domainanda.com
```
`/etc/cloudflared/config.yml`:
```yaml
tunnel: kilaw
credentials-file: /home/USERANDA/.cloudflared/ID-TUNNEL.json
ingress:
  - hostname: klinik.domainanda.com
    service: http://127.0.0.1:8787
  - service: http_status:404
```
```bash
sudo cloudflared service install && sudo systemctl enable --now cloudflared
```
HTTPS otomatis dari Cloudflare. Sambungan real-time (SSE) lewat tunnel ini berfungsi; server mengirim detak tiap 20 detik agar tidak diputus.

## 4. Apps Script (Code.gs) untuk export, cetak, dan cadangan ke Drive
1. Di Drive buat tiga folder: `storage`, `cetak`, `laporan`. Salin link masing-masing (Bagikan → Salin link, atau dari address bar).
2. Buka script.google.com → Proyek baru → tempel isi `Code.gs`.
3. Di blok `KONFIGURASI` paling atas tempel tiga link folder. `TOKEN` boleh dikosongkan (dibuat otomatis).
4. Pilih fungsi **aturKonfigurasi** → Run → izinkan akses Drive. Token muncul di *Execution log*; salin.
5. **Kosongkan lagi** blok `KONFIGURASI` (nilainya sudah tersimpan di Script Properties; token tidak perlu tertinggal di kode).
6. Deploy → New deployment → Web app: *Execute as* **Me**, *Who has access* **Anyone**. Salin URL yang berakhiran `/exec`.
7. Cek kapan saja dengan fungsi **cekKonfigurasi** (menampilkan status token dan nama tiap folder).

Mengganti folder atau token nanti: ubah langsung di Script Properties, tanpa deploy ulang. Setelah ganti token, isi ulang di tiap HP (tab Sinkron) dan di `/etc/kilaw.env` (`APPSCRIPT_TOKEN`) lalu `sudo systemctl restart kilaw`.

Jika masih memakai Apps Script lama dengan folder Excel yang sudah berisi file, isi `FOLDER_STORAGE` dengan link folder Excel lama itu supaya file lama tetap terbaca.

## 5. Pakai di HP
1. Buka `https://klinik.domainanda.com` (web app dimuat dari server, tidak perlu Drive).
2. Tab **Sinkron → Real-time**: isi alamat server dan token server, lalu **Simpan & Hubungkan**.
3. **HP pertama (yang datanya paling lengkap) dulu.** Datanya diunggah ke server.
4. HP lain: kosong atau berisi data lama, sambungkan; data server ditarik. Untuk kunci yang sama, **versi server dipakai**. Data yang hanya ada di HP itu ikut diunggah.
5. Tab **Sinkron → Apps Script**: isi URL `/exec` dan token Apps Script → **Tes koneksi** (harus menampilkan tiga folder siap). Ini hanya perlu untuk export dan cetak ke Drive.

Lencana di pojok atas: hijau = tersambung, kuning = sinkron, abu = offline (perubahan tetap tersimpan dan terkirim otomatis saat tersambung).

Kapan file ke Drive:
- **End Shift** otomatis mengirim tiga Excel terbaru ke `storage/` (satu panggilan).
- Tombol **Ekspor semua / Pasien / Entry / Catatan** di tab Sinkron kapan saja.
- Tombol PDF/foto di dokumen cetak dan laporan langsung ke `cetak/` atau `laporan/`.
- Tanpa Apps Script, cetak jatuh ke LiveDrive atau unduhan biasa.

## 6. Cadangan dan pemulihan
- STB membuat cadangan harian di `DATA_DIR/backup/` (14 hari terakhir).
- Bila `APPSCRIPT_URL` dan `APPSCRIPT_TOKEN` diisi, STB juga mengirim `log-<hari>.ndjson.gz` ke Drive `storage/backup-stb/` sekali sehari setelah jam 02:00 (jika gagal, dicoba lagi tiap jam). Cek: `journalctl -u kilaw | grep Cadangan`.
- Pulihkan dari cadangan lokal: `sudo systemctl stop kilaw`, ganti `log.ndjson` dengan `backup/log-TANGGAL.ndjson`, `sudo systemctl start kilaw`.
- Pulihkan dari Drive: unduh `log-<hari>.ndjson.gz`, `gunzip log-senin.ndjson.gz`, ganti nama jadi `log.ndjson`, lalu seperti di atas.
- Pilihan terakhir bila log hilang semua: tab Sinkron → **Muat dari Excel di Drive** di satu HP, lalu sambungkan ke server.

## 7. Aturan main (perlu diketahui)
- Satu catatan diedit dua orang bersamaan: **yang tiba terakhir di server menang**.
- **No RM kembar** (dua HP membuat nomor sama sebelum sempat sinkron): versi server dipertahankan, versi HP yang kalah disimpan di Sinkron → *Unduh data bentrok*, lalu masukkan ulang dengan nomor baru.
- Nomor urut antrian (`no`) bisa kembar bila dua HP mengantri bersamaan. Urutan tampil tetap konsisten.
- **Jangan Impor Excel besar** saat HP lain sedang bekerja: dari sudut pandang sistem itu ratusan perubahan dan penghapusan sekaligus, dan semuanya menyebar ke semua HP.
- Tombol *Gabung ulang* mengulang penggabungan dari awal (server menang untuk kunci yang sama).
- Ganti token server: ubah `KILAW_TOKEN` di `/etc/kilaw.env`, `sudo systemctl restart kilaw`, lalu isi ulang di tiap HP.
- Export bukan sinkron: file Excel di Drive adalah salinan untuk dibaca/diolah, bukan sumber data harian.

## 8. Perbarui aplikasi
Ganti berkas di `~/kilaw/public/` (dan `server.js` bila berubah, lalu `sudo systemctl restart kilaw`), lalu muat ulang di HP. Nomor versi di `index.html` (`?v=...`) mencegah cache lama dipakai. Server menyimpan hasil kompres file statis di memori dan memakai ETag, jadi muat ulang tidak membebani STB.

## 9. Bila ada masalah
| Gejala | Periksa |
|---|---|
| Lencana abu terus | `systemctl status kilaw cloudflared`; `curl` ping dari STB; flashdisk terpasang (`df -h /mnt/data`) |
| "Token salah" (merah) | token server di HP sama dengan `KILAW_TOKEN` di `/etc/kilaw.env` |
| "Balasan bukan JSON" saat Tes koneksi | deploy Apps Script harus *Anyone*, URL berakhiran `/exec`; setelah ubah kode, buat *New deployment* |
| Tes koneksi: "Belum diatur: FOLDER_…" | isi Script Properties atau jalankan `aturKonfigurasi` |
| Server tidak mau start | `journalctl -u kilaw -n 50`; token minimal 12 karakter |
| Cadangan Drive gagal | `APPSCRIPT_URL` dan `APPSCRIPT_TOKEN` di `/etc/kilaw.env`; folder `storage` sudah diatur |
