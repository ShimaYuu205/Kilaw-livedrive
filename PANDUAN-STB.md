# Kilaw real-time di STB + domain (Cloudflare Tunnel)

Alurnya: **HP klinik ⇄ https://klinik.domainanda.com ⇄ (tunnel) ⇄ STB (server.js)**.
Server tanpa dependensi (hanya Node), menyajikan web app sekaligus menyimpan dan membagikan data.

## 1. Siapkan STB
Armbian/Debian, terhubung LAN/Wi-Fi, akses SSH.

```bash
sudo apt update && sudo apt install -y curl chrony
# Node.js 18+ (20 LTS dianjurkan). arm64:
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo bash - && sudo apt install -y nodejs
node -v
```
Penting: pada STB armv7 (32-bit) paket NodeSource Node 20 tidak tersedia. Pakai `setup_18.x`; server ini jalan di Node 18.

**Penyimpanan:** hindari menulis terus-menerus ke SD card/eMMC bawaan. Pasang flashdisk/SSD USB, mis. di `/mnt/data`, lalu pakai sebagai `DATA_DIR`.

## 2. Pasang server
```bash
mkdir -p ~/kilaw/public && cd ~/kilaw
# salin dari hasil ini:  server.js  ->  ~/kilaw/
#                        index.html app.js sync.js style.css  ->  ~/kilaw/public/
openssl rand -hex 24      # buat TOKEN, simpan baik-baik
```
Berkas `/etc/systemd/system/kilaw.service`:
```ini
[Unit]
Description=Kilaw Sync Server
After=network-online.target
Wants=network-online.target

[Service]
User=USERANDA
WorkingDirectory=/home/USERANDA/kilaw
Environment=KILAW_TOKEN=ISI_TOKEN_DI_SINI
Environment=DATA_DIR=/mnt/data/kilaw-data
Environment=PORT=8787
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
```
```bash
sudo mkdir -p /mnt/data/kilaw-data && sudo chown USERANDA /mnt/data/kilaw-data
sudo systemctl daemon-reload && sudo systemctl enable --now kilaw
curl -H "Authorization: Bearer TOKEN" http://127.0.0.1:8787/api/ping     # harus {"ok":true,...}
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

## 4. Pakai di HP
1. Buka `https://klinik.domainanda.com` (web app dimuat dari server, tidak perlu Drive).
2. Tab **Sinkron → Real-time**: isi alamat server dan token, lalu **Simpan & Hubungkan**.
3. **HP pertama (yang datanya paling lengkap) dulu.** Datanya diunggah ke server.
4. HP lain: kosong atau berisi data lama, sambungkan; data server ditarik. Untuk kunci yang sama, **versi server dipakai**. Data yang hanya ada di HP itu ikut diunggah.

Lencana di pojok atas: hijau = tersambung, kuning = sinkron, abu = offline (perubahan tetap tersimpan dan terkirim otomatis saat tersambung).

## 5. Cadangan dan pemulihan
- Server membuat cadangan harian di `DATA_DIR/backup/` (14 hari terakhir).
- Salin juga keluar STB, mis. cron + rclone ke Google Drive: `0 2 * * * rclone copy /mnt/data/kilaw-data/backup gdrive:kilaw-backup`.
- Pulihkan: hentikan service, ganti `log.ndjson` dengan salah satu `backup/log-TANGGAL.ndjson`, jalankan lagi.
- Export Excel dan sinkron Drive lama tetap ada sebagai cadangan tambahan.

## 6. Aturan main (perlu diketahui)
- Satu catatan diedit dua orang bersamaan: **yang tiba terakhir di server menang**.
- **No RM kembar** (dua HP membuat nomor sama sebelum sempat sinkron): versi server dipertahankan, versi HP yang kalah disimpan di Sinkron → *Unduh data bentrok*, lalu masukkan ulang dengan nomor baru.
- Nomor urut antrian (`no`) bisa kembar bila dua HP mengantri bersamaan. Urutan tampil tetap konsisten.
- **Jangan Import Excel besar** saat HP lain sedang bekerja: dari sudut pandang sistem itu adalah ratusan perubahan dan penghapusan sekaligus, dan semuanya akan menyebar ke semua HP.
- Tombol *Gabung ulang* mengulang penggabungan dari awal (server menang untuk kunci yang sama).
- Ganti token: ubah di service, `sudo systemctl restart kilaw`, lalu isi ulang di tiap HP.

## 7. Perbarui aplikasi
Ganti berkas di `~/kilaw/public/`, lalu muat ulang di HP. Nomor versi di `index.html` (`?v=...`) mencegah cache lama dipakai.
