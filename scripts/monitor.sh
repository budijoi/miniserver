#!/bin/bash
# MiniServer System Monitor
# Menampilkan informasi sistem secara real-time

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

BOLD='\033[1m'

get_cpu_temp() {
    local temp=0
    for path in /sys/class/thermal/thermal_zone*/temp /sys/class/hwmon/hwmon*/temp1_input; do
        if [[ -f "$path" ]]; then
            local t=$(cat "$path" 2>/dev/null)
            if [[ "$t" -gt 0 ]]; then
                temp=$t
                break
            fi
        fi
    done
    echo "scale=1; $temp / 1000" | bc 2>/dev/null || echo "0"
}

get_cpu_usage() {
    local cpu1=$(grep '^cpu ' /proc/stat | awk '{print $2+$3+$4+$5+$6+$7+$8}')
    local idle1=$(grep '^cpu ' /proc/stat | awk '{print $5}')
    sleep 0.5
    local cpu2=$(grep '^cpu ' /proc/stat | awk '{print $2+$3+$4+$5+$6+$7+$8}')
    local idle2=$(grep '^cpu ' /proc/stat | awk '{print $5}')
    local total=$((cpu2 - cpu1))
    local idle=$((idle2 - idle1))
    if [[ $total -gt 0 ]]; then
        echo "scale=1; (1 - $idle / $total) * 100" | bc 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

format_bytes() {
    local bytes=$1
    if [[ $bytes -ge 1073741824 ]]; then
        echo "$(echo "scale=2; $bytes / 1073741824" | bc) GB"
    elif [[ $bytes -ge 1048576 ]]; then
        echo "$(echo "scale=2; $bytes / 1048576" | bc) MB"
    elif [[ $bytes -ge 1024 ]]; then
        echo "$(echo "scale=2; $bytes / 1024" | bc) KB"
    else
        echo "${bytes} B"
    fi
}

format_uptime() {
    local seconds=$(cat /proc/uptime 2>/dev/null | awk '{print int($1)}')
    local days=$((seconds / 86400))
    local hours=$(( (seconds % 86400) / 3600 ))
    local mins=$(( (seconds % 3600) / 60 ))
    echo "${days}d ${hours}h ${mins}m"
}

get_network_rxtx() {
    local rx=0
    local tx=0
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*(eth|wlan|en|wl)[^:]+: ]]; then
            local data=($line)
            rx=$((rx + ${data[1]}))
            tx=$((tx + ${data[9]}))
        fi
    done < /proc/net/dev
    echo "$rx $tx"
}

get_zram_info() {
    local total=0
    local used=0
    for zram in /sys/block/zram*; do
        if [[ -d "$zram" ]]; then
            local name=$(basename "$zram")
            local disksize=$(cat "$zram/disksize" 2>/dev/null || echo 0)
            local mmstat=$(cat "$zram/mm_stat" 2>/dev/null || echo "0 0")
            local mma=($mmstat)
            total=$((total + disksize))
            used=$((used + ${mma[1]:-0}))
        fi
    done
    echo "$total $used"
}

show_header() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║              MiniServer System Monitor                     ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo -e "${BOLD}Hostname:${NC} $(hostname)  |  ${BOLD}Uptime:${NC} $(format_uptime)  |  ${BOLD}Date:${NC} $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
}

show_cpu() {
    local temp=$(get_cpu_temp)
    local usage=$(get_cpu_usage)
    local load=$(cat /proc/loadavg | awk '{print $1, $2, $3}')
    
    echo -e "${BOLD}CPU${NC}"
    echo -e "  ${BLUE}Temp:${NC}      ${temp}°C"
    echo -e "  ${BLUE}Usage:${NC}     ${usage}%"
    echo -e "  ${BLUE}Load:${NC}      ${load}"
    
    # Progress bar
    local bar_width=30
    local filled=$(echo "scale=0; $usage * $bar_width / 100" | bc 2>/dev/null || echo 0)
    local empty=$((bar_width - filled))
    printf "  ["
    for ((i=0; i<filled; i++)); do printf "${GREEN}#${NC}"; done
    for ((i=0; i<empty; i++)); do printf "${YELLOW}-${NC}"; done
    printf "] ${usage}%%\n"
    echo ""
}

show_ram() {
    local total=$(free -b | awk '/^Mem:/{print $2}')
    local used=$(free -b | awk '/^Mem:/{print $3}')
    local avail=$(free -b | awk '/^Mem:/{print $7}')
    local percent=$(echo "scale=1; $used * 100 / $total" | bc 2>/dev/null || echo 0)
    
    echo -e "${BOLD}RAM${NC}"
    echo -e "  ${BLUE}Total:${NC}     $(format_bytes $total)"
    echo -e "  ${BLUE}Used:${NC}      $(format_bytes $used)"
    echo -e "  ${BLUE}Available:${NC} $(format_bytes $avail)"
    
    local bar_width=30
    local filled=$(echo "scale=0; $percent * $bar_width / 100" | bc 2>/dev/null || echo 0)
    local empty=$((bar_width - filled))
    printf "  ["
    for ((i=0; i<filled; i++)); do printf "${YELLOW}#${NC}"; done
    for ((i=0; i<empty; i++)); do printf "${YELLOW}-${NC}"; done
    printf "] ${percent}%%\n"
    echo ""
}

