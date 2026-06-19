#!/bin/bash
# MiniServer SDCard Mount Script
# Mengkonfigurasi SDCard sebagai storage utama

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SDCARD_MOUNT="/mnt/sdcard"
LOG_FILE="/tmp/miniserver-mount.log"

log_info() { echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1" | tee -a "$LOG_FILE"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"; }

detect_sdcard() {
    log_info "Mendeteksi SDCard..."
    
    local devices=()
    
    # Cari device yang mungkin adalah SDCard
    for dev in /dev/mmcblk1 /dev/mmcblk2; do
        if [[ -b "$dev" ]]; then
            local dev_path="/sys/block/$(basename $dev)"
            local removable=$(cat "$dev_path/removable" 2>/dev/null || echo "0")
            if [[ "$removable" == "1" ]]; then
                devices+=("$dev")
            fi
        fi
    done
    
    # Fallback: cari device yg bukan system disk
    if [[ ${#devices[@]} -eq 0 ]]; then
        for dev in /dev/sda /dev/sdb /dev/sdc /dev/mmcblk1 /dev/mmcblk2; do
            if [[ -b "$dev" ]]; then
                local root_dev=$(findmnt -n -o SOURCE / | sed 's/[0-9]*$//' | sed 's/p[0-9]*$//')
                if [[ "$dev" != "$root_dev" ]]; then
                    devices+=("$dev")
                fi
            fi
        done
    fi
    
    if [[ ${#devices[@]} -eq 0 ]]; then
        log_error "SDCard tidak terdeteksi!"
        log_info "Device yang tersedia:"
        lsblk -d -o NAME,SIZE,TYPE,MOUNTPOINT | grep -E "mmc|sd"
        echo ""
        read -p "Masukkan device SDCard secara manual (contoh: mmcblk1): " manual_dev
        manual_dev=$(echo "$manual_dev" | xargs)
        [[ "$manual_dev" != /dev/* ]] && manual_dev="/dev/$manual_dev"
        if [[ -b "$manual_dev" ]]; then
            devices=("$manual_dev")
        else
            log_error "Device $manual_dev tidak ditemukan"
            exit 1
        fi
    fi
    
    SDCARD_DEV="${devices[0]}"
    log_success "SDCard terdeteksi: ${SDCARD_DEV}"
}

prepare_partition() {
    local dev="$1"
    local part="${dev}p1"
    
    if [[ "$dev" == /dev/sd* ]]; then
        part="${dev}1"
    fi
    
    if [[ ! -b "$part" ]]; then
        log_info "Membuat partisi pada ${dev}..."
        echo -e "o\nn\np\n1\n\n\nw" | fdisk "$dev" 2>&1 | tee -a "$LOG_FILE"
        sleep 2
        partprobe "$dev" 2>/dev/null || true
        sleep 1
    fi
    
    # Format jika belum ext4
    local fstype=$(blkid -s TYPE -o value "$part" 2>/dev/null || echo "")
    if [[ "$fstype" != "ext4" ]]; then
        log_info "Memformat ${part} sebagai ext4..."
        mkfs.ext4 -F "$part" 2>&1 | tee -a "$LOG_FILE"
    fi
    
    echo "$part"
}

mount_sdcard() {
    local part="$1"
    
    mkdir -p "$SDCARD_MOUNT"
    
    if mountpoint -q "$SDCARD_MOUNT"; then
        log_info "SDCard sudah ter-mount di ${SDCARD_MOUNT}"
        return 0
    fi
    
    log_info "Mounting ${part} ke ${SDCARD_MOUNT}..."
    mount "$part" "$SDCARD_MOUNT" 2>&1 | tee -a "$LOG_FILE"
    
    if mountpoint -q "$SDCARD_MOUNT"; then
        log_success "SDCard berhasil di-mount"
    else
        log_error "Gagal mount SDCard"
        exit 1
    fi
}

create_directories() {
    log_info "Membuat direktori di SDCard..."
    
    local dirs=(
        "www"
        "log"
        "cache"
        "home"
        "docker"
        "squid/cache"
        "squid/logs"
        "mysql"
        "redis"
        "downloads"
        "backup"
        "My Document"
        "My Music"
        "My Pictures"
        "My Video"
    )
    
    for dir in "${dirs[@]}"; do
        mkdir -p "$SDCARD_MOUNT/$dir"
    done
    
    log_success "Direktori dibuat"
}

create_symlinks() {
    log_info "Membuat symlink..."
    
    local links=(
        "/var/www:$SDCARD_MOUNT/www"
        "/var/log:$SDCARD_MOUNT/log"
        "/var/cache:$SDCARD_MOUNT/cache"
        "/home:$SDCARD_MOUNT/home"
    )
    
    for link in "${links[@]}"; do
        local target="${link%%:*}"
        local source="${link##*:}"
        
        # Backup jika ada
        if [[ -d "$target" ]] && [[ ! -L "$target" ]]; then
            if [[ -n "$(ls -A "$target" 2>/dev/null)" ]]; then
                log_info "Backup ${target} ke ${target}.backup..."
                cp -a "$target" "${target}.backup" 2>/dev/null || true
            fi
            rm -rf "$target"
        fi
        
        if [[ ! -L "$target" ]]; then
            ln -sf "$source" "$target"
            log_info "  ${target} -> ${source}"
        fi
    done
    
    # Symlink khusus untuk landing page
    if [[ ! -L "/var/www/html/rootfs" ]]; then
        ln -sf / "/var/www/html/rootfs" 2>/dev/null || true
    fi
    
    # Symlink untuk file manager
    if [[ ! -L "/var/www/html/My Document" ]]; then
        ln -sf "$SDCARD_MOUNT/My Document" "/var/www/html/My Document" 2>/dev/null || true
    fi
    if [[ ! -L "/var/www/html/My Music" ]]; then
        ln -sf "$SDCARD_MOUNT/My Music" "/var/www/html/My Music" 2>/dev/null || true
    fi
    if [[ ! -L "/var/www/html/My Pictures" ]]; then
        ln -sf "$SDCARD_MOUNT/My Pictures" "/var/www/html/My Pictures" 2>/dev/null || true
    fi
    if [[ ! -L "/var/www/html/My Video" ]]; then
        ln -sf "$SDCARD_MOUNT/My Video" "/var/www/html/My Video" 2>/dev/null || true
    fi
    
    log_success "Symlink dibuat"
}

update_fstab() {
    local part="$1"
    
    local uuid=$(blkid -s UUID -o value "$part" 2>/dev/null)
    if [[ -z "$uuid" ]]; then
        log_warn "Tidak dapat memperoleh UUID, gunakan device path"
        if ! grep -q "$SDCARD_MOUNT" /etc/fstab; then
            echo "$part $SDCARD_MOUNT ext4 defaults,noatime,nodiratime,errors=remount-ro 0 2" >> /etc/fstab
            log_info "Menambahkan $part ke /etc/fstab"
        fi
    else
        if ! grep -q "$uuid" /etc/fstab; then
            echo "UUID=$uuid $SDCARD_MOUNT ext4 defaults,noatime,nodiratime,errors=remount-ro 0 2" >> /etc/fstab
            log_info "Menambahkan UUID=$uuid ke /etc/fstab"
        fi
    fi
    
    log_success "/etc/fstab diupdate"
}

optimize_sdcard() {
    log_info "Mengoptimasi SDCard..."
    
    # Disable journaling for better performance on SDCard
    local part=$(findmnt -n -o SOURCE "$SDCARD_MOUNT")
    if [[ -n "$part" ]]; then
        tune2fs -o journal_data_writeback "$part" 2>/dev/null || true
        tune2fs -O ^has_journal "$part" 2>/dev/null || true
    fi
    
    # Set noatime untuk mount
    mount -o remount,noatime,nodiratime "$SDCARD_MOUNT" 2>/dev/null || true
    
    # Set sysctl untuk better IO
    sysctl -w vm.dirty_ratio=10 2>/dev/null || true
    sysctl -w vm.dirty_background_ratio=5 2>/dev/null || true
    sysctl -w vm.vfs_cache_pressure=50 2>/dev/null || true
    
    log_success "Optimasi selesai"
}

show_status() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  STATUS SDCARD${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    
    echo -e "Device: ${YELLOW}$SDCARD_DEV${NC}"
    echo -e "Mount: ${YELLOW}$SDCARD_MOUNT${NC}"
    echo ""
    
    if mountpoint -q "$SDCARD_MOUNT"; then
        echo -e "${GREEN}✓ SDCard ter-mount${NC}"
        echo ""
        df -h "$SDCARD_MOUNT" | tail -1 | awk '{print "Size: " $2 "\nUsed: " $3 "\nAvail: " $4 "\nUse%: " $5}'
    else
        echo -e "${RED}✗ SDCard belum ter-mount${NC}"
    fi
    
    echo ""
    echo -e "Symlinks:"
    for link in /var/www /var/log /var/cache /home; do
        if [[ -L "$link" ]]; then
            echo -e "  ${GREEN}✓${NC} $link -> $(readlink $link)"
        elif [[ -d "$link" ]]; then
            echo -e "  ${YELLOW}○${NC} $link (local)"
        else
            echo -e "  ${RED}✗${NC} $link (missing)"
        fi
    done
}

# ==================== MAIN ====================

# Cek root
if [[ $EUID -ne 0 ]]; then
    log_error "Script harus dijalankan sebagai root (sudo)"
    exit 1
fi

> "$LOG_FILE"

echo ""
echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
echo -e "${BLUE}║    SDCard Mount & Setup Script      ║${NC}"
echo -e "${BLUE}║      MiniServer for Armbian         ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
echo ""

case "${1:-mount}" in
    mount)
        detect_sdcard
        local part=$(prepare_partition "$SDCARD_DEV")
        mount_sdcard "$part"
        create_directories
        create_symlinks
        update_fstab "$part"
        optimize_sdcard
        show_status
        log_success "SDCard siap digunakan sebagai storage utama"
        ;;
    status)
        show_status
        ;;
    unmount|umount)
        log_info "Unmounting SDCard..."
        umount "$SDCARD_MOUNT" 2>&1 | tee -a "$LOG_FILE"
        log_success "SDCard di-unmount"
        ;;
    format)
        detect_sdcard
        log_warn "Akan memformat $SDCARD_DEV! Data akan hilang!"
        read -p "Lanjutkan? (y/N): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            local part="${SDCARD_DEV}p1"
            if [[ "$SDCARD_DEV" == /dev/sd* ]]; then
                part="${SDCARD_DEV}1"
            fi
            umount "$part" 2>/dev/null || true
            echo -e "o\nn\np\n1\n\n\nw" | fdisk "$SDCARD_DEV"
            sleep 1
            mkfs.ext4 -F "$part"
            log_success "SDCard diformat"
        fi
        ;;
    help|--help|-h)
        echo "Usage: $0 {mount|status|unmount|format|help}"
        echo ""
        echo "  mount   - Deteksi, partisi, format, mount, dan setup SDCard (default)"
        echo "  status  - Tampilkan status SDCard"
        echo "  unmount - Unmount SDCard"
        echo "  format  - Format SDCard (HATI-HATI: semua data hilang)"
        echo "  help    - Tampilkan bantuan ini"
        ;;
esac
