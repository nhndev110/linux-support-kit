#!/bin/bash
# post-install.sh — chạy sau cachyos-installer, TỪ live ISO
set -euo pipefail

################ A. CHUẨN BỊ ################
LOG=/tmp/post-install.log
exec > >(tee -a "$LOG") 2>&1
echo "=== Post-install $(date -Is) ==="

TARGET=/mnt

DISK=$(awk -F'"' '/"device"/{print $4}' /root/settings.json 2>/dev/null || true)
[[ -z ${DISK:-} ]] && DISK=$(lsblk -dpno NAME,TYPE | awk '$2=="disk"{print $1; exit}')

udevadm settle
partprobe "$DISK" || true

ROOT_PART=$(lsblk -pnro NAME,FSTYPE "$DISK" | awk '$2~/^(btrfs|ext4|xfs|f2fs)$/{print $1; exit}')
BOOT_PART=$(lsblk -pnro NAME,FSTYPE "$DISK" | awk '$2=="vfat"{print $1; exit}')
ROOT_FS=$(lsblk -pnro FSTYPE "$ROOT_PART")
echo "disk=$DISK root=$ROOT_PART ($ROOT_FS) boot=$BOOT_PART"
[[ -n $ROOT_PART && -n $BOOT_PART ]] || { echo "LỖI: không tìm thấy phân vùng"; exit 1; }

################ B. MOUNT ################
cleanup() { sync; umount -R "$TARGET" 2>/dev/null || true; }
trap cleanup EXIT

if [[ $ROOT_FS == btrfs ]]; then
    mount -o subvol=/@     "$ROOT_PART" "$TARGET"
    mount -o subvol=/@home "$ROOT_PART" "$TARGET/home"
else
    mount "$ROOT_PART" "$TARGET"
fi
mount "$BOOT_PART" "$TARGET/boot"

[[ -f $TARGET/etc/os-release && -d $TARGET/usr/lib/systemd ]] \
    || { echo "LỖI: $TARGET không phải hệ thống đã cài"; exit 1; }
[[ -e $TARGET/@ ]] && { echo "LỖI: quên subvol=/@"; exit 1; }
echo "Hostname đích: $(cat "$TARGET/etc/hostname" 2>/dev/null || echo '?')"

################ C. RUỘT ################
# INNER=/root/configure-system.sh

# [[ -f $INNER ]] || { echo "LỖI: không thấy $INNER"; exit 1; }

# install -m 700 "$INNER" "$TARGET/root/configure-system.sh"
# arch-chroot "$TARGET" /bin/bash /root/configure-system.sh
# rm -f "$TARGET/root/configure-system.sh"

################ HẬU KỲ ################
cp "$LOG" "$TARGET/root/post-install.log"
echo "=== Xong ==="