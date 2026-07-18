#!/usr/bin/env bash
#
# setup-xrdp.sh — Tự động cài đặt & cấu hình XRDP trên Arch Linux (dùng paru)
#
# Cách dùng:
#   chmod +x setup-xrdp.sh
#   ./setup-xrdp.sh          <-- chạy bằng USER THƯỜNG, KHÔNG dùng sudo/root
#
# Lý do không chạy bằng root: paru build gói AUR (xrdp, xorgxrdp) và từ chối
# chạy dưới quyền root. Script sẽ tự gọi sudo ở các bước cần quyền hệ thống.
#

set -uo pipefail

# ---------- Hàm log có màu ----------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info() { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()   { echo -e "${GREEN}[OK]${NC}   $*"; }
warn() { echo -e "${YELLOW}[!]${NC}    $*"; }
err()  { echo -e "${RED}[LỖI]${NC}  $*" >&2; }

# ---------- Kiểm tra điều kiện ----------
if [[ $EUID -eq 0 ]]; then
  err "Đừng chạy script này bằng root/sudo. Hãy chạy bằng user thường."
  exit 1
fi

if ! command -v paru &>/dev/null; then
  warn "Không tìm thấy 'paru' — tiến hành cài đặt..."
  sudo pacman -S --noconfirm paru || sudo pacman -Sy --noconfirm paru || {
    err "Không cài được paru."; exit 1;
  }
  command -v paru &>/dev/null && ok "Đã cài paru." || { err "Không tìm thấy lệnh paru."; exit 1; }
fi

# Xin quyền sudo ngay từ đầu và giữ "sống" trong suốt quá trình
info "Cần quyền sudo để cấu hình hệ thống — nhập mật khẩu nếu được hỏi:"
sudo -v || { err "Không lấy được quyền sudo."; exit 1; }
( while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) &
KEEPALIVE_PID=$!
trap 'kill "$KEEPALIVE_PID" 2>/dev/null' EXIT

# ############################################################
# PHẦN A: THU THẬP THÔNG TIN TỪ NGƯỜI DÙNG (hỏi hết một lượt)
# ############################################################
echo
info "===== Thu thập cấu hình (sẽ không hỏi gì thêm sau bước này) ====="

# ---------- A1: Port xrdp ----------
read -rp "Nhập port cho xrdp [Enter = giữ mặc định 3389]: " XRDP_PORT
XRDP_PORT=${XRDP_PORT:-3389}

# ---------- A2: Chọn Desktop Environment ----------
echo
echo "Chọn Desktop Environment cho phiên XRDP:"
# Menu read (không dùng 'select') vì 'select' khi nhấn Enter chỉ in lại menu,
# không hỗ trợ "Enter = giá trị mặc định".
echo "  1) KDE Plasma (X11)   (mặc định)"
echo "  2) GNOME"
echo "  3) XFCE"
echo "  4) Cosmic"
echo "  5) Tự nhập lệnh khác"
SESSION_CMD=""
while true; do
  read -rp "Nhập số lựa chọn [Enter = 1 (KDE Plasma)]: " DE_CHOICE
  DE_CHOICE="${DE_CHOICE:-1}"
  case "$DE_CHOICE" in
    1) SESSION_CMD="exec startplasma-x11"; break;;
    2) SESSION_CMD="exec gnome-session";   break;;
    3) SESSION_CMD="exec startxfce4";      break;;
    4) SESSION_CMD="exec start-cosmic";    break;;
    5) read -rp "Nhập lệnh exec (vd: exec i3): " SESSION_CMD
       if [[ -z "$SESSION_CMD" ]]; then warn "Lệnh trống — thử lại."; continue; fi
       break;;
    *) warn "Lựa chọn không hợp lệ, thử lại.";;
  esac
done

# ---------- A3: IP tĩnh (tùy chọn) ----------
echo
info "Cấu hình mạng hiện tại:"
# Địa chỉ IP + interface (bỏ qua loopback)
while IFS= read -r line; do
  echo "  IP       : $line"
done < <(ip -brief -4 addr show scope global 2>/dev/null | awk '$1!="lo"{print $1" -> "$3}')
# Gateway mặc định
CUR_GW="$(ip route show default 2>/dev/null | awk '/default/{print $3; exit}')"
echo "  Gateway  : ${CUR_GW:-(không có)}"
# DNS hiện tại (ưu tiên resolvectl, sau đó nmcli, cuối cùng /etc/resolv.conf)
if command -v resolvectl &>/dev/null; then
  CUR_DNS="$(resolvectl dns 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort -u | paste -sd' ')"