show_storage() {
    echo -e "${BOLD}Storage${NC}"
    for mount in / /mnt/sdcard; do
        if [[ -d "$mount" ]]; then
            local total=$(df -B1 "$mount" 2>/dev/null | tail -1 | awk '{print $2}')
            local used=$(df -B1 "$mount" 2>/dev/null | tail -1 | awk '{print $3}')
            local avail=$(df -B1 "$mount" 2>/dev/null | tail -1 | awk '{print $4}')
            local pct=$(df -h "$mount" 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%')
            
            local label="Internal"
            [[ "$mount" == "/mnt/sdcard" ]] && label="SDCard"
            
            if [[ -n "$total" ]]; then
                echo -e "  ${BLUE}${label}:${NC}    $(format_bytes $total) total, $(format_bytes $used) used, $(format_bytes $avail) free (${pct}%%)"
                
                local bar_width=30
                local filled=$(echo "scale=0; $pct * $bar_width / 100" | bc 2>/dev/null || echo 0)
                local empty=$((bar_width - filled))
                printf "  ["
                for ((i=0; i<filled; i++)); do printf "${GREEN}#${NC}"; done
                for ((i=0; i<empty; i++)); do printf "${GREEN}-${NC}"; done
                printf "] ${pct}%%\n"
            fi
        fi
    done
    echo ""
}

show_swap_zram() {
    echo -e "${BOLD}SWAP / ZRAM${NC}"
    
    # SWAP
    local swap_total=$(free -b | awk '/^Swap:/{print $2}')
    local swap_used=$(free -b | awk '/^Swap:/{print $3}')
    if [[ $swap_total -gt 0 ]]; then
        local swap_pct=$(echo "scale=1; $swap_used * 100 / $swap_total" | bc 2>/dev/null || echo 0)
        echo -e "  ${BLUE}SWAP:${NC}     $(format_bytes $swap_total) total, $(format_bytes $swap_used) used (${swap_pct}%%)"
    fi
    
    # ZRAM
    local zram_data=($(get_zram_info))
    local zram_total=${zram_data[0]}
    local zram_used=${zram_data[1]}
    if [[ $zram_total -gt 0 ]]; then
        local zram_pct=$(echo "scale=1; $zram_used * 100 / $zram_total" | bc 2>/dev/null || echo 0)
        echo -e "  ${BLUE}ZRAM:${NC}     $(format_bytes $zram_total) total, $(format_bytes $zram_used) used (${zram_pct}%%)"
    fi
    
    if [[ $swap_total -eq 0 && $zram_total -eq 0 ]]; then
        echo -e "  ${YELLOW}Tidak ada SWAP/ZRAM aktif${NC}"
    fi
    echo ""
}

show_network() {
    local net=($(get_network_rxtx))
    local rx=${net[0]}
    local tx=${net[1]}
    
    echo -e "${BOLD}Network${NC}"
    echo -e "  ${BLUE}RX:${NC}        $(format_bytes $rx)"
    echo -e "  ${BLUE}TX:${NC}        $(format_bytes $tx)"
    echo ""
    
    echo -e "  ${BLUE}Interfaces:${NC}"
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*(eth|wlan|en|wl|br)[^:]+: ]]; then
            local name=$(echo "$line" | awk -F: '{print $1}' | tr -d ' ')
            local data=($line)
            local irx=${data[1]}
            local itx=${data[9]}
            echo -e "    ${GREEN}$name:${NC} RX=$(format_bytes $irx) TX=$(format_bytes $itx)"
        fi
    done < /proc/net/dev
    echo ""
}

show_top_processes() {
    echo -e "${BOLD}Top 5 Proses by CPU${NC}"
    ps aux --sort=-%cpu 2>/dev/null | head -6 | awk '{printf "  %-5s %-5s %-5s %s\n", $2, $3"%", $4"%", $11}'
    echo ""
}

show_services_status() {
    echo -e "${BOLD}Service Status${NC}"
    local services=("nginx" "apache2" "php8.2-fpm" "squid" "mariadb" "docker")
    for svc in "${services[@]}"; do
        local status=$(systemctl is-active "$svc" 2>/dev/null || echo "not_found")
        if [[ "$status" == "active" ]]; then
            echo -e "  ${GREEN}●${NC} $svc"
        elif [[ "$status" == "inactive" ]]; then
            echo -e "  ${RED}○${NC} $svc"
        fi
    done
    echo ""
}

# ==================== MAIN ====================

if [[ "$1" == "--once" || "$1" == "-1" ]]; then
    show_header
    show_cpu
    show_ram
    show_storage
    show_swap_zram
    show_network
    show_top_processes
    show_services_status
elif [[ "$1" == "--interval" || "$1" == "-i" ]]; then
    interval="${2:-2}"
    while true; do
        show_header
        show_cpu
        show_ram
        show_storage
        show_swap_zram
        show_network
        show_top_processes
        show_services_status
        echo -e "${YELLOW}Press Ctrl+C to exit (refreshes every ${interval}s)${NC}"
        sleep "$interval"
    done
else
    echo "MiniServer System Monitor"
    echo ""
    echo "Usage:"
    echo "  $0 --once        Tampilkan informasi sekali"
    echo "  $0 --interval N  Tampilkan setiap N detik (default: 2)"
    echo ""
    echo "Example:"
    echo "  $0 --once"
    echo "  $0 -i 5"
fi
