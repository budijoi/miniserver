#!/bin/bash
# MiniServer All-In-One Installer
# Author: MiniServer Team
# Description: Auto-detect, install, and manage applications on Armbian TV Box

set -e

# ==================== CONFIGURATION ====================
INSTALL_DIR="/opt/miniserver"
WWW_DIR="/var/www/html"
SDCARD_MOUNT="/mnt/sdcard"
LOG_FILE="/tmp/miniserver-install.log"
GITHUB_REPO="https://github.com/username/miniserver"

# Warna output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ==================== FUNCTIONS ====================

log() {
    echo -e "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_info() {
    log "${BLUE}[INFO]${NC} $1"
}

log_success() {
    log "${GREEN}[OK]${NC} $1"
}

log_warn() {
    log "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    log "${RED}[ERROR]${NC} $1"
}

banner() {
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
    echo -e "============================================"
    echo ""
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Script harus dijalankan sebagai root (sudo)"
        exit 1
    fi
}

detect_device() {
    log_info "Mendeteksi perangkat..."
    
    if [[ -f /proc/device-tree/model ]]; then
        DEVICE_MODEL=$(cat /proc/device-tree/model)
    elif [[ -f /sys/firmware/devicetree/base/model ]]; then
        DEVICE_MODEL=$(cat /sys/firmware/devicetree/base/model)
    else
        DEVICE_MODEL="Unknown"
    fi
    
    # Deteksi RAM
    TOTAL_RAM=$(free -m | awk '/^Mem:/{print $2}')
    
    # Deteksi ROM (internal storage)
    if [[ -b /dev/mmcblk0 ]]; then
        INTERNAL_STORAGE=$(lsblk -b /dev/mmcblk0 | awk 'NR==2{printf "%.1fG", $4/1024/1024/1024}')
    elif [[ -b /dev/mmcblk1 ]]; then
        INTERNAL_STORAGE=$(lsblk -b /dev/mmcblk1 | awk 'NR==2{printf "%.1fG", $4/1024/1024/1024}')
    else
        INTERNAL_STORAGE="Unknown"
    fi
    
    log_info "Perangkat: ${DEVICE_MODEL}"
    log_info "RAM: ${TOTAL_RAM} MB"
    log_info "Storage Internal: ${INTERNAL_STORAGE}"
    
    # Simpan info
    echo "$DEVICE_MODEL" > /tmp/device_model
    echo "$TOTAL_RAM" > /tmp/device_ram
}

detect_sdcard() {
    log_info "Mendeteksi SDCard..."
    
    # Cari device SDCard (biasanya mmcblk1 atau sd*)
    SDCARD_DEV=""
    
    for dev in /dev/mmcblk1 /dev/mmcblk2 /dev/sda /dev/sdb; do
        if [[ -b "$dev" ]]; then
            # Cek apakah ini bukan eMMC internal
            if echo "$dev" | grep -q "mmcblk"; then
                DEV_TYPE=$(cat /sys/block/$(basename $dev)/device/type 2>/dev/null || echo "Unknown")
                if [[ "$DEV_TYPE" != "MMC" ]] || [[ "$dev" == "/dev/mmcblk1" ]]; then
                    SDCARD_DEV="$dev"
                    break
                fi
            else
                SDCARD_DEV="$dev"
                break
            fi
        fi
    done
    
    if [[ -z "$SDCARD_DEV" ]]; then
        log_warn "SDCard tidak terdeteksi secara otomatis"
        log_info "Device tersedia:"
        lsblk -d -o NAME,SIZE,TYPE,MOUNTPOINT | grep -E "mmc|sd"
        echo ""
        read -p "Masukkan device SDCard (contoh: /dev/mmcblk1): " SDCARD_DEV
    fi
    
    echo "$SDCARD_DEV" > /tmp/sdcard_dev
    log_success "SDCard terdeteksi: ${SDCARD_DEV}"
}

check_network() {
    log_info "Memeriksa koneksi internet..."
    if ping -c 2 8.8.8.8 &>/dev/null || ping -c 2 1.1.1.1 &>/dev/null; then
        log_success "Koneksi internet tersedia"
        return 0
    else
        log_warn "Koneksi internet terputus. Beberapa fitur mungkin tidak berfungsi."
        return 1
    fi
}

update_system() {
    log_info "Mengupdate package list..."
    apt-get update -qq 2>&1 | tee -a "$LOG_FILE" || true
    log_success "Package list diupdate"
}

# ==================== APPLICATION INSTALLATION ====================

# Daftar port default untuk setiap aplikasi
declare -A APP_PORTS
APP_PORTS["nginx"]="80,443"
APP_PORTS["apache2"]="80,443"
APP_PORTS["php"]="9000"
APP_PORTS["mysql"]="3306"
APP_PORTS["mariadb"]="3306"
APP_PORTS["postgresql"]="5432"
APP_PORTS["redis"]="6379"
APP_PORTS["nodejs"]="3000"
APP_PORTS["python-flask"]="5000"
APP_PORTS["squid"]="3128"
APP_PORTS["phpmyadmin"]="8080"
APP_PORTS["phpfilemanager"]="8081"
APP_PORTS["netdata"]="19999"
APP_PORTS["docker"]="2375"
APP_PORTS["cockpit"]="9090"
APP_PORTS["portainer"]="9443"
APP_PORTS["jellyfin"]="8096"
APP_PORTS["transmission"]="9091"
APP_PORTS["syncthing"]="8384"