fi
[[ -z "${CUR_DNS:-}" ]] && command -v nmcli &>/dev/null && \
  CUR_DNS="$(nmcli -g IP4.DNS device show 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort -u | paste -sd' ')"
[[ -z "${CUR_DNS:-}" ]] && \
  CUR_DNS="$(awk '/^nameserver/{print $2}' /etc/resolv.conf 2>/dev/null | paste -sd' ')"
echo "  DNS      : ${CUR_DNS:-(không có)}"
echo

read -rp "Cấu hình IP tĩnh không? [y/N]: " ANS
STATIC_IP=false
if [[ "${ANS,,}" == "y" ]]; then
  STATIC_IP=true
  
  # Tự lấy connection đang active (gắn với thiết bị thật)
  mapfile -t ACTIVE_CONS < <(nmcli -t -f NAME,DEVICE connection show --active | awk -F: '$2!="" && $2!="lo"{print $1}')

  if [[ ${#ACTIVE_CONS[@]} -eq 0 ]]; then
    err "Không tìm thấy connection nào đang active."
    exit 1
  elif [[ ${#ACTIVE_CONS[@]} -eq 1 ]]; then
    CON="${ACTIVE_CONS[0]}"
    ok "Dùng connection đang active: $CON"
  else
    echo "Có nhiều connection đang active, chọn một:"
    select c in "${ACTIVE_CONS[@]}"; do
      [[ -n "$c" ]] && { CON="$c"; break; } || warn "Lựa chọn không hợp lệ."
    done
  fi
  
  read -rp "Address (chỉ IP, vd 192.168.1.150): " ADDR
  ADDR="${ADDR%/*}/24"
  info "Netmask cố định: 255.255.255.0 (/24) → $ADDR"
  read -rp "Gateway (vd 192.168.1.1): " GW
  # Menu read (không dùng 'select') vì 'select' khi nhấn Enter chỉ in lại menu,
  # không hỗ trợ "Enter = giá trị mặc định".
  echo
  echo "Chọn nhóm DNS:"
  echo "  1) Google      (8.8.8.8 / 8.8.4.4)   (mặc định)"
  echo "  2) Cloudflare  (1.1.1.1 / 1.0.0.1)"
  echo "  3) Viettel     (203.113.131.1 / .2)"
  echo "  4) VNPT        (203.162.4.190 / .191)"
  echo "  5) Tự nhập tay"
  DNS=""; DNS2=""
  while true; do
    read -rp "Nhập số lựa chọn [Enter = 1 (Google)]: " DNS_CHOICE
    DNS_CHOICE="${DNS_CHOICE:-1}"
    case "$DNS_CHOICE" in
      1) DNS="8.8.8.8";       DNS2="8.8.4.4";       break;;
      2) DNS="1.1.1.1";       DNS2="1.0.0.1";       break;;
      3) DNS="203.113.131.1"; DNS2="203.113.131.2"; break;;
      4) DNS="203.162.4.190"; DNS2="203.162.4.191"; break;;
      5) read -rp "Preferred DNS (vd 8.8.8.8): " DNS
         read -rp "Alternate DNS (vd 8.8.4.4) [Enter = bỏ qua]: " DNS2
         break;;
      *) warn "Lựa chọn không hợp lệ, thử lại.";;
    esac
  done
  info "DNS đã chọn: $DNS${DNS2:+ , $DNS2}"
fi

# ---------- A4: Đặt lại mật khẩu cho user + root ----------
echo
read -rp "Đặt lại mật khẩu cho user '$USER' và root? [y/N]: " PW_ANS
SET_PASS=false
if [[ "${PW_ANS,,}" == "y" ]]; then
  SET_PASS=true
  while true; do
    read -rp "Nhập mật khẩu mới: " NEWPASS
    if [[ -z "$NEWPASS" ]]; then
      warn "Mật khẩu trống — thử lại."
    else
      ok "Mật khẩu hợp lệ."
      break
    fi
  done
fi

ok "Đã thu thập xong cấu hình. Bắt đầu cài đặt..."

# ############################################################
# PHẦN B: CÀI ĐẶT & CẤU HÌNH (tự động, không cần tương tác)
# ############################################################

