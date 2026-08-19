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
# Chép log vào hệ đích NGAY TRONG TRAP, trước khi umount: đặt ở cuối script thì
# hễ chết giữa chừng là mất sạch log (log gốc nằm ở /tmp của live ISO, reboot là bay).
cleanup() {
    sync
    cp "$LOG" "$TARGET/root/post-install.log" 2>/dev/null || true
    umount -R "$TARGET" 2>/dev/null || true
}
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

SCRIPT_DST="$U_HOME/configure-system.sh"
install -m 755 -o "$U_UID" -g "$U_GID" "$INNER" "$TARGET$SCRIPT_DST"
echo "Đã chép script cấu hình vào $SCRIPT_DST"

################ D. SERVICE CHẠY LẦN ĐẦU ################
# Chạy TRƯỚC display-manager nên không phải đăng nhập: service chiếm tty1 và giữ
# SDDM lại cho tới khi cấu hình xong (Type=oneshot mới có ràng buộc "xong" này).
# Chỉ chạy một lần: script tự xóa mình khi mọi bước OK -> ConditionPathExists sai
# ở lần boot sau. Nếu script chết giữa chừng thì file còn -> boot lại là chạy lại.
cat > "$TARGET/etc/systemd/system/configure-system.service" <<EOF
[Unit]
Description=Cau hinh lan dau sau khi cai dat
ConditionPathExists=$SCRIPT_DST
Wants=network-online.target
After=network-online.target systemd-user-sessions.service
Before=display-manager.service
# Bắt buộc: chỉ 'tty-force' thôi thì agetty vẫn giữ tty1 và vẽ đè lên script,
# khoảng 2 giây sau khi service chạy là màn hình nhảy về 'tty1 login:'.
# Conflicts bảo systemd DỪNG getty@tty1 trong lúc service chạy, và tự bật lại sau.
Conflicts=getty@tty1.service
After=getty@tty1.service

[Service]
Type=oneshot
RemainAfterExit=yes
User=$USER_NAME
WorkingDirectory=$U_HOME
# systemd không tự đặt HOME/USER như lúc login; thiếu thì .xinitrc và config KDE
# sẽ bị ghi sai chỗ. TERM=linux để phần in màu hiển thị đúng trên tty.
Environment=HOME=$U_HOME USER=$USER_NAME TERM=linux
ExecStart=/bin/bash $SCRIPT_DST
# tty-force: giành tty1 kể cả khi getty đang giữ. Thiếu stdin thì mọi lệnh 'read'
# nhận EOF và script chạy tuột qua hết phần hỏi cấu hình.
StandardInput=tty-force
StandardOutput=tty
StandardError=tty
TTYPath=/dev/tty1
TTYReset=yes
TTYVHangup=yes
# Không đặt timeout: pacman -Syu + build AUR rất lâu, và script còn ngồi chờ nhập
TimeoutStartSec=infinity

[Install]
WantedBy=multi-user.target
EOF
chmod 644 "$TARGET/etc/systemd/system/configure-system.service"

# Enable bằng symlink tay — tương đương 'systemctl enable', khỏi cần chroot
mkdir -p "$TARGET/etc/systemd/system/multi-user.target.wants"
ln -sf ../configure-system.service \
    "$TARGET/etc/systemd/system/multi-user.target.wants/configure-system.service"
echo "Đã bật configure-system.service (chạy ở lần khởi động đầu tiên)"

# Cho phép sudo không cần mật khẩu, CHỈ để script cấu hình chạy suôn một mạch.
# configure-system.sh tự xóa file này ở bước cuối khi mọi bước đều OK.
SUDOERS_DROPIN="$TARGET/etc/sudoers.d/99-configure-system"
mkdir -p "$TARGET/etc/sudoers.d"
printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$USER_NAME" > "$SUDOERS_DROPIN"
chmod 440 "$SUDOERS_DROPIN"
# Sudoers sai cú pháp là mất luôn quyền sudo của cả máy — kiểm tra trước khi để lại.
# Không qua được thì chỉ xóa file và cảnh báo: cùng lắm là phải nhập mật khẩu tay,
# không đáng để làm hỏng cả lần cài máy.
if command -v visudo &>/dev/null && ! visudo -cf "$SUDOERS_DROPIN"; then
    rm -f "$SUDOERS_DROPIN"
    echo "CẢNH BÁO: sudoers drop-in không qua visudo -c, đã xóa (sẽ phải nhập mật khẩu tay)"
else
    echo "Đã cấp NOPASSWD tạm thời cho '$USER_NAME'"
fi

################ HẬU KỲ ################
# Log do trap cleanup chép sang $TARGET/root/post-install.log
echo "=== Xong ==="