# Deteksi aplikasi serupa
detect_similar_apps() {
    local app_name="$1"
    local similar_apps=()
    
    case "$app_name" in
        nginx)
            [[ -f /usr/sbin/apache2 ]] && similar_apps+=("apache2")
            [[ -f /usr/bin/caddy ]] && similar_apps+=("caddy")
            ;;
        apache2)
            [[ -f /usr/sbin/nginx ]] && similar_apps+=("nginx")
            [[ -f /usr/bin/caddy ]] && similar_apps+=("caddy")
            ;;
        mysql|mariadb)
            [[ -f /usr/bin/psql ]] && similar_apps+=("postgresql")
            [[ -f /usr/bin/sqlite3 ]] && similar_apps+=("sqlite3")
            ;;
        postgresql)
            [[ -f /usr/bin/mysql ]] && similar_apps+=("mysql")
            ;;
        squid)
            [[ -f /usr/sbin/tinyproxy ]] && similar_apps+=("tinyproxy")
            [[ -f /usr/sbin/haproxy ]] && similar_apps+=("haproxy")
            ;;
    esac
    
    echo "${similar_apps[@]}"
}

# Cek ketersediaan port
check_port_available() {
    local port=$1
    if ss -tuln | grep -q ":$port "; then
        return 1
    fi
    return 0
}

find_available_port() {
    local base_port=$1
    local app_name=$2
    local max_attempts=100
    
    for ((i=0; i<max_attempts; i++)); do
        local check_port=$((base_port + i))
        if check_port_available "$check_port"; then
            echo "$check_port"
            return 0
        fi
    done
    
    echo "0"
    return 1
}

handle_port_conflict() {
    local app_name="$1"
    local port="$2"
    local app_ports="${APP_PORTS[$app_name]}"
    local ports=(${app_ports//,/ })
    
    log_info "Memeriksa port untuk ${app_name}..."
    
    local all_ports_ok=true
    for p in "${ports[@]}"; do
        p=$(echo "$p" | xargs)
        if ! check_port_available "$p"; then
            all_ports_ok=false
            log_warn "Port $p sudah digunakan oleh layanan lain:"
            ss -tuln | grep ":$p " | head -3
        fi
    done
    
    if ! $all_ports_ok; then
        echo ""
        log_warn "Port default untuk ${app_name} (${app_ports}) sudah terpakai."
        echo ""
        
        # Cari port alternatif untuk setiap port yang bermasalah
        local new_ports=()
        for p in "${ports[@]}"; do
            p=$(echo "$p" | xargs)
            if ! check_port_available "$p"; then
                local alt_port=$(find_available_port "$p" "$app_name")
                if [[ "$alt_port" != "0" ]]; then
                    new_ports+=("$alt_port")
                    log_info "Port alternatif: ${p} -> ${alt_port}"
                fi
            else
                new_ports+=("$p")
            fi
        done
        
        echo ""
        echo -e "${YELLOW}Pilih tindakan:${NC}"
        echo "1) Gunakan port alternatif (${new_ports[*]})"
        echo "2) Skip instalasi ${app_name}"
        echo "3) Paksa pakai port default (tidak disarankan)"
        read -p "Pilihan [1-3]: " port_choice
        
        case $port_choice in
            1)
                log_info "Menggunakan port alternatif untuk ${app_name}"
                echo "${new_ports[*]}" > "/tmp/${app_name}_ports"
                return 0
                ;;
            2)
                log_info "Melewati instalasi ${app_name}"
                return 1
                ;;
            3)
                log_warn "Memaksa menggunakan port default (mungkin konflik)"
                return 0
                ;;
            *)
                log_info "Melewati instalasi ${app_name}"
                return 1
                ;;
        esac
    fi
    
    return 0
}

install_nginx() {
    log_info "Menginstall Nginx..."
    
    local similar=$(detect_similar_apps "nginx")
    if [[ -n "$similar" ]] && [[ -f /usr/sbin/nginx ]]; then
        log_warn "Nginx sudah terinstall!"
        echo ""
        echo -e "${YELLOW}Pilih tindakan:${NC}"
        echo "1) Update Nginx"
        echo "2) Hapus Nginx"
        echo "3) Hapus dan Install ulang"
        echo "4) Skip"
        read -p "Pilihan [1-4]: " nginx_choice
        
        case $nginx_choice in
            1) apt-get install --only-upgrade -y nginx 2>&1 | tee -a "$LOG_FILE"; log_success "Nginx diupdate"; return 0 ;;
            2) apt-get remove --purge -y nginx 2>&1 | tee -a "$LOG_FILE"; log_success "Nginx dihapus"; return 0 ;;
            3) apt-get remove --purge -y nginx 2>&1 | tee -a "$LOG_FILE"; apt-get install -y nginx 2>&1 | tee -a "$LOG_FILE"; log_success "Nginx diinstall ulang"; return 0 ;;
            4) log_info "Melewati Nginx"; return 0 ;;
        esac
    fi
    
    if ! handle_port_conflict "nginx" "80,443"; then
        return 0
    fi
    
    apt-get install -y nginx 2>&1 | tee -a "$LOG_FILE"
    
    # Konfigurasi Nginx untuk landing page
    cat > /etc/nginx/sites-available/default << 'NGINXEOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    root /var/www/html;
    index index.php index.html index.htm;

    server_name _;

    location / {
        try_files $uri $uri/ =404;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.2-fpm.sock;
    }

    location ~ /\.ht {
        deny all;
    }
}
NGINXEOF
    
    systemctl enable nginx
    systemctl restart nginx
    
    log_success "Nginx berhasil diinstall"
}