# ============================================================
# Bước 1: Cập nhật hệ thống
# ============================================================
info "Bước 1/11: Cập nhật hệ thống (pacman -Syu)..."
sudo pacman -Syu --noconfirm
ok "Đã cập nhật hệ thống."

# ============================================================
# Bước 2: Cài xrdp và xorgxrdp (qua paru / AUR)
# ============================================================
info "Bước 2/11: Cài đặt xrdp + xorgxrdp..."
paru -S --noconfirm xrdp xorgxrdp
ok "Đã cài xrdp + xorgxrdp."

# ============================================================
# Bước 3: Tạo chứng chỉ (cert) tự động
# ============================================================
info "Bước 3/11: Tạo cert..."
if command -v xrdp-keygen &>/dev/null; then
  sudo xrdp-keygen xrdp auto && ok "Đã tạo cert." || warn "xrdp-keygen lỗi — bỏ qua, service sẽ tự tạo cert."
else
  warn "Không có xrdp-keygen — bỏ qua (service tự tạo cert khi khởi động)."
fi

# ============================================================
# Bước 4: Kích hoạt dịch vụ xrdp
# ============================================================
info "Bước 4/11: Kích hoạt xrdp..."
sudo systemctl enable --now xrdp
ok "xrdp đã được bật."

# ============================================================
# Bước 5: Đổi port trong /etc/xrdp/xrdp.ini
# ============================================================
info "Bước 5/11: Đặt port = ${XRDP_PORT}..."
# Chỉ thay dòng 'port=' ĐẦU TIÊN (nằm trong [Globals]), không đụng port của session
sudo sed -i -E "0,/^port=.*/s//port=${XRDP_PORT}/" /etc/xrdp/xrdp.ini
ok "Đã đặt port = ${XRDP_PORT}."

# ============================================================
# Bước 6: Cấu hình ~/.xinitrc theo Desktop Environment
# ============================================================
info "Bước 6/11: Ghi ~/.xinitrc..."
# Nếu chọn KDE Plasma (X11) thì đảm bảo có kwin-x11 (Arch đã tách kwin-x11/kwin-wayland)
if [[ "$SESSION_CMD" == "exec startplasma-x11" ]]; then
  info "Đảm bảo có kwin-x11 cho phiên Plasma X11..."
  sudo pacman -S --needed --noconfirm kwin-x11
  ok "kwin-x11 đã sẵn sàng."
fi
# Ghi ~/.xinitrc của USER (không dùng sudo — nếu dùng sudo sẽ ghi vào /root)
cat > "$HOME/.xinitrc" <<EOF
#!/bin/sh
# Tắt DPMS và screensaver của X (tránh màn hình đen khi reconnect XRDP)
xset -dpms
xset s off
$SESSION_CMD
EOF
chmod +x "$HOME/.xinitrc"
ok "Đã ghi ~/.xinitrc với: $SESSION_CMD"

# ============================================================
# Bước 7: Khởi động lại xrdp
# ============================================================
info "Bước 7/11: Khởi động lại xrdp..."
sudo systemctl restart xrdp
ok "Đã restart xrdp."

# ============================================================
# Bước 8: Tắt tường lửa ufw
# ============================================================
info "Bước 8/11: Tắt tường lửa..."
if command -v ufw &>/dev/null; then
  sudo ufw disable
  ok "Đã tắt ufw."
else
  warn "Không thấy ufw — bỏ qua. (Có thể bạn chưa cài, không sao cả.)"
fi

# ============================================================
# Bước 9: Cấu hình IP tĩnh (tùy chọn) — qua nmcli (NetworkManager)
# ============================================================
info "Bước 9/11: Cấu hình IP tĩnh..."
if [[ "$STATIC_IP" == true ]]; then
  # Gộp DNS chính + phụ (nếu có)
  DNS_ALL="$DNS"
  [[ -n "${DNS2:-}" ]] && DNS_ALL="$DNS,$DNS2"

  sudo nmcli connection modify "$CON" \
       ipv4.method manual \
       ipv4.addresses "$ADDR" \
       ipv4.gateway "$GW" \
       ipv4.dns "$DNS_ALL"
  sudo nmcli connection up "$CON"
  ok "Đã đặt IP tĩnh cho '$CON' (DNS: $DNS_ALL)."
else
  warn "Bỏ qua cấu hình IP tĩnh."
