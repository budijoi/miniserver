<!DOCTYPE html>
<html lang="id">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Tutorial - STB MINI SERVER</title>
    <link rel="stylesheet" href="css/modern.css">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">
    <style>
        .tutorial-container { max-width: 900px; margin: 0 auto; }
        .tutorial-card {
            background: var(--glass-bg);
            backdrop-filter: blur(16px);
            border: 1px solid var(--glass-border);
            border-radius: var(--radius);
            padding: 24px;
            margin-bottom: 20px;
            box-shadow: var(--shadow);
        }
        .tutorial-card h2 {
            font-size: 1.3em;
            margin-bottom: 16px;
            display: flex;
            align-items: center;
            gap: 10px;
        }
        .tutorial-card h2 i { color: var(--accent); }
        .tutorial-card h3 {
            font-size: 1em;
            color: var(--accent);
            margin: 16px 0 8px;
        }
        .tutorial-card p, .tutorial-card li { color: var(--text-secondary); line-height: 1.8; }
        .tutorial-card ul { padding-left: 20px; }
        .tutorial-card li { margin-bottom: 4px; }
        .tutorial-card code {
            display: block;
            background: #0f0f1a;
            color: #22c55e;
            padding: 12px 16px;
            border-radius: 8px;
            font-family: 'Consolas', monospace;
            font-size: 0.85em;
            margin: 8px 0;
            white-space: pre-wrap;
            word-break: break-all;
            border: 1px solid rgba(255,255,255,0.04);
        }
        .tutorial-card .note {
            background: rgba(99,102,241,0.1);
            border-left: 3px solid var(--accent);
            padding: 10px 14px;
            border-radius: 0 8px 8px 0;
            margin: 12px 0;
            font-size: 0.9em;
        }
        .tutorial-card .warning {
            background: rgba(245,158,11,0.1);
            border-left: 3px solid var(--warning);
            padding: 10px 14px;
            border-radius: 0 8px 8px 0;
            margin: 12px 0;
            font-size: 0.9em;
        }
        .step { display: flex; gap: 12px; margin-bottom: 12px; }
        .step-num {
            width: 28px; height: 28px;
            background: var(--accent); color: white;
            border-radius: 50%; display: flex;
            align-items: center; justify-content: center;
            font-size: 0.8em; font-weight: 700; flex-shrink: 0; margin-top: 2px;
        }
        .step-content { flex: 1; }
        .step-content p { margin: 0; }
        .back-link {
            display: inline-flex; align-items: center; gap: 8px;
            color: var(--text-secondary); text-decoration: none;
            margin-bottom: 20px; font-size: 0.9em;
        }
        .back-link:hover { color: var(--accent); }
        .toc { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 12px; margin-bottom: 24px; }
        .toc a {
            display: flex; align-items: center; gap: 10px;
            padding: 14px; background: var(--glass-bg);
            border: 1px solid var(--glass-border); border-radius: var(--radius);
            text-decoration: none; color: var(--text-primary); transition: all 0.2s;
        }
        .toc a:hover { border-color: var(--accent); transform: translateY(-2px); }
        .toc a i { font-size: 1.3em; color: var(--accent); }

        .tab-nav { display: flex; gap: 4px; margin-bottom: 20px; flex-wrap: wrap; }
        .tab-nav a {
            padding: 8px 18px; border: 1px solid var(--glass-border);
            border-radius: 8px; text-decoration: none; color: var(--text-secondary);
            font-size: 0.85em; transition: all 0.2s;
        }
        .tab-nav a:hover, .tab-nav a.active { border-color: var(--accent); color: var(--accent); background: rgba(99,102,241,0.08); }

        @media (max-width: 600px) {
            .tutorial-card { padding: 16px; }
            .toc { grid-template-columns: 1fr; }
        }
    </style>