install_apache() {
    log_info "Menginstall Apache..."
    
    if [[ -f /usr/sbin/apache2 ]]; then
        log_warn "Apache sudah terinstall!"
        echo ""
        echo -e "${YELLOW}Pilih tindakan:${NC}"
        echo "1) Update Apache"
        echo "2) Hapus Apache"
        echo "3) Hapus dan Install ulang"
        echo "4) Skip"
        read -p "Pilihan [1-4]: " ap_choice
        
        case $ap_choice in
            1) apt-get install --only-upgrade -y apache2 2>&1 | tee -a "$LOG_FILE"; log_success "Apache diupdate"; return 0 ;;
            2) apt-get remove --purge -y apache2 2>&1 | tee -a "$LOG_FILE"; log_success "Apache dihapus"; return 0 ;;
            3) apt-get remove --purge -y apache2 2>&1 | tee -a "$LOG_FILE"; apt-get install -y apache2 2>&1 | tee -a "$LOG_FILE"; log_success "Apache diinstall ulang"; return 0 ;;
            4) log_info "Melewati Apache"; return 0 ;;
        esac
    fi
    
    if ! handle_port_conflict "apache2" "80,443"; then
        return 0
    fi
    
    apt-get install -y apache2 2>&1 | tee -a "$LOG_FILE"
    
    a2enmod php8.2
    a2enmod rewrite
    systemctl enable apache2
    systemctl restart apache2
    
    log_success "Apache berhasil diinstall"
}

install_php() {
    log_info "Menginstall PHP..."
    
    apt-get install -y php8.2 php8.2-fpm php8.2-mysql php8.2-mbstring php8.2-xml php8.2-curl php8.2-gd php8.2-zip php8.2-bcmath 2>&1 | tee -a "$LOG_FILE"
    
    systemctl enable php8.2-fpm
    systemctl restart php8.2-fpm
    
    log_success "PHP berhasil diinstall"
}

install_mysql() {
    log_info "Menginstall MariaDB/MySQL..."
    
    if [[ -f /usr/bin/mysql ]]; then
        log_warn "MySQL/MariaDB sudah terinstall!"
        echo ""
        echo -e "${YELLOW}Pilih tindakan:${NC}"
        echo "1) Update"
        echo "2) Hapus"
        echo "3) Hapus dan Install ulang"
        echo "4) Skip"
        read -p "Pilihan [1-4]: " mysql_choice
        
        case $mysql_choice in
            1) apt-get install --only-upgrade -y mariadb-server 2>&1 | tee -a "$LOG_FILE"; log_success "MariaDB diupdate"; return 0 ;;
            2) apt-get remove --purge -y mariadb-server 2>&1 | tee -a "$LOG_FILE"; log_success "MariaDB dihapus"; return 0 ;;
            3) apt-get remove --purge -y mariadb-server 2>&1 | tee -a "$LOG_FILE"; apt-get install -y mariadb-server 2>&1 | tee -a "$LOG_FILE"; log_success "MariaDB diinstall ulang"; return 0 ;;
            4) log_info "Melewati MariaDB"; return 0 ;;
        esac
    fi
    
    if ! handle_port_conflict "mariadb" "3306"; then
        return 0
    fi
    
    apt-get install -y mariadb-server 2>&1 | tee -a "$LOG_FILE"
    
    systemctl enable mariadb
    systemctl restart mariadb
    
    # Secure installation
    mysql -e "DELETE FROM mysql.user WHERE User='';"
    mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
    mysql -e "DROP DATABASE IF EXISTS test;"
    mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
    mysql -e "FLUSH PRIVILEGES;"
    
    log_success "MariaDB berhasil diinstall"
}

install_redis() {
    log_info "Menginstall Redis..."
    
    if [[ -f /usr/bin/redis-server ]]; then
        log_warn "Redis sudah terinstall!"
        echo ""
        echo -e "${YELLOW}Pilih tindakan:${NC}"
        echo "1) Update"
        echo "2) Hapus"
        echo "3) Hapus dan Install ulang"
        echo "4) Skip"
        read -p "Pilihan [1-4]: " redis_choice
        
        case $redis_choice in
            1) apt-get install --only-upgrade -y redis-server 2>&1 | tee -a "$LOG_FILE"; log_success "Redis diupdate"; return 0 ;;
            2) apt-get remove --purge -y redis-server 2>&1 | tee -a "$LOG_FILE"; log_success "Redis dihapus"; return 0 ;;
            3) apt-get remove --purge -y redis-server 2>&1 | tee -a "$LOG_FILE"; apt-get install -y redis-server 2>&1 | tee -a "$LOG_FILE"; log_success "Redis diinstall ulang"; return 0 ;;
            4) log_info "Melewati Redis"; return 0 ;;
        esac
    fi
    
    if ! handle_port_conflict "redis" "6379"; then
        return 0
    fi
    
    apt-get install -y redis-server 2>&1 | tee -a "$LOG_FILE"
    systemctl enable redis-server
    systemctl restart redis-server
    
    log_success "Redis berhasil diinstall"
}