fi

# ============================================================
# Bước 10: Tắt auto sleep / hibernate (giữ máy luôn thức cho XRDP)
# ============================================================
info "Bước 10/11: Tắt auto sleep / hibernate..."
sudo systemctl mask hibernate.target hybrid-sleep.target sleep.target suspend-then-hibernate.target suspend.target
ok "Đã tắt sleep/hibernate (máy sẽ không tự ngủ)."

# ============================================================
# Bước 11: Tắt khóa màn hình tự động (screen lock)
# ============================================================
info "Bước 11/11: Tắt khóa màn hình tự động..."
# KDE Plasma — tắt qua file cấu hình kscreenlockerrc của user
if [[ "$SESSION_CMD" == "exec startplasma-x11" ]]; then
  mkdir -p "$HOME/.config"
  if command -v kwriteconfig6 &>/dev/null; then
    kwriteconfig6 --file kscreenlockerrc --group Daemon --key Autolock false
    kwriteconfig6 --file kscreenlockerrc --group Daemon --key LockOnResume false
  elif command -v kwriteconfig5 &>/dev/null; then
    kwriteconfig5 --file kscreenlockerrc --group Daemon --key Autolock false
    kwriteconfig5 --file kscreenlockerrc --group Daemon --key LockOnResume false
  else
    # Ghi thẳng file nếu không có kwriteconfig
    cat > "$HOME/.config/kscreenlockerrc" <<EOF
[Daemon]
Autolock=false
LockOnResume=false
EOF
  fi
  ok "Đã tắt khóa màn hình cho Plasma."
# GNOME — tắt qua gsettings
elif [[ "$SESSION_CMD" == "exec gnome-session" ]]; then
  if command -v gsettings &>/dev/null; then
    gsettings set org.gnome.desktop.screensaver lock-enabled false 2>/dev/null
    gsettings set org.gnome.desktop.session idle-delay 0 2>/dev/null
    ok "Đã tắt khóa màn hình cho GNOME."
  else
    warn "Không thấy gsettings — bỏ qua tắt khóa màn hình GNOME."
  fi
else
  # XFCE / Cosmic / lệnh tùy chỉnh — xset s off trong .xinitrc đã xử lý phần lớn
  warn "DE này không có bước tắt lock riêng — đã dựa vào 'xset s off' trong ~/.xinitrc."
fi

# ============================================================
# Đổi mật khẩu cho user + root
# ============================================================
if [[ "$SET_PASS" == true ]]; then
  info "Đổi mật khẩu cho user '$USER' và root..."
  echo "$USER:$NEWPASS" | sudo chpasswd
  echo "root:$NEWPASS"   | sudo chpasswd
  ok "Đã đổi mật khẩu cho '$USER' và root."
fi

# ============================================================
# Bước 12: Cài đặt SCADA agent
# ============================================================
info "Cài đặt SCADA agent từ scada.tpservers.com..."
if curl -fsSL https://scada.tpservers.com/agent | sudo bash; then
  ok "Đã cài đặt SCADA agent."
else
  warn "Cài SCADA agent thất bại — kiểm tra lại mạng hoặc URL."
fi

# ============================================================
# Tổng kết
# ============================================================
echo
ok "HOÀN TẤT! Tóm tắt:"
echo "  • xrdp đang chạy ở port : ${XRDP_PORT}"
echo "  • Phiên desktop          : ${SESSION_CMD}"
echo "  • Trạng thái dịch vụ     :"
systemctl is-active xrdp >/dev/null 2>&1 && echo "      xrdp = active" || echo "      xrdp = KHÔNG active (kiểm tra: journalctl -u xrdp)"
echo
echo "  Kết nối từ máy khác bằng RDP tới:  <IP-máy-này>:${XRDP_PORT}"
echo "  Kiểm tra IP hiện tại bằng:          ip a"

# ============================================================
# Tự xóa file script
# ============================================================
SCRIPT_PATH="$(realpath "$0")"
info "Xóa file script: $SCRIPT_PATH"
rm -f "$SCRIPT_PATH" && ok "Đã xóa file script." || warn "Không xóa được file script."

# ============================================================
# Khởi động lại máy
# ============================================================
echo
warn "Cài đặt xong — máy sẽ khởi động lại sau 10 giây... (Ctrl+C để hủy)"
sleep 10
sudo reboot
