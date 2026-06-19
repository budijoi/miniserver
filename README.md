# MiniServer - Armbian TV Box Web Server

Proyek ini adalah solusi All-In-One untuk menjadikan TV Box (B860H, X96mini, dan sejenisnya) sebagai web server lengkap dengan Armbian yang terinstall di SDCard.

## Daftar Isi

- [Spesifikasi Perangkat](#spesifikasi-perangkat)
- [Fitur](#fitur)
- [Prasyarat](#prasyarat)
- [Instalasi Cepat](#instalasi-cepat)
- [Instalasi Manual](#instalasi-manual)
- [Struktur Direktori](#struktur-direktori)
- [Landing Page](#landing-page)
- [File Manager](#file-manager)
- [All-In-One Installer](#all-in-one-installer)
- [Squid-Cache](#squid-cache)
- [Adblock](#adblock)
- [Mount SDCard](#mount-sdcard)
- [Troubleshooting](#troubleshooting)
- [Lisensi](#lisensi)

## Spesifikasi Perangkat

| Perangkat | RAM | ROM | Storage |
|-----------|-----|-----|---------|
| B860H | 1 GB | 8 GB | SDCard (Utama) |
| X96mini | 2 GB | 16 GB | SDCard (Utama) |

> **Catatan:** Semua aplikasi dan data akan disimpan pada SDCard. ROM internal hanya digunakan untuk booting awal.

## Fitur

- **Landing Page** - Informasi sistem real-time (CPU, RAM, Storage, SWAP/ZRAM, RX/TX)
- **Multi Theme** - 4 tema pilihan (Minimalist, Modern, Techno, Cute)
- **File Manager** - Akses root folder dan `/var/www` untuk kemudahan editing
- **Service Manager** - Start, stop, restart, dan cek status layanan
- **All-In-One Installer** - Install aplikasi dengan deteksi otomatis dan manajemen port
- **Squid-Cache** - Proxy server dengan cache untuk mempercepat akses web
- **Adblock** - Blokir iklan dengan filter khusus Indonesia
- **SDCard Optimasi** - Mount dan optimasi SDCard sebagai storage utama

## Prasyarat

1. TV Box dengan Armbian sudah terinstall di SDCard
2. Koneksi internet untuk instalasi paket
3. PHP 8.x (akan diinstall otomatis oleh script)
4. Nginx atau Apache (akan diinstall otomatis oleh script)

## Instalasi Cepat

```bash
# Clone repositori
git clone https://github.com/budijoi/miniserver.git /opt/miniserver

# Masuk ke direktori
cd /opt/miniserver

# Jalankan installer
chmod +x installer/install.sh
./installer/install.sh
```

## Instalasi Manual

### 1. Mount SDCard sebagai Storage Utama

```bash
chmod +x scripts/mount-sdcard.sh
./scripts/mount-sdcard.sh
```

### 2. Install Landing Page

```bash
cp -r landing-page/* /var/www/html/
cp -r www/* /var/www/html/
```

### 3. Install File Manager

```bash
cp -r file-manager/* /var/www/html/
```

### 4. Setup Nginx/Apache

Konfigurasi web server untuk mengarah ke `/var/www/html/`.

### 5. Setup Squid-Cache

```bash
cp config/squid/squid.conf /etc/squid/squid.conf
systemctl restart squid
```

### 6. Setup Adblock

```bash
./scripts/setup-adblock.sh
```

## Struktur Direktori

```
miniserver/
├── installer/
│   └── install.sh              # All-In-One installer script
├── landing-page/
│   ├── index.php                # Halaman utama landing page
│   ├── api.php                  # API endpoint untuk data sistem
│   ├── css/
│   │   ├── minimalist.css       # Tema Minimalist
│   │   ├── modern.css           # Tema Modern
│   │   ├── techno.css           # Tema Techno
│   │   └── cute.css             # Tema Cute
│   ├── js/
│   │   └── main.js              # JavaScript landing page
│   └── themes/
│       └── settings.json        # Konfigurasi tema
├── file-manager/
│   └── index.php                # File manager
├── config/
│   ├── squid/
│   │   └── squid.conf           # Konfigurasi Squid-Cache
│   ├── adblock/
│   │   ├── adblock.conf         # Konfigurasi Adblock
│   │   └── filter-indo.txt      # Filter khusus Indonesia
│   └── system/
│       └── fstab-sdcard.conf    # Konfigurasi fstab untuk SDCard
├── scripts/
│   ├── mount-sdcard.sh          # Script mount SDCard
│   ├── services.sh              # Service manager
│   ├── monitor.sh               # System monitor
│   └── setup-adblock.sh         # Setup adblock
├── www/
│   ├── My Document/             # Folder default dokumen
│   ├── My Music/                # Folder default musik
│   ├── My Pictures/             # Folder default gambar
│   └── My Video/                # Folder default video
└── README.md
```

## Landing Page

Landing page menampilkan informasi sistem secara real-time:

- **CPU**: Temperatur dan Usage (%)
- **RAM**: Total, Used, Available
- **Storage**: Total, Used, Available (SDCard)
- **SWAP & ZRAM**: Usage dan status
- **Network**: RX/TX dalam format human-readable

### Tema

1. **Minimalist** - Bersih, putih, fokus pada informasi
2. **Modern** - Gelap, glassmorphism, gradient accent
3. **Techno** - Hijau matrix, tampilan terminal
4. **Cute** - Pastel, rounded, menyenangkan

Ganti tema melalui dropdown di pojok kanan atas landing page.

## File Manager

File manager memungkinkan akses ke:

- `/` (root filesystem)
- `/var/www/` (web root)
- `/opt/miniserver/www/` (folder default My Document, My Music, dll)

Fitur:
- Browse, create, edit, delete file dan folder
- Upload file
- Preview teks dan gambar
- Search file

## All-In-One Installer

Script installer otomatis (`installer/install.sh`) dengan fitur:

### Deteksi Aplikasi Serupa
Jika aplikasi serupa terdeteksi, script akan memberikan pilihan:
1. **Update** aplikasi ke versi terbaru
2. **Hapus** aplikasi
3. **Hapus dan Install** versi terbaru

### Manajemen Port
Script akan mengecek ketersediaan port sebelum instalasi:
- Jika port sudah terpakai, script akan mencari port alternatif
- Menampilkan daftar port yang digunakan
- Memberikan konfirmasi sebelum menggunakan port alternatif

### Aplikasi yang Didukung

| Aplikasi | Port Default | Deskripsi |
|----------|-------------|-----------|
| Nginx | 80, 443 | Web server |
| Apache | 80, 443 | Web server alternatif |
| PHP | 9000 | PHP-FPM |
| MySQL/MariaDB | 3306 | Database |
| PostgreSQL | 5432 | Database alternatif |
| Redis | 6379 | Cache |
| Node.js | 3000 | JavaScript runtime |
| Python Flask | 5000 | Python web framework |
| Squid-Cache | 3128 | Proxy cache |
| Adblock | - | DNS-based ad blocking |
| phpMyAdmin | 8080 | Database management |
| phpFileManager | 8081 | File manager web |
| Netdata | 19999 | Monitoring |
| Docker | 2375 | Container platform |
| Cockpit | 9090 | Server management |
| Portainer | 9443 | Container management |
| Jellyfin | 8096 | Media server |
| Transmission | 9091 | Torrent client |
| Syncthing | 8384 | File sync |

## Squid-Cache

Proxy server dengan fitur:

- **Memory cache** hingga 256 MB
- **Disk cache** hingga 5 GB (di SDCard)
- **Cache untuk HTTP dan HTTPS**
- **Access control** berdasarkan IP lokal
- **Optimasi bandwidth** dengan caching konten statis

### Konfigurasi

Edit `/etc/squid/squid.conf` untuk menyesuaikan:
- `cache_mem` - Ukuran memory cache
- `maximum_object_size` - Ukuran maksimal object cache
- `cache_dir` - Lokasi dan ukuran disk cache

## Adblock

DNS-based ad blocking dengan filter:

- Filter umum (EasyList, EasyPrivacy, Peter Lowe)
- **Filter khusus Indonesia**:
  - Indonesian ad servers
  - Situs iklan lokal
  - Tracking domains Indonesia

### Update Filter

```bash
./scripts/setup-adblock.sh --update
```

### Custom Filter

Tambahkan domain ke `config/adblock/filter-indo.txt` dengan format satu domain per baris.

## Mount SDCard

Script `scripts/mount-sdcard.sh` akan:

1. Mendeteksi device SDCard secara otomatis
2. Memformat (jika diperlukan) dengan ext4
3. Mount ke `/mnt/sdcard`
4. Membuat symlink folder penting ke SDCard:
   - `/var/www` → `/mnt/sdcard/www`
   - `/var/log` → `/mnt/sdcard/log`
   - `/var/cache` → `/mnt/sdcard/cache`
   - `/home` → `/mnt/sdcard/home`
5. Update `/etc/fstab` untuk auto-mount saat boot

## Troubleshooting

### Landing Page tidak muncul
```bash
# Cek status web server
systemctl status nginx
# atau
systemctl status apache2

# Cek error log
tail -f /var/log/nginx/error.log
```

### File Manager error
```bash
# Pastikan PHP sudah terinstall
php -v

# Cek permission folder
chmod -R 755 /var/www/html/
chown -R www-data:www-data /var/www/html/
```

### Port sudah terpakai
```bash
# Cek port yang digunakan
netstat -tulpn | grep :PORT
```

### SDCard tidak terdeteksi
```bash
# Lihat daftar device
lsblk
fdisk -l

# Cek dmesg
dmesg | grep mmc
dmesg | grep sd
```

## Lisensi

Proyek ini dilisensikan di bawah [MIT License](LICENSE).

---

**Dibuat dengan ❤️ untuk komunitas TV Box Android & Armbian Indonesia**