</head>
<body class="theme-modern">
    <div class="container tutorial-container">
        <a href="./" class="back-link"><i class="fas fa-arrow-left"></i> Kembali ke Dashboard</a>

        <div class="tutorial-card" style="text-align:center;padding:32px;">
            <h1 style="font-size:1.8em;margin-bottom:8px;"><i class="fas fa-graduation-cap" style="color:var(--accent)"></i> Tutorial STB MINI SERVER</h1>
            <p style="color:var(--text-secondary);">Panduan instalasi, pengeditan file, dan manajemen aplikasi di TV Box Armbian</p>
            <div class="tab-nav" style="justify-content:center;margin-top:16px;">
                <a href="#instal"><i class="fas fa-download"></i> Instal</a>
                <a href="#edit"><i class="fas fa-edit"></i> Edit</a>
                <a href="#hapus"><i class="fas fa-trash"></i> Hapus</a>
                <a href="#filemanager"><i class="fas fa-folder-open"></i> File Manager</a>
                <a href="#sdcard"><i class="fas fa-sd-card"></i> SDCard</a>
            </div>
        </div>

        <div class="toc">
            <a href="#instal"><i class="fas fa-download"></i> Cara Instal</a>
            <a href="#edit"><i class="fas fa-edit"></i> Cara Edit</a>
            <a href="#hapus"><i class="fas fa-trash"></i> Cara Hapus</a>
            <a href="#filemanager"><i class="fas fa-folder-open"></i> File Manager</a>
            <a href="#sdcard"><i class="fas fa-sd-card"></i> SDCard</a>
            <a href="#service"><i class="fas fa-cogs"></i> Service</a>
        </div>

        <!-- INSTAL -->
        <div class="tutorial-card" id="instal">
            <h2><i class="fas fa-download"></i> Cara Instal Aplikasi</h2>

            <h3>Install Semua (Sekali Jalan)</h3>
            <div class="step">
                <div class="step-num">1</div>
                <div class="step-content"><p>SSH ke TV Box, lalu jalankan:</p></div>
            </div>
            <code>cd /opt/miniserver<br>sudo ./installer/install.sh --install-all</code>

            <h3>Install Satu per Satu</h3>
            <div class="step">
                <div class="step-num">1</div>
                <div class="step-content"><p>Jalankan installer dan pilih menu:</p></div>
            </div>
            <code>cd /opt/miniserver<br>sudo ./installer/install.sh</code>

            <div class="step">
                <div class="step-num">2</div>
                <div class="step-content"><p>Pilih angka sesuai aplikasi yang diinginkan:</p></div>
            </div>
            <ul>
                <li><strong>1</strong> - Landing Page (Nginx + PHP + Dashboard)</li>
                <li><strong>2</strong> - TinyFileManager (File Manager akses root)</li>
                <li><strong>3</strong> - Squid-Cache (Proxy + Cache)</li>
                <li><strong>4</strong> - Adblock (Pi-hole + Filter Indonesia)</li>
                <li><strong>5</strong> - Setup SDCard sebagai storage utama</li>
                <li><strong>a</strong> - Install semua</li>
            </ul>

            <h3>Install via CLI (Tanpa Menu)</h3>
            <code>sudo ./installer/install.sh --install landing<br>sudo ./installer/install.sh --install tiny<br>sudo ./installer/install.sh --install squid<br>sudo ./installer/install.sh --install adblock<br>sudo ./installer/install.sh --install sdcard</code>

            <div class="note">
                <i class="fas fa-info-circle"></i> Installer otomatis mendeteksi aplikasi serupa dan port yang sudah terpakai.
            </div>
        </div>

        <!-- EDIT -->
        <div class="tutorial-card" id="edit">
            <h2><i class="fas fa-edit"></i> Cara Edit File</h2>

            <h3>Via TinyFileManager (Mudah)</h3>
            <div class="step">
                <div class="step-num">1</div>
                <div class="step-content"><p>Buka browser, akses <code>http://ip-address/tiny.php</code></p></div>
            </div>
            <div class="step">
                <div class="step-num">2</div>
                <div class="step-content"><p>Login: user <strong>admin</strong>, password <strong>admin</strong></p></div>
            </div>
            <div class="step">
                <div class="step-num">3</div>
                <div class="step-content"><p>Navigasi ke folder yang ingin diedit, klik file, klik <strong>Edit</strong></p></div>
            </div>
            <p>File yang bisa diedit: PHP, HTML, CSS, JS, TXT, JSON, XML, SH, PY, dll. Ada syntax highlighting dari CodeMirror.</p>
            <div class="note">
                <i class="fas fa-folder-open"></i> Landing page berada di <code>/var/www/html/</code>
            </div>

            <h3>Via SSH (Terminal)</h3>
            <code># Edit file landing page<br>sudo nano /var/www/html/index.php<br><br># Edit nginx config<br>sudo nano /etc/nginx/sites-available/default<br><br># Edit squid config<br>sudo nano /etc/squid/squid.conf</code>
            <p>Gunakan <code>nano</code> atau <code>vim</code> untuk edit file dari terminal.</p>
        </div>

        <!-- HAPUS -->
        <div class="tutorial-card" id="hapus">
            <h2><i class="fas fa-trash"></i> Cara Hapus Aplikasi</h2>

            <h3>Via Installer (Otomatis)</h3>
            <div class="step">
                <div class="step-num">1</div>
                <div class="step-content"><p>Jalankan installer:</p></div>
            </div>
            <code>cd /opt/miniserver && sudo ./installer/install.sh</code>
            <div class="step">
                <div class="step-num">2</div>
                <div class="step-content"><p>Pilih menu aplikasi yang mau dihapus</p></div>
            </div>
            <div class="step">
                <div class="step-num">3</div>
                <div class="step-content"><p>Pilih opsi <strong>2) Hapus</strong> atau <strong>3) Hapus & Install ulang</strong></p></div>
            </div>

            <div class="warning">
                <i class="fas fa-exclamation-triangle"></i> Data aplikasi (database, cache, log) tetap tersimpan di SDCard.
            </div>

            <h3>Via Terminal (Manual)</h3>
            <code># Hapus Nginx<br>sudo apt-get remove --purge -y nginx nginx-full<br><br># Hapus Squid<br>sudo apt-get remove --purge -y squid<br><br># Hapus Pi-hole<br>pihole uninstall<br><br># Hapus TinyFileManager<br>sudo rm /var/www/html/tiny.php</code>

            <h3>Hapus Landing Page</h3>
            <code>sudo rm -rf /var/www/html/*</code>
            <div class="warning">
                <i class="fas fa-exclamation-triangle"></i> Perintah di atas akan menghapus SEMUA file di landing page.
            </div>

            <h3>Hapus Seluruh STB MINI SERVER</h3>
            <code># Backup dulu jika perlu<br>cp -r /var/www/html ~/backup-html<br><br># Hapus semua<br>sudo rm -rf /var/www/html<br>sudo rm -rf /opt/miniserver</code>
        </div>

        <!-- FILE MANAGER -->
        <div class="tutorial-card" id="filemanager">
            <h2><i class="fas fa-folder-open"></i> TinyFileManager</h2>
            <p>File manager berbasis PHP (1 file) dengan akses penuh ke seluruh filesystem. Ringan karena jalan di PHP yang sudah terinstall, tanpa perlu service tambahan.</p>

            <h3>Akses</h3>
            <code>http://ip-address/tiny.php</code>
            <p>Login: <strong>admin</strong> / <strong>admin</strong></p>

            <h3>Fitur</h3>
            <ul>
                <li>Browse root <code>/</code> dan <code>/var/www/html/</code></li>
                <li>Upload & download file</li>
                <li>Edit file dengan <strong>syntax highlighting</strong></li>
                <li>Buat folder & file baru</li>
                <li>Rename, copy, move, delete</li>
                <li>Preview: gambar, video, audio, PDF</li>
                <li>Search file</li>
                <li>Zip & extract archive</li>
            </ul>

            <h3>Mengganti Password</h3>
            <p>Edit file <code>/var/www/html/tiny.php</code>, cari bagian <code>$auth_users</code>, ganti password hash.</p>
            <p>Atau bisa di-generate di: <a href="https://tinyfilemanager.github.io/tinyfilemanager/password_generator.html" target="_blank">TinyFileManager Password Generator</a></p>

            <h3>Update</h3>
            <code>sudo ./installer/install.sh --install tiny</code>

        <!-- SDCARD -->
        <div class="tutorial-card" id="sdcard">
            <h2><i class="fas fa-sd-card"></i> SDCard</h2>

            <h3>Cek Status SDCard</h3>
            <code>sudo ./scripts/mount-sdcard.sh status</code>

            <h3>Mount Manual</h3>
            <code>sudo ./scripts/mount-sdcard.sh</code>

            <h3>Unmount</h3>
            <code>sudo ./scripts/mount-sdcard.sh unmount</code>

            <h3>Format SDCard</h3>
            <div class="warning">
                <i class="fas fa-exclamation-triangle"></i> Semua data di SDCard akan hilang!
            </div>
            <code>sudo ./scripts/mount-sdcard.sh format</code>

            <h3>Struktur Folder SDCard</h3>
            <code>/mnt/sdcard/<br>├── www/          → symlink ke /var/www<br>├── log/          → symlink ke /var/log<br>├── cache/        → symlink ke /var/cache<br>├── home/         → symlink ke /home<br>├── squid/<br>│   ├── cache/    → cache Squid<br>│   └── logs/<br>├── mysql/        → database MySQL<br>├── redis/<br>├── downloads/<br>├── backup/<br>├── My Document/<br>├── My Music/<br>├── My Pictures/<br>└── My Video/</code>
        </div>

        <!-- SERVICE -->
        <div class="tutorial-card" id="service">
            <h2><i class="fas fa-cogs"></i> Service Manager</h2>

            <h3>Via Dashboard (Mudah)</h3>
            <p>Buka landing page, scroll ke bawah ke bagian <strong>Service Manager</strong>. Klik tombol Start, Stop, atau Restart untuk setiap layanan.</p>

            <h3>Via Terminal</h3>
            <code># Lihat semua service<br>sudo ./scripts/services.sh list<br><br># Cek status<br>sudo ./scripts/services.sh status nginx<br><br># Start service<br>sudo ./scripts/services.sh start nginx<br><br># Stop service<br>sudo ./scripts/services.sh stop nginx<br><br># Restart service<br>sudo ./scripts/services.sh restart nginx<br><br># Lihat log<br>sudo ./scripts/services.sh logs nginx -n 30</code>

            <h3>Systemctl Langsung</h3>
            <code>sudo systemctl status nginx<br>sudo systemctl start squid<br>sudo systemctl restart php8.2-fpm<br>sudo systemctl enable nginx<br>sudo systemctl disable apache2</code>

            <h3>Monitoring Real-time</h3>
            <code>sudo ./scripts/monitor.sh -i 3</code>
            <p>Menampilkan CPU, RAM, Storage, Network, dan proses setiap 3 detik.</p>
        </div>

        <footer style="text-align:center;padding:24px;color:var(--text-secondary);font-size:0.85em;">
            <p>STB MINI SERVER &copy; 2025 | <a href="./" style="color:var(--accent);">Kembali ke Dashboard</a></p>
        </footer>
    </div>
</body>
</html>
