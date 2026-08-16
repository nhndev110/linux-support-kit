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
# Không chạy configure-system.sh trong arch-chroot: nó cần systemd đang chạy
# (systemctl, nmcli), cần mạng và cần paru chạy dưới user thường. Ở đây chỉ chép
# nó vào home của user trong hệ thống đã cài, để chạy sau khi boot.
INNER=/root/configure-system.sh

[[ -f $INNER ]] || { echo "LỖI: không thấy $INNER"; exit 1; }

# Lấy user thường: ưu tiên settings.json, không có thì lấy UID >= 1000 đầu tiên
USER_NAME=$(awk -F'"' '/"user_name"/{print $4}' /root/settings.json 2>/dev/null || true)
[[ -z ${USER_NAME:-} ]] && \
    USER_NAME=$(awk -F: '$3>=1000 && $3<65534 {print $1; exit}' "$TARGET/etc/passwd")
[[ -n ${USER_NAME:-} ]] || { echo "LỖI: không xác định được user thường"; exit 1; }

# UID/GID/home đọc từ /etc/passwd của HỆ ĐÍCH, không phải của live ISO
PW_LINE=$(grep "^${USER_NAME}:" "$TARGET/etc/passwd") \
    || { echo "LỖI: không thấy user '$USER_NAME' trong $TARGET/etc/passwd"; exit 1; }
IFS=: read -r _ _ U_UID U_GID _ U_HOME _ <<<"$PW_LINE"
echo "user=$USER_NAME uid=$U_UID gid=$U_GID home=$U_HOME"

[[ -d $TARGET$U_HOME ]] || { echo "LỖI: không thấy home $U_HOME trong hệ đích"; exit 1; }

install -m 755 -o "$U_UID" -g "$U_GID" "$INNER" "$TARGET$U_HOME/configure-system.sh"
echo "Đã chép script cấu hình vào $U_HOME/configure-system.sh"

################ HẬU KỲ ################
cp "$LOG" "$TARGET/root/post-install.log"
echo "=== Xong ==="