install_squid() {
    log_info "Menginstall Squid-Cache..."
    
    if [[ -f /usr/sbin/squid ]]; then
        log_warn "Squid sudah terinstall!"
        echo ""
        echo -e "${YELLOW}Pilih tindakan:${NC}"
        echo "1) Update"
        echo "2) Hapus"
        echo "3) Hapus dan Install ulang"
        echo "4) Skip"
        read -p "Pilihan [1-4]: " squid_choice
        
        case $squid_choice in
            1) apt-get install --only-upgrade -y squid 2>&1 | tee -a "$LOG_FILE"; log_success "Squid diupdate"; return 0 ;;
            2) apt-get remove --purge -y squid 2>&1 | tee -a "$LOG_FILE"; log_success "Squid dihapus"; return 0 ;;
            3) apt-get remove --purge -y squid 2>&1 | tee -a "$LOG_FILE"; apt-get install -y squid 2>&1 | tee -a "$LOG_FILE"; log_success "Squid diinstall ulang"; return 0 ;;
            4) log_info "Melewati Squid"; return 0 ;;
        esac
    fi
    
    if ! handle_port_conflict "squid" "3128"; then
        return 0
    fi
    
    apt-get install -y squid 2>&1 | tee -a "$LOG_FILE"
    
    # Copy config
    cp "$INSTALL_DIR/config/squid/squid.conf" /etc/squid/squid.conf
    
    # Buat cache directory di SDCard jika ada
    if [[ -d "$SDCARD_MOUNT" ]]; then
        mkdir -p "$SDCARD_MOUNT/squid/cache"
        mkdir -p "$SDCARD_MOUNT/squid/logs"
        chown -R proxy:proxy "$SDCARD_MOUNT/squid"
        sed -i "s|cache_dir ufs /var/spool/squid 5000|cache_dir ufs $SDCARD_MOUNT/squid/cache 5000|" /etc/squid/squid.conf
    fi
    
    squid -z 2>&1 | tee -a "$LOG_FILE"
    systemctl enable squid
    systemctl restart squid
    
    log_success "Squid-Cache berhasil diinstall"
}

install_docker() {
    log_info "Menginstall Docker..."
    
    if [[ -f /usr/bin/docker ]]; then
        log_warn "Docker sudah terinstall!"
        echo ""
        echo -e "${YELLOW}Pilih tindakan:${NC}"
        echo "1) Update"
        echo "2) Hapus"
        echo "3) Hapus dan Install ulang"
        echo "4) Skip"
        read -p "Pilihan [1-4]: " docker_choice
        
        case $docker_choice in
            1) apt-get install --only-upgrade -y docker-ce 2>&1 | tee -a "$LOG_FILE"; log_success "Docker diupdate"; return 0 ;;
            2) apt-get remove --purge -y docker-ce docker-ce-cli containerd.io 2>&1 | tee -a "$LOG_FILE"; log_success "Docker dihapus"; return 0 ;;
            3) apt-get remove --purge -y docker-ce docker-ce-cli containerd.io 2>&1 | tee -a "$LOG_FILE"; apt-get install -y docker-ce docker-ce-cli containerd.io 2>&1 | tee -a "$LOG_FILE"; log_success "Docker diinstall ulang"; return 0 ;;
            4) log_info "Melewati Docker"; return 0 ;;
        esac
    fi
    
    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh 2>&1 | tee -a "$LOG_FILE" || true
    if [[ -f /tmp/get-docker.sh ]]; then
        sh /tmp/get-docker.sh 2>&1 | tee -a "$LOG_FILE"
        
        # Pindahkan Docker ke SDCard
        if [[ -d "$SDCARD_MOUNT" ]]; then
            systemctl stop docker
            mkdir -p "$SDCARD_MOUNT/docker"
            cat > /etc/docker/daemon.json << 'DOCKEREOF'
{
    "data-root": "/mnt/sdcard/docker"
}
DOCKEREOF
            systemctl start docker
        fi
        
        systemctl enable docker
        log_success "Docker berhasil diinstall"
    else
        log_warn "Gagal mendownload Docker, install dari repo..."
        apt-get install -y docker.io 2>&1 | tee -a "$LOG_FILE"
        systemctl enable docker
        systemctl start docker
        log_success "Docker (dari repo) berhasil diinstall"
    fi
}

install_netdata() {
    log_info "Menginstall Netdata..."
    
    if [[ -f /usr/sbin/netdata ]]; then
        log_warn "Netdata sudah terinstall!"
        echo ""
        echo -e "${YELLOW}Pilih tindakan:${NC}"
        echo "1) Update"
        echo "2) Hapus"
        echo "3) Hapus dan Install ulang"
        echo "4) Skip"
        read -p "Pilihan [1-4]: " netdata_choice
        
        case $netdata_choice in
            1) apt-get install --only-upgrade -y netdata 2>&1 | tee -a "$LOG_FILE"; log_success "Netdata diupdate"; return 0 ;;
            2) apt-get remove --purge -y netdata 2>&1 | tee -a "$LOG_FILE"; log_success "Netdata dihapus"; return 0 ;;
            3) apt-get remove --purge -y netdata 2>&1 | tee -a "$LOG_FILE"; bash <(curl -Ss https://my-netdata.io/kickstart.sh) 2>&1 | tee -a "$LOG_FILE"; log_success "Netdata diinstall ulang"; return 0 ;;
            4) log_info "Melewati Netdata"; return 0 ;;
        esac
    fi
    
    bash <(curl -Ss https://my-netdata.io/kickstart.sh) 2>&1 | tee -a "$LOG_FILE" || true
    if [[ ! -f /usr/sbin/netdata ]]; then
        apt-get install -y netdata 2>&1 | tee -a "$LOG_FILE"
    fi
    
    log_success "Netdata berhasil diinstall"
}

install_jellyfin() {
    log_info "Menginstall Jellyfin..."
    
    if [[ -f /usr/bin/jellyfin ]]; then
        log_warn "Jellyfin sudah terinstall!"
        echo ""
        echo -e "${YELLOW}Pilih tindakan:${NC}"
        echo "1) Update"
        echo "2) Hapus"
        echo "3) Hapus dan Install ulang"
        echo "4) Skip"
        read -p "Pilihan [1-4]: " jelly_choice
        
        case $jelly_choice in
            1) apt-get install --only-upgrade -y jellyfin 2>&1 | tee -a "$LOG_FILE"; log_success "Jellyfin diupdate"; return 0 ;;
            2) apt-get remove --purge -y jellyfin 2>&1 | tee -a "$LOG_FILE"; log_success "Jellyfin dihapus"; return 0 ;;
            3) apt-get remove --purge -y jellyfin 2>&1 | tee -a "$LOG_FILE"; 
               curl https://repo.jellyfin.org/install-debuntu.sh | bash 2>&1 | tee -a "$LOG_FILE"; 
               log_success "Jellyfin diinstall ulang"; return 0 ;;
            4) log_info "Melewati Jellyfin"; return 0 ;;
        esac
    fi
    
    curl https://repo.jellyfin.org/install-debuntu.sh | bash 2>&1 | tee -a "$LOG_FILE" || true
    if [[ ! -f /usr/bin/jellyfin ]]; then
        log_warn "Gagal install dari repo resmi, menggunakan paket Debian..."
        apt-get install -y jellyfin 2>&1 | tee -a "$LOG_FILE" || log_warn "Jellyfin tidak tersedia di repo default"
    fi
    
    log_success "Jellyfin berhasil diinstall (jika tersedia)"
}

