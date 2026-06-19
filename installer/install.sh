#!/bin/bash
# MiniServer All-In-One Installer
# Author: MiniServer Team
# Description: Install landing page, file manager, squid-cache, adblock di Armbian TV Box

set -e

INSTALL_DIR="/opt/miniserver"
WWW_DIR="/var/www/html"
SDCARD_MOUNT="/mnt/sdcard"
LOG_FILE="/tmp/miniserver-install.log"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $1" | tee -a "$LOG_FILE"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"; }
log_err() { echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"; }

check_root() { if [[ $EUID -ne 0 ]]; then log_err "Jalankan dengan sudo"; exit 1; fi }

detect_sdcard() {
    log_info "Mendeteksi SDCard..."
    local root_dev=$(findmnt -n -o SOURCE / | sed 's/p[0-9]*$//' | sed 's/[0-9]*$//')
    for dev in /dev/mmcblk1 /dev/mmcblk2 /dev/sda /dev/sdb; do
        if [[ -b "$dev" && "$dev" != "$root_dev" ]]; then
            local size=$(cat /sys/block/$(basename $dev)/size 2>/dev/null || echo 0)
            if [[ "$size" -gt 0 ]]; then
                SDCARD_DEV="$dev"; break
            fi
        fi
    done
    if [[ -z "$SDCARD_DEV" ]]; then
        log_warn "SDCard tidak terdeteksi otomatis"
        lsblk -d -o NAME,SIZE,TYPE,MOUNTPOINT 2>/dev/null | grep -E "mmc|sd" || true
        read -p "Masukkan device SDCard (contoh: /dev/mmcblk1): " input_dev
        input_dev=$(echo "$input_dev" | xargs)
        [[ "$input_dev" != /dev/* ]] && input_dev="/dev/$input_dev"
        SDCARD_DEV="$input_dev"
    fi
    if [[ -n "$SDCARD_DEV" && ! -b "$SDCARD_DEV" ]]; then
        log_err "Device $SDCARD_DEV tidak ditemukan"; SDCARD_DEV=""
    fi
    log_ok "SDCard: ${SDCARD_DEV:-tidak ada}"
}

setup_sdcard() {
    [[ -z "$SDCARD_DEV" || ! -b "$SDCARD_DEV" ]] && { log_warn "SDCard tidak tersedia, skip"; return 1; }
    local part="${SDCARD_DEV}p1"
    [[ "$SDCARD_DEV" == /dev/sd* ]] && part="${SDCARD_DEV}1"
    if [[ ! -b "$part" ]]; then
        log_info "Membuat partisi..."
        echo -e "o\nn\np\n1\n\n\nw" | fdisk "$SDCARD_DEV" 2>&1 | tee -a "$LOG_FILE"
        sleep 2; mkfs.ext4 -F "$part" 2>&1 | tee -a "$LOG_FILE"
    fi
    mkdir -p "$SDCARD_MOUNT"
    mountpoint -q "$SDCARD_MOUNT" || mount "$part" "$SDCARD_MOUNT" 2>&1 | tee -a "$LOG_FILE"
    for d in www log cache home squid squid/cache squid/logs mysql redis downloads backup \
             "My Document" "My Music" "My Pictures" "My Video"; do
        mkdir -p "$SDCARD_MOUNT/$d"
    done
    for src in www log cache home; do
        local tgt="/var/$src"
        [[ -d "$tgt" && ! -L "$tgt" ]] && { cp -a "$tgt/"* "$SDCARD_MOUNT/$src/" 2>/dev/null || true; rm -rf "$tgt"; }
        [[ ! -L "$tgt" ]] && ln -sf "$SDCARD_MOUNT/$src" "$tgt"
    done
    local uuid=$(blkid -s UUID -o value "$part" 2>/dev/null)
    [[ -n "$uuid" && -z "$(grep "$uuid" /etc/fstab)" ]] && \
        echo "UUID=$uuid $SDCARD_MOUNT ext4 defaults,noatime,nodiratime 0 2" >> /etc/fstab
    log_ok "SDCard siap sebagai storage utama"
}

# ==================== INSTALASI ====================

detect_similar_apps() {
    local app="$1"; local found=""
    case "$app" in
        nginx) [[ -f /usr/sbin/apache2 ]] && found+="apache2 "; [[ -f /usr/bin/caddy ]] && found+="caddy ";;
        apache2) [[ -f /usr/sbin/nginx ]] && found+="nginx ";;
        squid) [[ -f /usr/sbin/tinyproxy ]] && found+="tinyproxy "; [[ -f /usr/sbin/haproxy ]] && found+="haproxy ";;
        adblock) [[ -f /etc/dnsmasq.d/adblock.conf ]] && found+="dnsmasq-adblock ";;
    esac; echo "$found"
}

check_port() {
    ss -tuln | grep -q ":$1 " && return 1; return 0
}

find_port() {
    local base=$1
    for ((i=0; i<50; i++)); do
        local p=$((base + i))
        check_port "$p" && { echo "$p"; return 0; }
    done; echo "0"; return 1
}

handle_port() {
    local app="$1" ports="$2"
    local IFS=','; read -ra plist <<< "$ports"
    for p in "${plist[@]}"; do
        p=$(echo "$p" | xargs)
        if ! check_port "$p"; then
            log_warn "Port $p ($app) sudah terpakai:"
            ss -tuln | grep ":$p " | head -2
            local alt=$(find_port "$p")
            if [[ "$alt" != "0" ]]; then
                echo -e "${YELLOW}Gunakan port alternatif ${alt}? [Y/n]:${NC} "
                read -r yn; [[ "$yn" =~ ^[Nn] ]] && { log_err "Skip $app"; return 1; }
                log_info "Menggunakan port $alt untuk $app"
                eval "${app}_port=$alt"
            else
                log_err "Tidak ada port tersedia untuk $app"; return 1
            fi
        fi
    done; return 0
}

handle_similar() {
    local app="$1" name="$2"
    local similar=$(detect_similar_apps "$app")
    if [[ -n "$similar" ]] || (command -v "$app" &>/dev/null) || [[ -f "/usr/sbin/$app" ]] || [[ -f "/usr/bin/$app" ]]; then
        log_warn "$name sudah terinstall!"
        echo "1) Update $name"
        echo "2) Hapus $name"
        echo "3) Hapus & Install ulang"
        echo "4) Skip"
        read -p "Pilihan [1-4]: " ch
        case $ch in
            1) return 2;;  # update
            2) return 3;;  # hapus
            3) return 4;;  # hapus & install ulang
            *) return 1;;  # skip
        esac
    fi
    return 0
}

install_nginx() {
    handle_similar "nginx" "Nginx"; local rc=$?
    [[ $rc == 1 ]] && return 0
    [[ $rc == 3 ]] && { apt-get remove --purge -y nginx nginx-full nginx-light nginx-core 2>&1 | tee -a "$LOG_FILE"; return 0; }
    if [[ $rc == 4 ]]; then
        apt-get remove --purge -y nginx nginx-full nginx-light nginx-core 2>&1 | tee -a "$LOG_FILE"
    fi
    handle_port "nginx" "80,443" || return 0
    if [[ $rc == 2 ]]; then
        apt-get install --only-upgrade -y nginx-full nginx-light nginx-core 2>&1 | tee -a "$LOG_FILE" || apt-get install --only-upgrade -y nginx 2>&1 | tee -a "$LOG_FILE"
        log_ok "Nginx diupdate"; return 0
    fi
    log_info "Mencoba install Nginx..."
    for pkg in nginx-full nginx-light nginx-core nginx; do
        apt-get install -y "$pkg" 2>&1 | tee -a "$LOG_FILE" && { NGX_OK=1; break; }
    done
    if [[ -z "$NGX_OK" ]]; then
        log_err "Gagal install Nginx. Coba: apt-get update && apt-get install nginx"
        log_info "Menggunakan Apache sebagai alternatif..."
        install_apache
        return 0
    fi
    local nginx_conf="/etc/nginx/sites-available/default"
    [[ -d "/etc/nginx/sites-available" ]] || mkdir -p /etc/nginx/sites-available
    cat > "$nginx_conf" << 'EOF'
server {
    listen 80 default_server; listen [::]:80 default_server;
    root /var/www/html; index index.php index.html index.htm;
    server_name _;
    location / { try_files $uri $uri/ =404; }
    location ~ \.php$ { include snippets/fastcgi-php.conf; fastcgi_pass unix:/var/run/php/php8.2-fpm.sock; }
}
EOF
    if [[ -d "/etc/nginx/sites-enabled" && ! -L "/etc/nginx/sites-enabled/default" ]]; then
        ln -sf "$nginx_conf" /etc/nginx/sites-enabled/default 2>/dev/null || true
    fi
    systemctl enable nginx 2>/dev/null || true
    systemctl restart nginx 2>&1 | tee -a "$LOG_FILE" || true
    log_ok "Nginx terinstall"
}

install_apache() {
    handle_similar "apache2" "Apache"; local rc=$?
    [[ $rc == 1 ]] && return 0
    [[ $rc == 3 ]] && { apt-get remove --purge -y apache2 2>&1 | tee -a "$LOG_FILE"; return 0; }
    if [[ $rc == 4 ]]; then apt-get remove --purge -y apache2 2>&1 | tee -a "$LOG_FILE"; fi
    handle_port "apache2" "80,443" || return 0
    if [[ $rc == 2 ]]; then apt-get install --only-upgrade -y apache2 2>&1 | tee -a "$LOG_FILE"; log_ok "Apache diupdate"; return 0; fi
    apt-get install -y apache2 2>&1 | tee -a "$LOG_FILE"
    a2enmod rewrite 2>/dev/null || true
    systemctl enable apache2; systemctl restart apache2
    log_ok "Apache terinstall"
}

install_php() {
    log_info "Menginstall PHP..."
    local php_ver=""
    for ver in 8.3 8.2 8.1 8.0; do
        if apt-cache show "php${ver}-fpm" &>/dev/null 2>&1; then
            php_ver="$ver"; break
        fi
    done
    if [[ -z "$php_ver" ]]; then
        log_info "Menjalankan apt-get update..."
        apt-get update -qq 2>&1 | tee -a "$LOG_FILE"
        for ver in 8.3 8.2 8.1 8.0; do
            if apt-cache show "php${ver}-fpm" &>/dev/null 2>&1; then
                php_ver="$ver"; break
            fi
        done
    fi
    if [[ -z "$php_ver" ]]; then
        log_err "Tidak ada paket PHP-FPM tersedia. Install manual: apt-get install php-fpm"
        # Fallback: coba install php-fpm (default version)
        apt-get install -y php-fpm php-mysql php-mbstring php-xml php-curl php-gd php-zip 2>&1 | tee -a "$LOG_FILE" || true
        PHP_FPM_SVC=$(systemctl list-units --type=service --state=running 2>/dev/null | grep php | head -1 | awk '{print $1}')
        [[ -n "$PHP_FPM_SVC" ]] && log_ok "PHP ($PHP_FPM_SVC) terinstall" || log_warn "PHP mungkin gagal"
        return 0
    fi
    apt-get install -y "php${php_ver}" "php${php_ver}-fpm" "php${php_ver}-mysql" \
        "php${php_ver}-mbstring" "php${php_ver}-xml" "php${php_ver}-curl" \
        "php${php_ver}-gd" "php${php_ver}-zip" 2>&1 | tee -a "$LOG_FILE"
    systemctl enable "php${php_ver}-fpm" 2>/dev/null || true
    systemctl restart "php${php_ver}-fpm" 2>/dev/null || true
    # Update nginx config dengan versi PHP yang benar
    local sock="/var/run/php/php${php_ver}-fpm.sock"
    if [[ -f /etc/nginx/sites-available/default ]]; then
        sed -i "s|fastcgi_pass unix:/var/run/php/php[0-9.]*-fpm.sock|fastcgi_pass unix:${sock}|" /etc/nginx/sites-available/default 2>/dev/null || true
        systemctl restart nginx 2>/dev/null || true
    fi
    log_ok "PHP ${php_ver} terinstall"
}

deploy_landing() {
    log_info "Mendeploy landing page..."
    mkdir -p "$WWW_DIR"
    cp -r "$INSTALL_DIR/landing-page/"* "$WWW_DIR/"
    for d in "My Document" "My Music" "My Pictures" "My Video"; do
        mkdir -p "$WWW_DIR/$d"
    done
    [[ ! -L "$WWW_DIR/rootfs" ]] && ln -sf / "$WWW_DIR/rootfs" 2>/dev/null || true
    # Deploy TinyFileManager jika belum ada
    if [[ ! -f "$WWW_DIR/tiny.php" ]]; then
        log_info "Mendeploy TinyFileManager..."
        curl -fsSL https://raw.githubusercontent.com/tinyfilemanager/tinyfilemanager/master/tinyfilemanager.php -o "$WWW_DIR/tiny.php" 2>/dev/null || true
        if [[ -f "$WWW_DIR/tiny.php" ]]; then
            configure_tinyfilemanager "$WWW_DIR/tiny.php"
            chown www-data:www-data "$WWW_DIR/tiny.php" 2>/dev/null || true
        fi
    fi
    chown -R www-data:www-data "$WWW_DIR" 2>/dev/null || true
    chmod -R 755 "$WWW_DIR" 2>/dev/null || true
    log_ok "Landing page: http://ip-address/"
    [[ -f "$WWW_DIR/tiny.php" ]] && log_ok "File Manager:  http://ip-address/tiny.php"
}

setup_tinyfilemanager() {
    echo ""
    echo -e "${CYAN}>>> TinyFileManager${NC}"
    local fm_path="$WWW_DIR/tiny.php"
    if [[ -f "$fm_path" ]]; then
        log_warn "TinyFileManager sudah ada"
        echo "1) Update TinyFileManager"
        echo "2) Hapus TinyFileManager"
        echo "3) Hapus & Install ulang"
        echo "4) Skip"
        read -p "Pilihan [1-4]: " ch
        case $ch in
            1) rm -f "$fm_path"; curl -fsSL https://raw.githubusercontent.com/tinyfilemanager/tinyfilemanager/master/tinyfilemanager.php -o "$fm_path" 2>&1 | tee -a "$LOG_FILE"; configure_tinyfilemanager "$fm_path"; log_ok "TinyFileManager diupdate"; return 0;;
            2) rm -f "$fm_path"; log_ok "TinyFileManager dihapus"; return 0;;
            3) rm -f "$fm_path";;
            *) return 0;;
        esac
    fi
    log_info "Mendownload TinyFileManager..."
    curl -fsSL https://raw.githubusercontent.com/tinyfilemanager/tinyfilemanager/master/tinyfilemanager.php -o "$fm_path" 2>&1 | tee -a "$LOG_FILE"
    if [[ ! -f "$fm_path" ]]; then
        log_err "Gagal mendownload TinyFileManager"; return 1
    fi
    configure_tinyfilemanager "$fm_path"
    chown www-data:www-data "$fm_path" 2>/dev/null || true
    chmod 644 "$fm_path"
    log_ok "TinyFileManager: http://ip-address/tiny.php (user: admin, pass: admin)"
}

configure_tinyfilemanager() {
    local path="$1"
    # Default: admin/admin, root = $_SERVER['DOCUMENT_ROOT']
    # Enable auth + set root ke / biar bisa akses seluruh filesystem
    sed -i \
      -e 's/$use_auth = false;/$use_auth = true;/' \
      -e "s|\\\$root_path = .*|\\\$root_path = '/';|" \
      "$path" 2>/dev/null || true
}

install_landing() {
    echo ""
    echo -e "${CYAN}>>> Landing Page + File Manager${NC}"
    echo "Pilih web server:"
    echo "1) Nginx (ringan, cocok untuk RAM 1GB)"
    echo "2) Apache"
    read -p "Pilihan [1]: " ws
    if [[ "$ws" == "2" ]]; then
        install_apache
    else
        install_nginx
    fi
    install_php
    deploy_landing
}

install_squid() {
    echo ""
    echo -e "${CYAN}>>> Squid-Cache${NC}"
    handle_similar "squid" "Squid-Cache"; local rc=$?
    [[ $rc == 1 ]] && return 0
    [[ $rc == 3 ]] && { apt-get remove --purge -y squid 2>&1 | tee -a "$LOG_FILE"; log_ok "Squid dihapus"; return 0; }
    if [[ $rc == 4 ]]; then apt-get remove --purge -y squid 2>&1 | tee -a "$LOG_FILE"; fi
    handle_port "squid" "3128" || return 0
    if [[ $rc == 2 ]]; then
        apt-get install --only-upgrade -y squid 2>&1 | tee -a "$LOG_FILE"
        [[ -d "$SDCARD_MOUNT" ]] && cp "$INSTALL_DIR/config/squid/squid.conf" /etc/squid/squid.conf
        systemctl restart squid; log_ok "Squid diupdate"; return 0
    fi
    if [[ $rc == 4 ]]; then apt-get remove --purge -y squid 2>&1 | tee -a "$LOG_FILE"; fi
    apt-get install -y squid 2>&1 | tee -a "$LOG_FILE"
    cp "$INSTALL_DIR/config/squid/squid.conf" /etc/squid/squid.conf
    if [[ -d "$SDCARD_MOUNT" ]]; then
        mkdir -p "$SDCARD_MOUNT/squid/cache" "$SDCARD_MOUNT/squid/logs"
        chown -R proxy:proxy "$SDCARD_MOUNT/squid" 2>/dev/null || true
        sed -i "s|cache_dir ufs /var/spool/squid 5000|cache_dir ufs $SDCARD_MOUNT/squid/cache 5000|" /etc/squid/squid.conf
    fi
    squid -z 2>&1 | tee -a "$LOG_FILE" || true
    systemctl enable squid; systemctl restart squid 2>&1 | tee -a "$LOG_FILE"
    log_ok "Squid-Cache terinstall"
}

install_adblock() {
    echo ""
    echo -e "${CYAN}>>> Adblock (dnsmasq)${NC}"

    if [[ -f /usr/bin/pihole ]]; then
        log_warn "Pi-hole terdeteksi, harus dihapus dulu"
        echo "  1) Hapus Pi-hole & Install dnsmasq adblock"
        echo "  2) Skip"
        read -p "Pilihan [1-2]: " ch
        [[ "$ch" != "1" ]] && return 0
        pihole uninstall 2>&1 | tee -a "$LOG_FILE"
        log_ok "Pi-hole dihapus"
    fi

    if [[ -f /etc/dnsmasq.d/adblock.conf ]]; then
        log_warn "dnsmasq adblock sudah terinstall"
        echo "  1) Update filter"
        echo "  2) Hapus"
        echo "  3) Hapus & Install ulang"
        echo "  4) Skip"
        read -p "Pilihan [1-4]: " ch
        case $ch in
            1) install_dnsmasq_adblock; return 0;;
            2) rm -f /etc/dnsmasq.d/adblock.conf /etc/dnsmasq.d/adblock.hosts
               systemctl restart dnsmasq 2>/dev/null || true
               log_ok "dnsmasq adblock dihapus"
               return 0;;
            3) rm -f /etc/dnsmasq.d/adblock.conf /etc/dnsmasq.d/adblock.hosts;;
            *) return 0;;
        esac
    fi

    install_dnsmasq_adblock
}

install_dnsmasq_adblock() {
    apt-get install -y dnsmasq 2>&1 | tee -a "$LOG_FILE"
    mkdir -p /etc/dnsmasq.d
    cat > /etc/dnsmasq.d/adblock.conf << 'EOF'
addn-hosts=/etc/dnsmasq.d/adblock.hosts
cache-size=10000
neg-ttl=3600
local-service
EOF
    > /etc/dnsmasq.d/adblock.hosts
    for url in \
        "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts" \
        "https://someonewhocares.org/hosts/zero/hosts" \
        "https://raw.githubusercontent.com/rey_public/filter/main/indonesian-adlist.txt" \
        "https://raw.githubusercontent.com/rey_public/filter/main/indonesian-privacy.txt"; do
        curl -sL --connect-timeout 10 --max-time 20 "$url" 2>/dev/null | grep -E '^0\.0\.0\.0' >> /etc/dnsmasq.d/adblock.hosts || true
    done
    if [[ -f "$INSTALL_DIR/config/adblock/filter-indo.txt" ]]; then
        while IFS= read -r line; do
            [[ -z "$line" || "$line" == \#* ]] && continue
            echo "0.0.0.0 $line" >> /etc/dnsmasq.d/adblock.hosts
        done < "$INSTALL_DIR/config/adblock/filter-indo.txt"
    fi
    sort -u -o /etc/dnsmasq.d/adblock.hosts /etc/dnsmasq.d/adblock.hosts
    systemctl stop systemd-resolved 2>/dev/null || true
    systemctl disable systemd-resolved 2>/dev/null || true
    systemctl enable dnsmasq; systemctl restart dnsmasq 2>&1 | tee -a "$LOG_FILE" || true
    log_ok "dnsmasq adblock terinstall ($(wc -l < /etc/dnsmasq.d/adblock.hosts) domain)"
}

# ==================== UNINSTALL ====================

uninstall_landing() {
    echo ""
    echo -e "${YELLOW}>>> Hapus Landing Page${NC}"
    echo "Akan menghapus: Nginx, PHP, dan file landing page"
    read -p "Lanjutkan? (y/N): " yn
    [[ ! "$yn" =~ ^[Yy]$ ]] && return 0
    apt-get remove --purge -y nginx nginx-full nginx-light nginx-core 2>&1 | tee -a "$LOG_FILE" || true
    rm -rf "$WWW_DIR"/*
    log_ok "Landing page dan Nginx dihapus"
}

uninstall_tinyfm() {
    echo ""
    echo -e "${YELLOW}>>> Hapus TinyFileManager${NC}"
    if [[ ! -f "$WWW_DIR/tiny.php" ]]; then
        log_warn "TinyFileManager tidak ditemukan"; return 0
    fi
    read -p "Hapus TinyFileManager? (y/N): " yn
    [[ ! "$yn" =~ ^[Yy]$ ]] && return 0
    rm -f "$WWW_DIR/tiny.php"
    log_ok "TinyFileManager dihapus"
}

uninstall_squid() {
    echo ""
    echo -e "${YELLOW}>>> Hapus Squid-Cache${NC}"
    if ! command -v squid &>/dev/null && [[ ! -f /usr/sbin/squid ]]; then
        log_warn "Squid tidak terinstall"; return 0
    fi
    read -p "Hapus Squid-Cache? (y/N): " yn
    [[ ! "$yn" =~ ^[Yy]$ ]] && return 0
    systemctl stop squid 2>/dev/null || true
    apt-get remove --purge -y squid 2>&1 | tee -a "$LOG_FILE" || true
    log_ok "Squid-Cache dihapus"
}

uninstall_adblock() {
    echo ""
    echo -e "${YELLOW}>>> Hapus Adblock${NC}"
    if [[ -f /usr/bin/pihole ]]; then
        read -p "Hapus Pi-hole? (y/N): " yn
        [[ ! "$yn" =~ ^[Yy]$ ]] && return 0
        pihole uninstall 2>&1 | tee -a "$LOG_FILE"
        log_ok "Pi-hole dihapus"
    elif [[ -f /etc/dnsmasq.d/adblock.conf ]]; then
        read -p "Hapus dnsmasq adblock? (y/N): " yn
        [[ ! "$yn" =~ ^[Yy]$ ]] && return 0
        rm -f /etc/dnsmasq.d/adblock.conf /etc/dnsmasq.d/adblock.hosts
        systemctl restart dnsmasq 2>/dev/null || true
        log_ok "dnsmasq adblock dihapus"
    else
        log_warn "Tidak ada adblock terinstall"
    fi
}

uninstall_menu() {
    clear
    echo -e "${RED}"
    echo "  ╔══════════════════════════╗"
    echo "  ║     STB MINI SERVER      ║"
    echo "  ║     HAPUS APLIKASI       ║"
    echo "  ╚══════════════════════════╝"
    echo -e "${NC}"
    echo ""
    echo "1) Landing Page (Nginx + PHP)"
    echo "2) TinyFileManager"
    echo "3) Squid-Cache"
    echo "4) Adblock (dnsmasq)"
    echo ""
    echo "a) Hapus Semua"
    echo "b) Kembali ke Menu Utama"
    echo ""
    read -p "Pilihan: " ch
    case $ch in
        1) uninstall_landing; read -p "Enter untuk kembali..."; uninstall_menu;;
        2) uninstall_tinyfm; read -p "Enter untuk kembali..."; uninstall_menu;;
        3) uninstall_squid; read -p "Enter untuk kembali..."; uninstall_menu;;
        4) uninstall_adblock; read -p "Enter untuk kembali..."; uninstall_menu;;
        a|A) uninstall_landing; uninstall_tinyfm; uninstall_squid; uninstall_adblock; log_ok "Semua aplikasi dihapus";;
        b|B) menu;;
        *) uninstall_menu;;
    esac
}

# ==================== MENU ====================

menu() {
    clear
    echo -e "${CYAN}"
    echo "  ╔══════════════════════════╗"
    echo "  ║     STB MINI SERVER      ║"
    echo "  ║      For Armbian         ║"
    echo "  ╚══════════════════════════╝"
    echo -e "${NC}"
    echo ""
    echo "1) Landing Page (Nginx + PHP + Dashboard)"
    echo "2) TinyFileManager (File Manager - akses root & /var/www)"
    echo "3) Squid-Cache (Proxy + Cache)"
    echo "4) Adblock (dnsmasq + Filter Indonesia)"
    echo "5) Setup SDCard sebagai Storage Utama"
    echo ""
    echo "h) Hapus Aplikasi (uninstall)"
    echo "a) Install Semua (1+2+3+4+5)"
    echo "q) Keluar"
    echo ""
    read -p "Pilihan: " ch

    case $ch in
        1) detect_sdcard; setup_sdcard; install_landing;;
        2) setup_tinyfilemanager;;
        3) install_squid;;
        4) install_adblock;;
        5) detect_sdcard; setup_sdcard;;
        h|H) uninstall_menu;;
        a|A) detect_sdcard; setup_sdcard; install_landing; setup_tinyfilemanager; install_squid; install_adblock;;
        q) exit 0;;
        *) sleep 1; menu;;
    esac
}

# ==================== MAIN ====================
> "$LOG_FILE"
check_root

if [[ "$1" == "--install-all" ]]; then
    detect_sdcard; setup_sdcard; install_landing; setup_tinyfilemanager; install_squid; install_adblock
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  INSTALASI SELESAI!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo "Landing:     http://$(hostname -I | awk '{print $1}')"
    echo "File Mgr:   http://$(hostname -I | awk '{print $1}')/tiny.php (admin/admin)"
    echo "Squid:       port 3128"
elif [[ "$1" == "--uninstall" && -n "$2" ]]; then
    case "$2" in
        landing) uninstall_landing;;
        tiny|tinyfm) uninstall_tinyfm;;
        squid) uninstall_squid;;
        adblock) uninstall_adblock;;
        all) uninstall_landing; uninstall_tinyfm; uninstall_squid; uninstall_adblock; log_ok "Semua dihapus";;
        *) log_err "Aplikasi: landing, tiny, squid, adblock, all"; exit 1;;
    esac
elif [[ "$1" == "--install" && -n "$2" ]]; then
    case "$2" in
        landing) install_landing;;
        tiny|tinyfm) setup_tinyfilemanager;;
        squid) install_squid;;
        adblock) install_adblock;;
        sdcard) detect_sdcard; setup_sdcard;;
        *) log_err "Aplikasi: landing, tiny, squid, adblock, sdcard"; exit 1;;
    esac
else
    menu
fi
