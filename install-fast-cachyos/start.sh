#!/usr/bin/env bash
#
# start.sh — Tải bộ cài nhanh CachyOS về /root rồi mở cachyos-installer
#
# Cách dùng (chạy TỪ LIVE ISO của CachyOS):
#   curl -fsSL https://raw.githubusercontent.com/nhndev110/linux-support-kit/main/install-fast-cachyos/start.sh | sudo bash
#
# Script chỉ làm phần "dọn đường": tải settings.json + post-install.sh +
# configure-system.sh vào /root rồi gọi cachyos-installer. Toàn bộ việc cài đặt
# và cấu hình do 3 file kia lo.
#
set -euo pipefail

BASE=https://raw.githubusercontent.com/nhndev110/linux-support-kit/main/install-fast-cachyos
FILES=(settings.json post-install.sh configure-system.sh)
DEST=/root

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info() { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()   { echo -e "${GREEN}[OK]${NC}   $*"; }
warn() { echo -e "${YELLOW}[!]${NC}    $*"; }
err()  { echo -e "${RED}[LỖI]${NC}  $*" >&2; }

[[ $EUID -eq 0 ]] || { err "Cần chạy bằng root — thêm 'sudo'."; exit 1; }

command -v curl &>/dev/null || { err "Không có curl trên live ISO."; exit 1; }
command -v cachyos-installer &>/dev/null \
    || { err "Không thấy cachyos-installer — script này chỉ chạy từ live ISO CachyOS."; exit 1; }

# Xóa log của lần chạy trước để không đọc nhầm kết quả cũ
rm -f /tmp/post-install.log

cd "$DEST"
for f in "${FILES[@]}"; do
    info "Tải $f..."
    curl -fsSLo "$f" "$BASE/$f" || { err "Không tải được $f"; exit 1; }
done
chmod +x post-install.sh configure-system.sh
ok "Đã tải xong vào $DEST:"
ls -l "${FILES[@]}"

echo
info "Mở cachyos-installer — chọn 'Load config' và trỏ tới $DEST/settings.json"
cachyos-installer

# Installer chạy xong (đã gồm cả post-install.sh) → khởi động lại vào hệ thống mới
echo
warn "Máy sẽ khởi động lại sau 10 giây... (Ctrl+C để hủy)"
for i in $(seq 10 -1 1); do
    printf "\r${YELLOW}[!]${NC}    Reboot sau %2d giây... " "$i"
    sleep 1
done
echo
reboot
