# STB MINI SERVER - For Armbian

Proyek untuk menjadikan TV Box (B860H, X96mini) sebagai web server dengan Armbian di SDCard.

## Spesifikasi Perangkat

| Perangkat | RAM | ROM | Storage |
|-----------|-----|-----|---------|
| B860H | 1 GB | 8 GB | SDCard (Utama) |
| X96mini | 2 GB | 16 GB | SDCard (Utama) |

Semua aplikasi dan data disimpan di SDCard. ROM internal hanya untuk booting.

## Fitur

- **Landing Page** - Informasi sistem real-time (CPU Temp/Usage, RAM, Storage SDCard, SWAP/ZRAM, RX/TX)
- **Multi Theme** - 4 tema: Minimalist, Modern, Techno, Cute
- **File Manager** - Akses root `/` dan `/var/www`, bisa baca/tulis file
- **Service Manager** - Start, stop, restart, cek status layanan (nginx, apache, php, squid, pihole, ssh)
- **Squid-Cache** - Proxy server dengan cache (256MB memory, 5GB disk di SDCard)
- **Adblock** - DNS ad blocking + filter khusus Indonesia
- **SDCard** - Mount, symlink folder penting, auto-mount saat boot
- **All-In-One Installer** - Auto-detect aplikasi serupa, manajemen port otomatis

## Instalasi Cepat

```bash
git clone https://github.com/username/miniserver.git /opt/miniserver
cd /opt/miniserver
chmod +x installer/install.sh
./installer/install.sh
```

Pilih menu sesuai kebutuhan. Tersedia juga menu **h** untuk menghapus aplikasi.

## Menu Installer

```
╔══════════════════════════════════════╗
║   INSTALASI                         ║
╠══════════════════════════════════════╣
║ 1) Landing Page (Nginx + PHP + Dashboard)
║ 2) TinyFileManager (File Manager)
║ 3) Squid-Cache (Proxy + Cache)
║ 4) Adblock (Pi-hole + Filter Indonesia)
║ 5) Setup SDCard sebagai Storage Utama
║ a) Install Semua (1+2+3+4+5)
╠══════════════════════════════════════╣
║   HAPUS (tekan h)                   ║
╠══════════════════════════════════════╣
║ 1) Landing Page (Nginx + PHP)
║ 2) TinyFileManager
║ 3) Squid-Cache
║ 4) Adblock
║ a) Hapus Semua
╚══════════════════════════════════════╝
```

### CLI (Langsung dari Terminal)

```bash
# Install
sudo ./installer/install.sh --install landing
sudo ./installer/install.sh --install tiny
sudo ./installer/install.sh --install squid
sudo ./installer/install.sh --install adblock
sudo ./installer/install.sh --install-all        # Install semua

# Uninstall
sudo ./installer/install.sh --uninstall landing
sudo ./installer/install.sh --uninstall tiny
sudo ./installer/install.sh --uninstall squid
sudo ./installer/install.sh --uninstall adblock
sudo ./installer/install.sh --uninstall all      # Hapus semua
```

### Deteksi Aplikasi Serupa

Jika aplikasi serupa sudah terinstall, akan muncul pilihan:
- **Update** ke versi terbaru
- **Hapus** aplikasi
- **Hapus & Install ulang**
- **Skip**

### Manajemen Port

- Cek ketersediaan port sebelum instalasi
- Jika port terpakai, cari port alternatif otomatis
- Konfirmasi sebelum pakai port alternatif

## Struktur Direktori

```
miniserver/
├── installer/
│   └── install.sh              # All-In-One installer
├── landing-page/
│   ├── index.php                # Dashboard landing page
│   ├── api.php                  # API endpoint sistem & service
│   ├── css/
│   │   ├── minimalist.css       # Tema Minimalist
│   │   ├── modern.css           # Tema Modern
│   │   ├── techno.css           # Tema Techno
│   │   └── cute.css             # Tema Cute
│   ├── js/
│   │   └── main.js              # JavaScript dashboard
│   └── themes/
│       └── settings.json        # Konfigurasi tema
├── config/
│   ├── squid/
│   │   └── squid.conf           # Konfigurasi Squid-Cache
│   ├── adblock/
│   │   ├── adblock.conf         # Konfigurasi dnsmasq adblock
│   │   └── filter-indo.txt      # Filter khusus Indonesia
│   └── system/
│       └── fstab-sdcard.conf    # Contoh fstab untuk SDCard
├── scripts/
│   ├── mount-sdcard.sh          # Mount SDCard + symlink
│   ├── services.sh              # Manajemen layanan
│   ├── monitor.sh               # Monitoring sistem real-time
│   └── setup-adblock.sh         # Install/update adblock
├── www/
│   ├── My Document/
│   ├── My Music/
│   ├── My Pictures/
│   └── My Video/
└── README.md
```

## Landing Page

Menampilkan informasi real-time (refresh tiap 5 detik):
- **CPU** - Temperatur, Usage, Load Average
- **RAM** - Total, Used, Available dalam progress bar
- **Storage** - Internal & SDCard
- **SWAP/ZRAM** - Usage dan persentase
- **Network** - Total RX/TX per interface

### Tema

| Tema | Style |
|------|-------|
| Minimalist | Putih bersih, fokus informasi |
| Modern | Gelap, glassmorphism, gradient |
| Techno | Hijau matrix, tampilan terminal |
| Cute | Pastel, rounded, menyenangkan |

Ganti tema dari dropdown pojok kanan atas.

## TinyFileManager

File manager berbasis PHP (1 file) dengan akses penuh ke root filesystem dan `/var/www/`.

Akses: `http://ip-address/tiny.php`
- User: `admin`
- Password: `admin@123`

Fitur:
- Navigasi root `/` dan `/var/www/html/`
- Upload, download, rename, copy, move, delete
- Edit file dengan **syntax highlighting** (CodeMirror)
- Preview gambar, video, audio, PDF
- Buat folder & file baru
- Search file
- Zip/extract archive
- Multi-user (di file config)
- **Ringan** - jalan di PHP yg sudah terinstall, tanpa service/systemd tambahan

## Squid-Cache

Proxy server dengan cache untuk mempercepat akses web.

- Memory cache: 256 MB
- Disk cache: 5 GB (di SDCard)
- Port: 3128
- Access control untuk jaringan lokal

Konfigurasi: `/etc/squid/squid.conf`

## Adblock

DNS-based ad blocking menggunakan Pi-hole atau dnsmasq.

Filter:
- StevenBlack hosts
- SomeoneWhoCares
- **Filter Indonesia** (Indonesian ad servers + privacy)

Update filter: `sudo ./scripts/setup-adblock.sh update`

## Mount SDCard

```bash
sudo ./scripts/mount-sdcard.sh
```

Fungsi:
- Deteksi otomatis device SDCard
- Format ext4 jika perlu
- Mount ke `/mnt/sdcard`
- Symlink: `/var/www`, `/var/log`, `/var/cache`, `/home` ke SDCard
- Update `/etc/fstab` untuk auto-mount

## Troubleshooting

### Landing page error
```bash
systemctl status nginx   # atau apache2
journalctl -u nginx --no-pager -n 20
```

### File Manager error
```bash
php -v
chmod -R 755 /var/www/html/
chown -R www-data:www-data /var/www/html/
```

### SDCard tidak terdeteksi
```bash
lsblk
# Masukkan manual: /dev/mmcblk1
```

### Nginx gagal install
```bash
apt-get update
apt-get install nginx-full
```

## Lisensi

MIT License

---

**Dibuat untuk komunitas TV Box Android & Armbian Indonesia**