install_portainer() {
    log_info "Menginstall Portainer..."
    
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "portainer"; then
        log_warn "Portainer sudah terinstall!"
        echo ""
        echo -e "${YELLOW}Pilih tindakan:${NC}"
        echo "1) Update"
        echo "2) Hapus"
        echo "3) Hapus dan Install ulang"
        echo "4) Skip"
        read -p "Pilihan [1-4]: " port_choice
        
        case $port_choice in
            1) docker pull portainer/portainer-ce:latest 2>&1 | tee -a "$LOG_FILE"; docker stop portainer; docker rm portainer; docker run -d -p 9443:9443 --name portainer --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce:latest 2>&1 | tee -a "$LOG_FILE"; log_success "Portainer diupdate"; return 0 ;;
            2) docker stop portainer; docker rm portainer; docker volume rm portainer_data; log_success "Portainer dihapus"; return 0 ;;
            3) docker stop portainer; docker rm portainer; docker volume rm portainer_data; docker run -d -p 9443:9443 --name portainer --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce:latest 2>&1 | tee -a "$LOG_FILE"; log_success "Portainer diinstall ulang"; return 0 ;;
            4) log_info "Melewati Portainer"; return 0 ;;
        esac
    fi
    
    if ! docker info &>/dev/null; then
        log_warn "Docker belum terinstall. Install Docker terlebih dahulu."
        return 1
    fi
    
    docker volume create portainer_data 2>&1 | tee -a "$LOG_FILE"
    docker run -d -p 9443:9443 --name portainer --restart=always \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v portainer_data:/data \
        portainer/portainer-ce:latest 2>&1 | tee -a "$LOG_FILE"
    
    log_success "Portainer berhasil diinstall"
}

install_transmission() {
    log_info "Menginstall Transmission..."
    
    if [[ -f /usr/bin/transmission-daemon ]]; then
        log_warn "Transmission sudah terinstall!"
        echo ""
        echo -e "${YELLOW}Pilih tindakan:${NC}"
        echo "1) Update"
        echo "2) Hapus"
        echo "3) Hapus dan Install ulang"
        echo "4) Skip"
        read -p "Pilihan [1-4]: " tr_choice
        
        case $tr_choice in
            1) apt-get install --only-upgrade -y transmission-daemon 2>&1 | tee -a "$LOG_FILE"; log_success "Transmission diupdate"; return 0 ;;
            2) apt-get remove --purge -y transmission-daemon 2>&1 | tee -a "$LOG_FILE"; log_success "Transmission dihapus"; return 0 ;;
            3) apt-get remove --purge -y transmission-daemon 2>&1 | tee -a "$LOG_FILE"; apt-get install -y transmission-daemon 2>&1 | tee -a "$LOG_FILE"; log_success "Transmission diinstall ulang"; return 0 ;;
            4) log_info "Melewati Transmission"; return 0 ;;
        esac
    fi
    
    apt-get install -y transmission-daemon 2>&1 | tee -a "$LOG_FILE"
    
    # Konfigurasi download ke SDCard
    if [[ -d "$SDCARD_MOUNT" ]]; then
        systemctl stop transmission-daemon
        mkdir -p "$SDCARD_MOUNT/transmission/downloads"
        mkdir -p "$SDCARD_MOUNT/transmission/incomplete"
        sed -i "s|\"download-dir\": \"/var/lib/transmission-daemon/downloads\"|\"download-dir\": \"$SDCARD_MOUNT/transmission/downloads\"|" /etc/transmission-daemon/settings.json
        sed -i "s|\"incomplete-dir\": \"/var/lib/transmission-daemon/Downloads\"|\"incomplete-dir\": \"$SDCARD_MOUNT/transmission/incomplete\"|" /etc/transmission-daemon/settings.json
        systemctl start transmission-daemon
    fi
    
    systemctl enable transmission-daemon
    log_success "Transmission berhasil diinstall"
}

install_syncthing() {
    log_info "Menginstall Syncthing..."
    
    if [[ -f /usr/bin/syncthing ]]; then
        log_warn "Syncthing sudah terinstall!"
        echo ""
        echo -e "${YELLOW}Pilih tindakan:${NC}"
        echo "1) Update"
        echo "2) Hapus"
        echo "3) Hapus dan Install ulang"
        echo "4) Skip"
        read -p "Pilihan [1-4]: " sync_choice
        
        case $sync_choice in
            1) apt-get install --only-upgrade -y syncthing 2>&1 | tee -a "$LOG_FILE"; log_success "Syncthing diupdate"; return 0 ;;
            2) apt-get remove --purge -y syncthing 2>&1 | tee -a "$LOG_FILE"; log_success "Syncthing dihapus"; return 0 ;;
            3) apt-get remove --purge -y syncthing 2>&1 | tee -a "$LOG_FILE"; apt-get install -y syncthing 2>&1 | tee -a "$LOG_FILE"; log_success "Syncthing diinstall ulang"; return 0 ;;
            4) log_info "Melewati Syncthing"; return 0 ;;
        esac
    fi
    
    apt-get install -y syncthing 2>&1 | tee -a "$LOG_FILE"
    
    # Setup service untuk user
    systemctl enable syncthing@root
    systemctl start syncthing@root
    
    log_success "Syncthing berhasil diinstall"
}

