#!/bin/bash
# MiniServer Adblock Setup Script
# Menginstall dan mengkonfigurasi adblock dengan filter Indonesia

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CONFIG_DIR="/opt/miniserver/config/adblock"
ADBLOCK_HOSTS="/etc/dnsmasq.d/adblock.hosts"
ADBLOCK_CONF="/etc/dnsmasq.d/adblock.conf"
LOG_FILE="/tmp/miniserver-adblock.log"

log_info() { echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1" | tee -a "$LOG_FILE"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"; }

# Sumber filter
declare -A FILTER_SOURCES
FILTER_SOURCES["StevenBlack"]="https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
FILTER_SOURCES["SomeoneWhoCares"]="https://someonewhocares.org/hosts/zero/hosts"
FILTER_SOURCES["EasyList"]="https://easylist.to/easylist/easylist.txt"
FILTER_SOURCES["EasyPrivacy"]="https://easylist.to/easylist/easyprivacy.txt"
FILTER_SOURCES["PeterLowe"]="https://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts&showintro=0&mimetype=plaintext"
FILTER_SOURCES["IndoAdlist"]="https://raw.githubusercontent.com/rey_public/filter/main/indonesian-adlist.txt"
FILTER_SOURCES["IndoPrivacy"]="https://raw.githubusercontent.com/rey_public/filter/main/indonesian-privacy.txt"

install_dependencies() {
    log_info "Menginstall dependencies..."
    apt-get install -y dnsmasq curl wget 2>&1 | tee -a "$LOG_FILE"
    
    systemctl stop systemd-resolved 2>/dev/null || true
    systemctl disable systemd-resolved 2>/dev/null || true
    
    log_success "Dependencies terinstall"
}

setup_dnsmasq() {
    log_info "Mengkonfigurasi dnsmasq..."
    
    mkdir -p /etc/dnsmasq.d
    
    # Konfigurasi utama dnsmasq
    cat > /etc/dnsmasq.conf << 'EOF'
# MiniServer dnsmasq configuration
domain-needed
bogus-priv
no-resolv
no-poll
server=1.1.1.1
server=8.8.8.8
server=9.9.9.9
interface=lo
bind-interfaces
expand-hosts
domain=miniserver.local
local=/miniserver.local/
EOF
    
    # Konfigurasi adblock
    cat > "$ADBLOCK_CONF" << 'EOF'
# MiniServer Adblock Configuration
addn-hosts=/etc/dnsmasq.d/adblock.hosts
cache-size=10000
neg-ttl=3600
local-service
EOF
    
    log_success "dnsmasq dikonfigurasi"
}

