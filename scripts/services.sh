#!/bin/bash
# MiniServer Service Manager
# Mengelola layanan sistem dengan mudah

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Daftar layanan yang dikenal
SERVICES=(
    "nginx"
    "apache2"
    "php8.2-fpm"
    "mariadb"
    "mysql"
    "redis-server"
    "squid"
    "pihole-FTL"
    "dnsmasq"
    "docker"
    "netdata"
    "jellyfin"
    "transmission-daemon"
    "syncthing@root"
    "cockpit"
    "ssh"
    "cron"
)

show_help() {
    echo "MiniServer Service Manager"
    echo ""
    echo "Usage: $0 <command> [service]"
    echo ""
    echo "Commands:"
    echo "  list        - Tampilkan semua layanan dan statusnya"
    echo "  status      - Tampilkan status layanan"
    echo "  start       - Mulai layanan"
    echo "  stop        - Hentikan layanan"
    echo "  restart     - Restart layanan"
    echo "  enable      - Aktifkan layanan saat boot"
    echo "  disable     - Nonaktifkan layanan saat boot"
    echo "  logs        - Tampilkan log layanan"
    echo ""
    echo "Examples:"
    echo "  $0 list                   # Tampilkan semua layanan"
    echo "  $0 status nginx           # Status Nginx"
    echo "  $0 restart squid          # Restart Squid"
    echo "  $0 logs nginx -n 50       # 50 baris terakhir log Nginx"
    echo ""
}

list_services() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║              DAFTAR LAYANAN                     ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
    printf "%-25s %-10s %-10s %s\n" "LAYANAN" "STATUS" "ENABLED" "PORT"
    echo "──────────────────────────────────────────────────────────"
    
    for svc in "${SERVICES[@]}"; do
        local status=$(systemctl is-active "$svc" 2>/dev/null || echo "not_found")
        local enabled=$(systemctl is-enabled "$svc" 2>/dev/null || echo "not_found")
        
        if [[ "$status" == "not_found" ]]; then
            continue
        fi
        
        local status_icon=""
        local enabled_icon=""
        
        case "$status" in
            active) status_icon="${GREEN}● Active${NC}" ;;
            inactive) status_icon="${RED}○ Inactive${NC}" ;;
            activating) status_icon="${YELLOW}◌ Starting${NC}" ;;
            *) status_icon="${YELLOW}○ ${status}${NC}" ;;
        esac
        
        case "$enabled" in
            enabled|static) enabled_icon="${GREEN}✓${NC}" ;;
            disabled) enabled_icon="${RED}✗${NC}" ;;
            *) enabled_icon="${YELLOW}?${NC}" ;;
        esac
        
        local port=""
        case "$svc" in
            nginx) port="80, 443" ;;
            apache2) port="80, 443" ;;
            squid) port="3128" ;;
            mariadb|mysql) port="3306" ;;
            redis-server) port="6379" ;;
            pihole-FTL) port="53, 80" ;;
            dnsmasq) port="53" ;;
            docker) port="2375" ;;
            netdata) port="19999" ;;
            jellyfin) port="8096" ;;
            transmission-daemon) port="9091" ;;
            syncthing*) port="8384" ;;
            cockpit) port="9090" ;;
            ssh) port="22" ;;
        esac
        
        printf "%-25s %b %-10b %s\n" "$svc" "$status_icon" "$enabled_icon" "$port"
    done
    echo ""
}

service_action() {
    local action="$1"
    local service="$2"
    
    if [[ -z "$service" ]]; then
        echo -e "${RED}Error: Nama layanan diperlukan${NC}"
        show_help
        exit 1
    fi
    
    echo -e "${BLUE}[INFO]${NC} Menjalankan: systemctl $action $service"
    echo ""
    
    case "$action" in
        status)
            systemctl status "$service" --no-pager 2>&1
            ;;
        start|stop|restart)
            systemctl "$action" "$service" 2>&1
            local rc=$?
            if [[ $rc -eq 0 ]]; then
                echo ""
                echo -e "${GREEN}✓ ${action^} $service berhasil${NC}"
            else
                echo ""
                echo -e "${RED}✗ ${action^} $service gagal (kode: $rc)${NC}"
            fi
            ;;
        enable|disable)
            systemctl "$action" "$service" 2>&1
            local rc=$?
            if [[ $rc -eq 0 ]]; then
                echo ""
                echo -e "${GREEN}✓ ${action^} $service berhasil${NC}"
            else
                echo ""
                echo -e "${RED}✗ ${action^} $service gagal (kode: $rc)${NC}"
            fi
            ;;
        logs)
            local lines="${3:-30}"
            journalctl -u "$service" -n "$lines" --no-pager 2>&1
            ;;
        *)
            echo -e "${RED}Error: Aksi tidak dikenal: $action${NC}"
            show_help
            exit 1
            ;;
    esac
}

# ==================== MAIN ====================

if [[ $EUID -ne 0 ]]; then
    echo -e "${YELLOW}⚠ Sebaiknya jalankan dengan sudo untuk hasil maksimal${NC}"
fi

case "${1:-help}" in
    list)
        list_services
        ;;
    status|start|stop|restart|enable|disable|logs)
        service_action "$1" "$2" "$3"
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo -e "${RED}Error: Perintah tidak dikenal: $1${NC}"
        show_help
        exit 1
        ;;
esac