install_adblock() {
    log_info "Menginstall Adblock..."
    
    # Gunakan Pi-hole atau dnsmasq-based adblock
    if [[ -f /usr/bin/pihole ]]; then
        log_warn "Pi-hole sudah terinstall!"
        echo ""
        echo -e "${YELLOW}Pilih tindakan:${NC}"
        echo "1) Update filter"
        echo "2) Hapus Pi-hole"
        echo "3) Hapus dan Install ulang"
        echo "4) Skip"
        read -p "Pilihan [1-4]: " pihole_choice
        
        case $pihole_choice in
            1) pihole updateGravity 2>&1 | tee -a "$LOG_FILE"; log_success "Filter Pi-hole diupdate"; return 0 ;;
            2) pihole uninstall 2>&1 | tee -a "$LOG_FILE"; log_success "Pi-hole dihapus"; return 0 ;;
            3) pihole uninstall 2>&1 | tee -a "$LOG_FILE"; curl -sSL https://install.pi-hole.net | bash 2>&1 | tee -a "$LOG_FILE"; log_success "Pi-hole diinstall ulang"; return 0 ;;
            4) log_info "Melewati Pi-hole"; return 0 ;;
        esac
    fi
    
    # Alternatif: Install Pi-hole
    log_info "Menginstall Pi-hole (Adblock)..."
    curl -sSL https://install.pi-hole.net | bash 2>&1 | tee -a "$LOG_FILE" || true
    
    if [[ -f /usr/bin/pihole ]]; then
        # Tambah filter Indonesia
        log_info "Menambahkan filter khusus Indonesia..."
        pihole -a adlist add https://raw.githubusercontent.com/rey_public/filter/main/indonesian-adlist.txt 2>/dev/null || true
        pihole -a adlist add https://raw.githubusercontent.com/rey_public/filter/main/indonesian-privacy.txt 2>/dev/null || true
        
        # Tambah dari file lokal
        if [[ -f "$INSTALL_DIR/config/adblock/filter-indo.txt" ]]; then
            while IFS= read -r domain; do
                [[ -z "$domain" || "$domain" == \#* ]] && continue
                pihole -b "$domain" 2>/dev/null || true
            done < "$INSTALL_DIR/config/adblock/filter-indo.txt"
        fi
        
        pihole updateGravity 2>&1 | tee -a "$LOG_FILE"
        log_success "Pi-hole dengan filter Indonesia berhasil diinstall"
    else
        log_warn "Gagal install Pi-hole. Menginstall dnsmasq-based adblock..."
        install_dnsmasq_adblock
    fi
}

install_dnsmasq_adblock() {
    log_info "Menginstall dnsmasq adblock..."
    
    apt-get install -y dnsmasq 2>&1 | tee -a "$LOG_FILE"
    
    # Download filter
    mkdir -p /etc/dnsmasq.d
    
    # Filter umum
    cat > /etc/dnsmasq.d/adblock.conf << 'ADBLOCKEOF'
# Adblock domains - loaded from external sources
addn-hosts=/etc/dnsmasq.d/adblock.hosts
ADBLOCKEOF
    
    # Download dan gabungkan filter
    log_info "Mendownload filter adblock..."
    local filters=(
        "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
        "https://someonewhocares.org/hosts/zero/hosts"
        "https://raw.githubusercontent.com/rey_public/filter/main/indonesian-adlist.txt"
    )
    
    > /etc/dnsmasq.d/adblock.hosts
    for url in "${filters[@]}"; do
        curl -sL "$url" 2>/dev/null | grep -E '^0\.0\.0\.0' >> /etc/dnsmasq.d/adblock.hosts 2>/dev/null || true
    done
    
    # Tambah filter lokal Indonesia
    if [[ -f "$INSTALL_DIR/config/adblock/filter-indo.txt" ]]; then
        while IFS= read -r domain; do
            [[ -z "$domain" || "$domain" == \#* ]] && continue
            echo "0.0.0.0 $domain" >> /etc/dnsmasq.d/adblock.hosts
        done < "$INSTALL_DIR/config/adblock/filter-indo.txt"
    fi
    
    # Hapus duplikat
    sort -u /etc/dnsmasq.d/adblock.hosts -o /etc/dnsmasq.d/adblock.hosts
    
    sed -i 's/#port=53/port=53/' /etc/dnsmasq.conf
    systemctl enable dnsmasq
    systemctl restart dnsmasq
    
    log_success "dnsmasq adblock berhasil diinstall dengan $(wc -l < /etc/dnsmasq.d/adblock.hosts) domain"
}

install_nodejs() {
    log_info "Menginstall Node.js..."
    
    if [[ -f /usr/bin/node ]]; then
        log_warn "Node.js sudah terinstall!"
        echo ""
        echo -e "${YELLOW}Pilih tindakan:${NC}"
        echo "1) Update"
        echo "2) Hapus"
        echo "3) Hapus dan Install ulang"
        echo "4) Skip"
        read -p "Pilihan [1-4]: " node_choice
        
        case $node_choice in
            1) curl -fsSL https://deb.nodesource.com/setup_20.x | bash - 2>&1 | tee -a "$LOG_FILE"; apt-get install -y nodejs 2>&1 | tee -a "$LOG_FILE"; log_success "Node.js diupdate"; return 0 ;;
            2) apt-get remove --purge -y nodejs 2>&1 | tee -a "$LOG_FILE"; log_success "Node.js dihapus"; return 0 ;;
            3) apt-get remove --purge -y nodejs 2>&1 | tee -a "$LOG_FILE"; curl -fsSL https://deb.nodesource.com/setup_20.x | bash - 2>&1 | tee -a "$LOG_FILE"; apt-get install -y nodejs 2>&1 | tee -a "$LOG_FILE"; log_success "Node.js diinstall ulang"; return 0 ;;
            4) log_info "Melewati Node.js"; return 0 ;;
        esac
    fi
    
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - 2>&1 | tee -a "$LOG_FILE"
    apt-get install -y nodejs 2>&1 | tee -a "$LOG_FILE"
    
    log_success "Node.js $(node -v) berhasil diinstall"
}