download_filters() {
    log_info "Mendownload filter adblock..."
    
    > "$ADBLOCK_HOSTS"
    local total=0
    
    for name in "${!FILTER_SOURCES[@]}"; do
        local url="${FILTER_SOURCES[$name]}"
        log_info "  Downloading $name..."
        
        local tmpfile=$(mktemp)
        if curl -sL --connect-timeout 10 --max-time 30 "$url" -o "$tmpfile" 2>/dev/null; then
            local count=$(grep -cE '^(0\.0\.0\.0|127\.0\.0\.1)' "$tmpfile" 2>/dev/null || echo 0)
            grep -E '^(0\.0\.0\.0|127\.0\.0\.1)' "$tmpfile" >> "$ADBLOCK_HOSTS" 2>/dev/null || true
            total=$((total + count))
            log_success "    +${count} domain dari $name"
        else
            log_warn "    Gagal mendownload $name"
        fi
        rm -f "$tmpfile"
    done
    
    # Tambah filter lokal Indonesia
    local local_filter="$CONFIG_DIR/filter-indo.txt"
    if [[ -f "$local_filter" ]]; then
        local local_count=0
        while IFS= read -r line; do
            line=$(echo "$line" | xargs)
            [[ -z "$line" || "$line" == \#* ]] && continue
            echo "0.0.0.0 $line" >> "$ADBLOCK_HOSTS"
            local_count=$((local_count + 1))
        done < "$local_filter"
        log_success "    +${local_count} domain dari filter lokal"
        total=$((total + local_count))
    fi
    
    # Hapus komentar dan duplikat
    sed -i '/^#/d' "$ADBLOCK_HOSTS" 2>/dev/null || true
    sort -u -o "$ADBLOCK_HOSTS" "$ADBLOCK_HOSTS"
    
    local unique=$(wc -l < "$ADBLOCK_HOSTS")
    log_success "Total ${unique} domain unik diblokir (dari ${total} total)"
}

restart_dnsmasq() {
    log_info "Merestart dnsmasq..."
    
    # Matikan systemd-resolved jika berjalan
    systemctl stop systemd-resolved 2>/dev/null || true
    
    # Cek port 53
    if ss -tuln | grep -q ':53 '; then
        log_warn "Port 53 sudah digunakan. Matikan service lain yang menggunakan port 53."
        ss -tuln | grep ':53 '
    fi
    
    systemctl enable dnsmasq 2>&1 | tee -a "$LOG_FILE"
    systemctl restart dnsmasq 2>&1 | tee -a "$LOG_FILE" || true
    
    sleep 1
    
    if systemctl is-active dnsmasq &>/dev/null; then
        log_success "dnsmasq berjalan"
    else
        log_error "dnsmasq gagal berjalan. Cek dengan: journalctl -u dnsmasq --no-pager"
        return 1
    fi
}

verify_adblock() {
    log_info "Memverifikasi adblock..."
    
    # Test DNS resolution
    local test_domains=(
        "google.com"
        "doubleclick.net"
    )
    
    for domain in "${test_domains[@]}"; do
        local result=$(dig +short "$domain" @127.0.0.1 2>/dev/null || nslookup "$domain" 127.0.0.1 2>/dev/null)
        log_info "  $domain -> ${result:-gagal}"
    done
    
    local blocked=$(wc -l < "$ADBLOCK_HOSTS")
    log_success "Adblock aktif dengan $blocked domain diblokir"
}

show_status() {
    local blocked=$(wc -l < "$ADBLOCK_HOSTS" 2>/dev/null || echo 0)
    local active=$(systemctl is-active dnsmasq 2>/dev/null || echo "inactive")
    
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║         ADBLOCK STATUS              ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"
    echo ""
    
    if [[ "$active" == "active" ]]; then
        echo -e "Status: ${GREEN}Aktif${NC}"
    else
        echo -e "Status: ${RED}Tidak aktif${NC}"
    fi
    
    echo -e "Domain diblokir: ${YELLOW}$blocked${NC}"
    echo ""
    echo -e "Filter aktif:"
    for name in "${!FILTER_SOURCES[@]}"; do
        echo -e "  • ${GREEN}$name${NC}"
    done
    
    # Cek filter Indonesia
    local indo_count=$(grep -ci "id\|indonesia" "$ADBLOCK_HOSTS" 2>/dev/null || echo 0)
    if [[ $indo_count -gt 0 ]]; then
        echo -e "  • ${GREEN}Filter Indonesia${NC} ($indo_count domain)"
    fi
    
    echo ""
    echo -e "DNS Server: ${CYAN}127.0.0.1:53${NC}"
    echo ""
}

# ==================== MAIN ====================

if [[ $EUID -ne 0 ]]; then
    log_error "Script harus dijalankan sebagai root (sudo)"
    exit 1
fi

> "$LOG_FILE"

echo ""
echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
echo -e "${BLUE}║      Adblock Setup Script           ║${NC}"
echo -e "${BLUE}║      MiniServer for Armbian         ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
echo ""

case "${1:-install}" in
    install|setup)
        install_dependencies
        setup_dnsmasq
        download_filters
        restart_dnsmasq
        verify_adblock
        show_status
        log_success "Adblock berhasil diinstall"
        ;;
    update)
        download_filters
        restart_dnsmasq
        verify_adblock
        log_success "Filter adblock diupdate"
        ;;
    status)
        show_status
        ;;
    restart)
        restart_dnsmasq
        ;;
    uninstall)
        log_info "Menghapus adblock..."
        systemctl stop dnsmasq 2>/dev/null || true
        systemctl disable dnsmasq 2>/dev/null || true
        rm -f "$ADBLOCK_HOSTS" "$ADBLOCK_CONF"
        log_success "Adblock dihapus"
        ;;
    help|--help|-h)
        echo "Usage: $0 {install|update|status|restart|uninstall|help}"
        echo ""
        echo "  install   - Install dan konfigurasi adblock (default)"
        echo "  update    - Update filter adblock"
        echo "  status    - Tampilkan status adblock"
        echo "  restart   - Restart dnsmasq"
        echo "  uninstall - Hapus adblock"
        echo "  help      - Tampilkan bantuan ini"
        ;;
esac
