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
        adblock) [[ -f /usr/bin/pihole ]] && found+="pihole ";;
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
    log_info "Mendeploy landing page & file manager..."
    mkdir -p "$WWW_DIR" "$WWW_DIR/file-manager"
    cp -r "$INSTALL_DIR/landing-page/"* "$WWW_DIR/"
    cp -r "$INSTALL_DIR/file-manager/"* "$WWW_DIR/file-manager/"
    for d in "My Document" "My Music" "My Pictures" "My Video"; do
        mkdir -p "$WWW_DIR/$d"
    done
    [[ ! -L "$WWW_DIR/rootfs" ]] && ln -sf / "$WWW_DIR/rootfs" 2>/dev/null || true
    chown -R www-data:www-data "$WWW_DIR" 2>/dev/null || true
    chmod -R 755 "$WWW_DIR" 2>/dev/null || true
    log_ok "Landing page: http://ip-address/"
    log_ok "File manager: http://ip-address/file-manager/"
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
    echo -e "${CYAN}>>> Adblock${NC}"
    if [[ -f /usr/bin/pihole ]]; then
        log_warn "Pi-hole sudah terinstall"
        echo "1) Update filter"
        echo "2) Hapus Pi-hole"
        echo "3) Hapus & Install ulang"
        echo "4) Skip"
        read -p "Pilihan [1-4]: " ch
        case $ch in
            1) pihole updateGravity 2>&1 | tee -a "$LOG_FILE"; log_ok "Filter diupdate"; return 0;;
            2) pihole uninstall 2>&1 | tee -a "$LOG_FILE"; log_ok "Pi-hole dihapus"; return 0;;
            3) pihole uninstall 2>&1 | tee -a "$LOG_FILE"; curl -sSL https://install.pi-hole.net | bash 2>&1 | tee -a "$LOG_FILE";;
            *) return 0;;
        esac
    else
        log_info "Menginstall Pi-hole..."
        curl -sSL https://install.pi-hole.net | bash 2>&1 | tee -a "$LOG_FILE" || true
    fi
    if [[ -f /usr/bin/pihole ]]; then
        log_info "Menambahkan filter Indonesia..."
        pihole -a adlist add https://raw.githubusercontent.com/rey_public/filter/main/indonesian-adlist.txt 2>/dev/null || true
        pihole -a adlist add https://raw.githubusercontent.com/rey_public/filter/main/indonesian-privacy.txt 2>/dev/null || true
        if [[ -f "$INSTALL_DIR/config/adblock/filter-indo.txt" ]]; then
            while IFS= read -r line; do
                [[ -z "$line" || "$line" == \#* ]] && continue
                pihole -b "$line" 2>/dev/null || true
            done < "$INSTALL_DIR/config/adblock/filter-indo.txt"
        fi
        pihole updateGravity 2>&1 | tee -a "$LOG_FILE"
        log_ok "Pi-hole + filter Indonesia terinstall"
    else
        log_warn "Pi-hole gagal, fallback ke dnsmasq adblock..."
        install_dnsmasq_adblock
    fi
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

# ==================== MENU ====================

menu() {
    clear
    echo -e "${CYAN}"
    echo "  __  __ _       _  _____                _"
    echo " |  \/  (_)     (_)/ ____|              | |"
    echo " | \  / |_ _ __  _| (___   ___ _ __   __| |"
    echo " | |\/| | | '_ \| |\___ \ / _ \ '_ \ / _\` |"
    echo " | |  | | | | | | |____) |  __/ | | | (_| |"
    echo " |_|  |_|_|_| |_|_|_____/ \___|_| |_|\__,_|"
    echo -e "${NC}"
    echo -e "${YELLOW}Armbian TV Box All-In-One Installer${NC}"
    echo -e "${BLUE}Device: B860H (1GB/8GB) | X96mini (2GB/16GB)${NC}"
    echo ""
    echo "1) Landing Page + File Manager (Nginx + PHP + Dashboard)"
    echo "2) Squid-Cache (Proxy + Cache)"
    echo "3) Adblock (Pi-hole + Filter Indonesia)"
    echo "4) Setup SDCard sebagai Storage Utama"
    echo ""
    echo "a) Install Semua (1+2+3+4)"
    echo "q) Keluar"
    echo ""
    read -p "Pilihan: " ch

    case $ch in
        1) detect_sdcard; setup_sdcard; install_landing;;
        2) install_squid;;
        3) install_adblock;;
        4) detect_sdcard; setup_sdcard;;
        a|A) detect_sdcard; setup_sdcard; install_landing; install_squid; install_adblock;;
        q) exit 0;;
        *) sleep 1; menu;;
    esac
}

# ==================== MAIN ====================
> "$LOG_FILE"
check_root

if [[ "$1" == "--install-all" ]]; then
    detect_sdcard; setup_sdcard; install_landing; install_squid; install_adblock
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  INSTALASI SELESAI!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo "Landing: http://$(hostname -I | awk '{print $1}')"
    echo "File Mgr: http://$(hostname -I | awk '{print $1}')/file-manager/"
    echo "Squid: port 3128"
elif [[ "$1" == "--install" && -n "$2" ]]; then
    case "$2" in
        landing) install_landing;;
        squid) install_squid;;
        adblock|pihole) install_adblock;;
        sdcard) detect_sdcard; setup_sdcard;;
        *) log_err "Aplikasi: landing, squid, adblock, sdcard"; exit 1;;
    esac
else
    menu
fi