# ==================== DEPLOY LANDING PAGE ====================

deploy_landing_page() {
    log_info "Mendeploy landing page..."
    
    mkdir -p "$WWW_DIR"
    
    # Copy semua file landing page
    cp -r "$INSTALL_DIR/landing-page/"* "$WWW_DIR/"
    cp -r "$INSTALL_DIR/file-manager/"* "$WWW_DIR/"
    cp -r "$INSTALL_DIR/www/"* "$WWW_DIR/"
    
    # Buat symlink atau copy folder default
    mkdir -p "$WWW_DIR/My Document"
    mkdir -p "$WWW_DIR/My Music"
    mkdir -p "$WWW_DIR/My Pictures"
    mkdir -p "$WWW_DIR/My Video"
    
    # Permission
    chown -R www-data:www-data "$WWW_DIR" 2>/dev/null || true
    find "$WWW_DIR" -type d -exec chmod 755 {} \;
    find "$WWW_DIR" -type f -exec chmod 644 {} \;
    
    # Buat symlink untuk akses root via file manager
    if [[ ! -L "$WWW_DIR/rootfs" ]]; then
        ln -sf / "$WWW_DIR/rootfs" 2>/dev/null || true
    fi
    
    log_success "Landing page dideploy ke ${WWW_DIR}"
}

# ==================== SETUP SDCARD ====================

setup_sdcard() {
    log_info "Menyiapkan SDCard sebagai storage utama..."
    
    local sdcard_dev=$(cat /tmp/sdcard_dev 2>/dev/null)
    if [[ -z "$sdcard_dev" ]]; then
        log_error "Device SDCard tidak diketahui"
        return 1
    fi
    
    # Cari partisi pertama
    local sdcard_part="${sdcard_dev}p1"
    if [[ "$sdcard_dev" == /dev/sd* ]]; then
        sdcard_part="${sdcard_dev}1"
    fi
    
    if [[ ! -b "$sdcard_part" ]]; then
        log_info "Membuat partisi pada ${sdcard_dev}..."
        echo -e "o\nn\np\n1\n\n\nw" | fdisk "$sdcard_dev" 2>&1 | tee -a "$LOG_FILE"
        sleep 2
        mkfs.ext4 -F "$sdcard_part" 2>&1 | tee -a "$LOG_FILE"
    fi
    
    # Mount
    mkdir -p "$SDCARD_MOUNT"
    if ! mountpoint -q "$SDCARD_MOUNT"; then
        mount "$sdcard_part" "$SDCARD_MOUNT" 2>&1 | tee -a "$LOG_FILE"
    fi
    
    # Buat direktori penting di SDCard
    mkdir -p "$SDCARD_MOUNT"/{www,log,cache,home,docker,squid,mysql,redis,downloads}
    
    # Symlink
    log_info "Membuat symlink dari SDCard..."
    
    # Backup dan replace folder penting
    for dir in www log cache home; do
        target_dir="$SDCARD_MOUNT/$dir"
        if [[ -d "/var/$dir" ]] && [[ ! -L "/var/$dir" ]]; then
            if [[ -z "$(ls -A /var/$dir 2>/dev/null)" ]]; then
                rmdir "/var/$dir"
            else
                cp -a "/var/$dir/"* "$target_dir/" 2>/dev/null || true
                rm -rf "/var/$dir"
            fi
            ln -sf "$target_dir" "/var/$dir"
        fi
    done
    
    # Update fstab
    local uuid=$(blkid -s UUID -o value "$sdcard_part" 2>/dev/null)
    if [[ -n "$uuid" ]]; then
        if ! grep -q "$uuid" /etc/fstab; then
            echo "UUID=$uuid $SDCARD_MOUNT ext4 defaults,noatime,nodiratime 0 2" >> /etc/fstab
        fi
    fi
    
    log_success "SDCard siap sebagai storage utama"
}

# ==================== INSTALL COMPLETE ====================

install_complete() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  INSTALASI SELESAI!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "Landing Page: ${CYAN}http://$(hostname -I | awk '{print $1}')${NC}"
    echo -e "File Manager: ${CYAN}http://$(hostname -I | awk '{print $1}')/file-manager/${NC}"
    echo ""
    echo -e "Layanan terinstall:"
    
    [[ -f /usr/sbin/nginx ]] && echo -e "  - ${GREEN}Nginx${NC}"
    [[ -f /usr/sbin/apache2 ]] && echo -e "  - ${GREEN}Apache${NC}"
    [[ -f /usr/sbin/squid ]] && echo -e "  - ${GREEN}Squid-Cache${NC} (port 3128)"
    [[ -f /usr/bin/mysql ]] && echo -e "  - ${GREEN}MariaDB/MySQL${NC}"
    [[ -f /usr/bin/redis-server ]] && echo -e "  - ${GREEN}Redis${NC}"
    [[ -f /usr/bin/node ]] && echo -e "  - ${GREEN}Node.js${NC}"
    [[ -f /usr/sbin/netdata ]] && echo -e "  - ${GREEN}Netdata${NC} (port 19999)"
    [[ -f /usr/bin/jellyfin ]] && echo -e "  - ${GREEN}Jellyfin${NC} (port 8096)"
    [[ -f /usr/bin/pihole ]] && echo -e "  - ${GREEN}Pi-hole (Adblock)${NC}"
    [[ -f /usr/bin/syncthing ]] && echo -e "  - ${GREEN}Syncthing${NC} (port 8384)"
    [[ -f /usr/bin/transmission-daemon ]] && echo -e "  - ${GREEN}Transmission${NC} (port 9091)"
    docker ps --format '{{.Names}}' 2>/dev/null | grep -q "portainer" && echo -e "  - ${GREEN}Portainer${NC} (port 9443)"
    
    echo ""
    echo -e "${YELLOW}Catatan:${NC}"
    echo "- Semua data aplikasi disimpan di SDCard"
    echo "- Log instalasi: ${LOG_FILE}"
    echo "- Untuk mengelola layanan: ${CYAN}./scripts/services.sh${NC}"
    echo ""
}

# ==================== MENU ====================

main_menu() {
    banner
    check_root
    
    echo -e "${CYAN}Pilih aplikasi yang akan diinstall:${NC}"
    echo ""
    echo -e "${GREEN}1)${NC}  Landing Page + File Manager"
    echo -e "${GREEN}2)  Nginx ${NC}(Web Server)"
    echo -e "${GREEN}3)  Apache ${NC}(Web Server Alternatif)"
    echo -e "${GREEN}4)  PHP 8.2 ${NC}(PHP-FPM)"
    echo -e "${GREEN}5)  MariaDB/MySQL ${NC}(Database)"
    echo -e "${GREEN}6)  Redis ${NC}(Cache)"
    echo -e "${GREEN}7)  Squid-Cache ${NC}(Proxy)"
    echo -e "${GREEN}8)  Pi-hole/Adblock ${NC}(Blokir Iklan)"
    echo -e "${GREEN}9)  Docker ${NC}(Container)"
    echo -e "${GREEN}10) Netdata ${NC}(Monitoring)"
    echo -e "${GREEN}11) Portainer ${NC}(Container Management)"
    echo -e "${GREEN}12) Jellyfin ${NC}(Media Server)"
    echo -e "${GREEN}13) Transmission ${NC}(Torrent Client)"
    echo -e "${GREEN}14) Syncthing ${NC}(File Sync)"
    echo -e "${GREEN}15) Node.js ${NC}(JavaScript Runtime)"
    echo ""
    echo -e "${GREEN}a)${NC}  Install ALL (Semua Aplikasi)"
    echo -e "${GREEN}s)${NC}  Setup SDCard sebagai Storage Utama"
    echo -e "${GREEN}q)${NC}  Keluar"
    echo ""
    read -p "Pilihan Anda: " menu_choice
    
    case $menu_choice in
        1)
            detect_sdcard
            setup_sdcard
            detect_device
            update_system
            install_php
            deploy_landing_page
            install_complete
            ;;
        2) install_nginx ;;
        3) install_apache ;;
        4) install_php ;;
        5) install_mysql ;;
        6) install_redis ;;
        7) install_squid ;;
        8) install_adblock ;;
        9) install_docker ;;
        10) install_netdata ;;
        11) install_portainer ;;
        12) install_jellyfin ;;
        13) install_transmission ;;
        14) install_syncthing ;;
        15) install_nodejs ;;
        a|A)
            detect_sdcard
            setup_sdcard
            detect_device
            update_system
            install_php
            install_nginx
            install_mysql
            install_redis
            install_squid
            install_adblock
            install_nodejs
            install_docker
            install_netdata
            install_jellyfin
            install_transmission
            install_syncthing
            deploy_landing_page
            install_complete
            ;;
        s|S)
            detect_sdcard
            setup_sdcard
            ;;
        q|Q)
            echo -e "${YELLOW}Keluar...${NC}"
            exit 0
            ;;
        *)
            log_error "Pilihan tidak valid!"
            sleep 2
            main_menu
            ;;
    esac
}

# ==================== MAIN ====================

# Setup trap
trap 'echo -e "${RED}Instalasi dibatalkan${NC}"; exit 1' INT TERM

# Buat log
> "$LOG_FILE"

# Direct execution or menu
if [[ "$1" == "--install-all" ]]; then
    banner
    check_root
    detect_sdcard
    setup_sdcard
    detect_device
    update_system
    install_php
    install_nginx
    install_mysql
    install_redis
    install_squid
    install_adblock
    install_nodejs
    install_docker
    install_netdata
    install_jellyfin
    install_transmission
    install_syncthing
    deploy_landing_page
    install_complete
elif [[ "$1" == "--install" && -n "$2" ]]; then
    banner
    check_root
    case "$2" in
        nginx) install_nginx ;;
        apache) install_apache ;;
        php) install_php ;;
        mysql|mariadb) install_mysql ;;
        redis) install_redis ;;
        squid) install_squid ;;
        adblock|pihole) install_adblock ;;
        docker) install_docker ;;
        netdata) install_netdata ;;
        portainer) install_portainer ;;
        jellyfin) install_jellyfin ;;
        transmission) install_transmission ;;
        syncthing) install_syncthing ;;
        nodejs|node) install_nodejs ;;
        landing) deploy_landing_page ;;
        sdcard) detect_sdcard; setup_sdcard ;;
        *) log_error "Aplikasi tidak dikenal: $2"; exit 1 ;;
    esac
else
    main_menu
fi
