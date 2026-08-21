#!/usr/bin/env bash
#
# setup-cachyos.sh — Tự động cài đặt & cấu hình XRDP trên Arch Linux (dùng paru)
#
# Cách dùng:
#   chmod +x setup-cachyos.sh
#   ./setup-cachyos.sh       <-- chạy bằng USER THƯỜNG, KHÔNG dùng sudo/root
#
# Lý do không chạy bằng root: paru build gói AUR (xrdp, xorgxrdp) và từ chối
# chạy dưới quyền root. Script sẽ tự gọi sudo ở các bước cần quyền hệ thống.
#

set -uo pipefail

# ---------- Ghi log ra file ----------
# Chạy qua systemd thì unit đặt StandardOutput=tty, output chỉ hiện trên tty1 rồi
# trôi mất — không có gì trong journalctl. Giữ thêm một bản ra file để soi lại được.
LOGFILE="${HOME:-/tmp}/configure-system.log"
exec > >(tee -a "$LOGFILE") 2>&1
echo "=== configure-system $(date -Is) ==="

# ---------- Hàm log có màu ----------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info() { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()   { echo -e "${GREEN}[OK]${NC}   $*"; }
warn() { echo -e "${YELLOW}[!]${NC}    $*"; }
err()  { echo -e "${RED}[LỖI]${NC}  $*" >&2; }

# ---------- Hàm kiểm tra dữ liệu nhập ----------
# Đúng dạng IPv4: 4 octet, mỗi octet 0-255, không có số 0 thừa ở đầu (010 dễ nhầm bát phân)
is_ipv4() {
  local ip="$1" o
  [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] || return 1
  for o in ${ip//./ }; do
    (( 10#$o >= 0 && 10#$o <= 255 )) || return 1
    [[ "$o" != "0" && "$o" =~ ^0 ]] && return 1
  done
  return 0
}

# Hỏi cho tới khi nhập được một IPv4 hợp lệ; kết quả gán vào biến có tên $2
read_ipv4() {
  local prompt="$1" varname="$2" value
  while true; do
    read -rp "$prompt" value || { err "Không đọc được dữ liệu nhập (EOF)."; exit 1; }
    value="${value// /}"          # bỏ khoảng trắng thừa
    value="${value%/*}"           # bỏ phần /prefix nếu người dùng lỡ gõ (vd 192.168.1.10/24)
    if is_ipv4 "$value"; then
      printf -v "$varname" '%s' "$value"
      return 0
    fi
    warn "Giá trị '${value}' không phải IPv4 hợp lệ — nhập dạng x.x.x.x, mỗi số từ 0 đến 255."
  done
}

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

# Xin quyền sudo ngay từ đầu và giữ "sống" trong suốt quá trình.
# Thử 'sudo -n true' TRƯỚC: khi đã có NOPASSWD (post-install.sh cấp tạm) thì không
# cần hỏi gì cả. Không dùng 'sudo -v' ở trường hợp này vì '-v' xác thực theo đường
# riêng và vẫn bật hộp hỏi mật khẩu dù sudoers đã cho !authenticate.
if sudo -n true 2>/dev/null; then
  ok "Đã có quyền sudo không cần mật khẩu."
else
  info "Cần quyền sudo để cấu hình hệ thống — nhập mật khẩu nếu được hỏi:"
  sudo -v || { err "Không lấy được quyền sudo."; exit 1; }
  ( while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) &
  KEEPALIVE_PID=$!
  trap 'kill "$KEEPALIVE_PID" 2>/dev/null' EXIT
fi

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
# Các menu trong script đều dùng 'read' chứ không dùng 'select', vì 'select' khi
# nhấn Enter chỉ in lại menu — không hỗ trợ "Enter = giá trị mặc định".
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
  echo "  • IP: $line"
done < <(ip -brief -4 addr show scope global 2>/dev/null | awk '$1!="lo"{print $1" -> "$3}')
# Gateway mặc định
CUR_GW="$(ip route show default 2>/dev/null | awk '/default/{print $3; exit}')"
echo "  • Gateway: ${CUR_GW:-(không có)}"
# DNS hiện tại (ưu tiên resolvectl, sau đó nmcli, cuối cùng /etc/resolv.conf)
if command -v resolvectl &>/dev/null; then
  CUR_DNS="$(resolvectl dns 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort -u | paste -sd' ')"
fi
[[ -z "${CUR_DNS:-}" ]] && command -v nmcli &>/dev/null && \
  CUR_DNS="$(nmcli -g IP4.DNS device show 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort -u | paste -sd' ')"
[[ -z "${CUR_DNS:-}" ]] && \
  CUR_DNS="$(awk '/^nameserver/{print $2}' /etc/resolv.conf 2>/dev/null | paste -sd' ')"
echo "  • DNS: ${CUR_DNS:-(không có)}"
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

  read_ipv4 "Address (chỉ IP, vd 192.168.1.150): " ADDR
  # Gateway lấy luôn địa chỉ .1 cùng lớp mạng (đúng với đa số router) — tính TRƯỚC khi
  # gắn '/24' vào ADDR cho khỏi phải cắt chuỗi hai lần
  GW="${ADDR%.*}.1"
  ADDR="$ADDR/24"
  info "Netmask cố định: 255.255.255.0 (/24) → $ADDR"
  info "Gateway tự suy từ IP: $GW"
  echo
  echo "Chọn nhóm DNS:"
  echo "  1) Google      (8.8.8.8 / 8.8.4.4)   (mặc định)"
  echo "  2) Cloudflare  (1.1.1.1 / 1.0.0.1)"
  echo "  3) VNPT        (203.162.4.190 / .191)"
  echo "  4) Viettel     (203.113.131.1 / .2)"
  echo "  5) Tự nhập tay"
  DNS=""; DNS2=""
  while true; do
    read -rp "Nhập số lựa chọn [Enter = 1 (Google)]: " DNS_CHOICE
    DNS_CHOICE="${DNS_CHOICE:-1}"
    case "$DNS_CHOICE" in
      1) DNS="8.8.8.8";       DNS2="8.8.4.4";       break;;
      2) DNS="1.1.1.1";       DNS2="1.0.0.1";       break;;
      3) DNS="203.162.4.190"; DNS2="203.162.4.191"; break;;
      4) DNS="203.113.131.1"; DNS2="203.113.131.2"; break;;
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

# ---------- A5: Tailscale (tùy chọn) ----------
echo
info "Tailscale để truy cập máy từ xa khi cần kiểm tra."
# CHÚ Ý: key nhúng sẵn ở đây và repo là public — ai đọc được file cũng ghép được
# máy của họ vào tailnet. Khi key lộ hoặc hết hạn thì xoay key mới ở
# https://login.tailscale.com/admin/settings/keys rồi sửa lại dòng dưới.
TS_DEFAULT_KEY="tskey-auth-kTSVWqqid211CNTRL-BRNitiKMkUFNCDGg8xjsUFbYsQsXWkRL"
# Thứ tự ưu tiên: nhập tay > biến môi trường TS_AUTHKEY > key mặc định ở trên
TS_KEY="${TS_AUTHKEY:-$TS_DEFAULT_KEY}"
read -rp "Tailscale auth key [Enter = dùng key có sẵn]: " TS_INPUT
[[ -n "$TS_INPUT" ]] && TS_KEY="$TS_INPUT"

ok "Đã thu thập xong cấu hình. Bắt đầu cài đặt..."

# ############################################################
# KHUNG THEO DÕI TRẠNG THÁI CÁC BƯỚC
# ############################################################
# Mỗi bước được ghi lại: tên bước + trạng thái + ghi chú, in ra dạng danh sách khi kết thúc
#   OK      = thành công (đã kiểm tra bằng "cờ" xác minh)
#   BỎ QUA  = không áp dụng / không bắt buộc, không tính là lỗi
#   LỖI     = thất bại → dừng script, KHÔNG reboot
# TOTAL_STEPS chỉ dùng để hiển thị "Bước N/TOTAL" — nhớ cập nhật khi thêm/bớt begin_step
TOTAL_STEPS=16
STEP_TITLES=()
STEP_STATES=()
STEP_NOTES=()

record() { STEP_TITLES+=("$1"); STEP_STATES+=("$2"); STEP_NOTES+=("${3:-}"); }

# Bắt đầu một bước: đánh số theo số bước đã ghi nhận, in tiêu đề, lưu tên bước hiện tại
begin_step() {
  CURRENT_STEP="$1"
  STEP_NO=$(( ${#STEP_TITLES[@]} + 1 ))
  info "Bước ${STEP_NO}/${TOTAL_STEPS}: ${CURRENT_STEP}..."
}

pass_step() { record "$CURRENT_STEP" "OK"     "${1:-}"; ok   "Bước ${STEP_NO} OK — ${CURRENT_STEP}${1:+ ($1)}"; }
skip_step() { record "$CURRENT_STEP" "BỎ QUA" "${1:-}"; warn "Bước ${STEP_NO} bỏ qua — ${1:-không áp dụng}"; }

# In tổng kết các bước theo dạng danh sách từng ý
print_summary() {
  local i state mark color
  echo
  for i in "${!STEP_TITLES[@]}"; do
    state="${STEP_STATES[$i]}"
    case "$state" in
      OK)       mark="✔"; color="$GREEN";;
      "BỎ QUA") mark="○"; color="$YELLOW";;
      *)        mark="✘"; color="$RED";;
    esac
    echo -e "  ${color}${mark}${NC} Bước $((i+1)). ${STEP_TITLES[$i]}  ${color}[${state}]${NC}"
    [[ -n "${STEP_NOTES[$i]}" ]] && echo "       ↳ ${STEP_NOTES[$i]}"
  done
}

# Bước thất bại → ghi LỖI, in tổng kết, dừng hẳn, KHÔNG reboot, KHÔNG xóa script
die_step() {
  local reason="${1:-lệnh trả về mã lỗi}"
  record "$CURRENT_STEP" "LỖI" "$reason"
  echo
  err "BƯỚC ${STEP_NO}/${TOTAL_STEPS} THẤT BẠI: ${CURRENT_STEP}"
  err "Nguyên nhân: ${reason}"
  print_summary
  echo
  err "CÀI ĐẶT DỪNG LẠI DO LỖI:"
  err "  • Máy sẽ KHÔNG khởi động lại."
  err "  • Script KHÔNG bị xóa."
  err "  • Sửa lỗi xong chạy lại: $0"
  # Giữ lại NOPASSWD để lần chạy sau không phải nhập mật khẩu, nhưng phải báo rõ:
  # bỏ quên file này là để hở quyền root không cần mật khẩu trên máy giao cho khách
  [[ -f /etc/sudoers.d/99-configure-system ]] && \
    err "  • CHÚ Ý: /etc/sudoers.d/99-configure-system vẫn còn (sudo không cần mật khẩu)."
  exit 1
}

# Chạy lệnh bắt buộc: lỗi là dừng
must() {
  local rc
  "$@"; rc=$?
  (( rc != 0 )) && die_step "lệnh thất bại (mã $rc): $*"
  return 0
}

# Cờ xác minh sau khi làm xong: điều kiện sai là dừng
verify() {
  local desc="$1"; shift
  if "$@" &>/dev/null; then
    return 0
  fi
  die_step "cờ kiểm tra thất bại — ${desc}"
}

# ############################################################
# PHẦN B: CÀI ĐẶT & CẤU HÌNH (tự động, không cần tương tác)
# ############################################################

# --- Bước 1: Cập nhật hệ thống ---
begin_step "Cập nhật hệ thống (pacman -Syu)"
must sudo pacman -Syu --noconfirm
pass_step

# --- Bước 2: Cài đặt Tailscale [không bắt buộc] ---
begin_step "Cài đặt Tailscale"
# Đặt ngay sau bước cập nhật, TRƯỚC mọi bước nặng: nếu các bước sau hỏng thì vẫn
# còn đường vào máy từ xa để đọc log — đúng mục đích dùng Tailscale ở đây.
# Cả bước dùng if/elif chứ không dùng 'must': Tailscale là tiện ích phụ, key hết
# hạn không đáng làm hỏng cả lần cài máy.
if [[ -z "$TS_KEY" ]]; then
  skip_step "không nhập auth key"
elif ! sudo pacman -Syu --needed --noconfirm tailscale; then
  skip_step "cài gói tailscale thất bại"
elif ! sudo systemctl enable --now tailscaled; then
  skip_step "không bật được tailscaled"
elif sudo tailscale up --authkey="$TS_KEY"; then
  TS_IP="$(tailscale ip -4 2>/dev/null | head -n1)"
  pass_step "${TS_IP:-đã kết nối}"
else
  skip_step "tailscale up thất bại — key sai hoặc đã hết hạn?"
fi

# --- Bước 3: Đảm bảo có desktop + màn hình đăng nhập ---
begin_step "Kiểm tra desktop và display manager"
# cachyos-installer ở headless_mode KHÔNG cài desktop dù settings.json ghi
# "desktop": "kde" — máy boot xong rơi thẳng vào tty1. Bù lại ở đây.
# /etc/systemd/system/display-manager.service là symlink do 'systemctl enable <dm>'
# tạo ra; không có nó nghĩa là không có màn hình đăng nhập nào chạy.
if [[ -e /etc/systemd/system/display-manager.service ]]; then
  pass_step "đã có display manager"
elif [[ "$SESSION_CMD" == "exec startplasma-x11" ]]; then
  info "Chưa có display manager — cài KDE Plasma..."
  # KDE đã thay SDDM bằng plasma-login-manager từ Plasma 6.5, nên không hardcode
  # tên gói: hỏi repo xem cái nào có thật rồi mới dùng.
  DM_PKG=""
  for p in plasma-login-manager sddm; do
    if pacman -Si "$p" &>/dev/null; then DM_PKG="$p"; break; fi
  done
  [[ -n "$DM_PKG" ]] || die_step "repo không có plasma-login-manager lẫn sddm"
  info "Display manager sẽ dùng: $DM_PKG"
  # xorg-server/xorg-xinit cũng nằm trong danh sách installer cài hụt, mà bước 7
  # (~/.xinitrc + startplasma-x11) thì bắt buộc phải có chúng.
  # Dùng -Syu chứ không phải -S: gộp nâng cấp và cài đặt vào CÙNG một transaction
  # là cách Arch khuyến nghị để tránh partial upgrade. Với -S, pacman chỉ được phép
  # đụng vào gói ta liệt kê, nên khi bản mới kéo theo gói cũ hơn của gói đã cài
  # (vd gstreamer -1.1 của CachyOS vs -1 của extra) nó bó tay và báo
  # "breaks dependency". Với -Syu nó được nâng/hạ cả cụm cho khớp.
  # Cả họ gst phải nằm trong CÙNG một transaction. Repo CachyOS tự mâu thuẫn: nó
  # ship gst-libav/gst-plugins-bad/ugly bản rebuild '-1.1' đòi đúng
  # 'gstreamer=1.28.6-1.1', nhưng không ship gstreamer/gst-plugins-base-libs bản
  # '-1.1'. Không kê tên ra thì pacman chỉ được đụng vào gói ta xin, thấy phải hạ
  # cấp gói khác là bỏ cuộc với 'breaks dependency' — đúng lỗi làm
  # install_desktop_packages của cachyos-installer chết.
  must sudo pacman -Syu --needed --noconfirm \
       plasma-meta "$DM_PKG" konsole dolphin xorg-server xorg-xinit \
       gstreamer gst-plugins-base gst-plugins-base-libs \
       gst-libav gst-plugins-bad gst-plugins-bad-libs gst-plugins-ugly
  # Tên unit KHÔNG chắc trùng tên gói: 'plasma-login-manager' cài xong mà
  # 'systemctl enable plasma-login-manager' báo "Unit ... does not exist".
  # Hỏi thẳng pacman xem gói vừa cài ra service nào, bỏ qua unit mẫu (@.service).
  DM_SVC="$(pacman -Ql "$DM_PKG" 2>/dev/null | awk '{print $2}' \
            | grep -E '/systemd/system/[^/@]+\.service$' | head -n1)"
  DM_SVC="${DM_SVC##*/}"
  if [[ -z "$DM_SVC" ]]; then
    warn "$DM_PKG không kèm service nào — quay sang sddm"
    must sudo pacman -S --needed --noconfirm sddm
    DM_SVC=sddm.service
  fi
  info "Display manager service: $DM_SVC"
  must sudo systemctl enable "$DM_SVC"
  verify "$DM_SVC chưa được enable" test -e /etc/systemd/system/display-manager.service
  pass_step "đã cài plasma-meta + $DM_SVC"
else
  skip_step "chưa có display manager, DE này chưa có bước cài tự động — phải cài tay"
fi

# --- Bước 4: Cài xrdp và xorgxrdp (qua paru / AUR) ---
begin_step "Cài đặt xrdp + xorgxrdp"
must paru -S --noconfirm xrdp xorgxrdp
verify "không tìm thấy lệnh xrdp sau khi cài" command -v xrdp
verify "không tìm thấy /etc/xrdp/xrdp.ini" test -f /etc/xrdp/xrdp.ini
pass_step "$(xrdp -v 2>/dev/null | head -n1)"

# --- Bước 5: Tạo chứng chỉ (cert) tự động [không bắt buộc] ---
begin_step "Tạo chứng chỉ (cert) cho xrdp"
if command -v xrdp-keygen &>/dev/null; then
  if sudo xrdp-keygen xrdp auto; then
    pass_step
  else
    skip_step "xrdp-keygen lỗi — service sẽ tự tạo cert khi khởi động"
  fi
else
  skip_step "không có xrdp-keygen — service tự tạo cert khi khởi động"
fi

# --- Bước 6: Kích hoạt dịch vụ xrdp ---
begin_step "Kích hoạt dịch vụ xrdp"
must sudo systemctl enable --now xrdp
verify "xrdp chưa được enable" systemctl is-enabled xrdp
pass_step

# --- Bước 7: Đổi port trong /etc/xrdp/xrdp.ini ---
begin_step "Đặt port xrdp = ${XRDP_PORT}"
# Chỉ thay dòng 'port=' ĐẦU TIÊN (nằm trong [Globals]), không đụng port của session
must sudo sed -i -E "0,/^port=.*/s//port=${XRDP_PORT}/" /etc/xrdp/xrdp.ini
verify "không thấy dòng port=${XRDP_PORT} trong /etc/xrdp/xrdp.ini" \
  grep -qx "port=${XRDP_PORT}" /etc/xrdp/xrdp.ini
pass_step "port=${XRDP_PORT}"

# --- Bước 8: Cấu hình ~/.xinitrc theo Desktop Environment ---
begin_step "Ghi ~/.xinitrc cho phiên desktop"
# Nếu chọn KDE Plasma (X11) thì đảm bảo có kwin-x11 (Arch đã tách kwin-x11/kwin-wayland)
if [[ "$SESSION_CMD" == "exec startplasma-x11" ]]; then
  info "Đảm bảo có kwin-x11 cho phiên Plasma X11..."
  # -Syu vì cùng lý do như bước 2: tránh 'breaks dependency' do partial upgrade
  must sudo pacman -Syu --needed --noconfirm kwin-x11
  ok "kwin-x11 đã sẵn sàng."
fi
# Ghi ~/.xinitrc của USER (không dùng sudo — nếu dùng sudo sẽ ghi vào /root)
cat > "$HOME/.xinitrc" <<EOF || die_step "không ghi được $HOME/.xinitrc"
#!/bin/sh
# Tắt DPMS và screensaver của X (tránh màn hình đen khi reconnect XRDP)
xset -dpms
xset s off
$SESSION_CMD
EOF
must chmod +x "$HOME/.xinitrc"
verify "~/.xinitrc không chứa lệnh session mong muốn" \
  grep -qF "$SESSION_CMD" "$HOME/.xinitrc"
pass_step "$SESSION_CMD"

# --- Bước 9: Khởi động lại xrdp ---
begin_step "Khởi động lại dịch vụ xrdp"
must sudo systemctl restart xrdp
sleep 2   # cho service kịp lên trước khi kiểm tra cờ
verify "xrdp không ở trạng thái active (xem: journalctl -u xrdp)" systemctl is-active xrdp
pass_step "active"

# --- Bước 10: Tắt tường lửa ufw [không bắt buộc] ---
begin_step "Tắt tường lửa ufw"
if command -v ufw &>/dev/null; then
  must sudo ufw disable
  pass_step
else
  skip_step "không có ufw trên máy — không cần tắt"
fi

# --- Bước 11: Cấu hình IP tĩnh (tùy chọn) — qua nmcli (NetworkManager) ---
begin_step "Cấu hình IP tĩnh"
if [[ "$STATIC_IP" == true ]]; then
  # Gộp DNS chính + phụ (nếu có)
  DNS_ALL="$DNS"
  [[ -n "${DNS2:-}" ]] && DNS_ALL="$DNS,$DNS2"

  must sudo nmcli connection modify "$CON" \
       ipv4.method manual \
       ipv4.addresses "$ADDR" \
       ipv4.gateway "$GW" \
       ipv4.dns "$DNS_ALL"
  must sudo nmcli connection up "$CON"
  # Truyền $CON qua tham số vị trí ($1) thay vì nhúng vào chuỗi — an toàn với mọi tên connection
  verify "connection '$CON' chưa ở chế độ manual" \
    bash -c 'nmcli -g ipv4.method connection show "$1" | grep -qx manual' _ "$CON"
  pass_step "$CON → $ADDR, GW $GW, DNS $DNS_ALL"
else
  skip_step "người dùng chọn không đặt IP tĩnh (giữ DHCP)"
fi

# --- Bước 12: Tắt auto sleep / hibernate (giữ máy luôn thức cho XRDP) ---
begin_step "Tắt auto sleep / hibernate"
must sudo systemctl mask hibernate.target hybrid-sleep.target sleep.target suspend-then-hibernate.target suspend.target
verify "sleep.target chưa bị mask" \
  bash -c 'systemctl is-enabled sleep.target 2>/dev/null | grep -qx masked'
pass_step "máy sẽ không tự ngủ"

# --- Bước 13: Tắt khóa màn hình tự động (screen lock) ---
begin_step "Tắt khóa màn hình tự động"
# KDE Plasma — tắt qua powerdevilrc (quản lý năng lượng) của user.
# Dấu '--' trước giá trị là bắt buộc: thiếu nó, kwriteconfig hiểu '-1' là tùy chọn.
if [[ "$SESSION_CMD" == "exec startplasma-x11" ]]; then
  must mkdir -p "$HOME/.config"
  if command -v kwriteconfig6 &>/dev/null; then
    kwriteconfig6 --file kscreenlockerrc --group Daemon --key Autolock false
    kwriteconfig6 --file kscreenlockerrc --group Daemon --key LockOnResume false
    kwriteconfig6 --file kscreenlockerrc --group Daemon --key Timeout 0

    kwriteconfig6 --file powerdevilrc --group AC --group SuspendAndShutdown --key AutoSuspendAction -- 0
    kwriteconfig6 --file powerdevilrc --group AC --group SuspendAndShutdown --key PowerButtonAction -- 8

    kwriteconfig6 --file powerdevilrc --group AC --group Display --key DimDisplayIdleTimeoutSec -- -1
    kwriteconfig6 --file powerdevilrc --group AC --group Display --key TurnOffDisplayIdleTimeoutSec -- -1
    kwriteconfig6 --file powerdevilrc --group AC --group Display --key TurnOffDisplayWhenIdle -- false

    kwriteconfig6 --file powerdevilrc --group AC --group Performance --key PowerProfile performance
  else
    # Không có kwriteconfig6 -> ghi thẳng 2 file, nội dung khớp đúng các key ở trên
    # (KConfig ghi nhóm lồng nhau theo dạng [AC][Nhóm])
    cat > "$HOME/.config/kscreenlockerrc" <<EOF || die_step "không ghi được kscreenlockerrc"
[Daemon]
Autolock=false
LockOnResume=false
Timeout=0
EOF
    cat > "$HOME/.config/powerdevilrc" <<EOF || die_step "không ghi được powerdevilrc"
[AC][Display]
DimDisplayIdleTimeoutSec=-1
TurnOffDisplayIdleTimeoutSec=-1
TurnOffDisplayWhenIdle=false

[AC][Performance]
PowerProfile=performance

[AC][SuspendAndShutdown]
AutoSuspendAction=0
PowerButtonAction=8
EOF
  fi
  verify "kscreenlockerrc không có Autolock=false" \
    grep -q "Autolock=false" "$HOME/.config/kscreenlockerrc"
  verify "powerdevilrc không có AutoSuspendAction=0" \
    grep -q "AutoSuspendAction=0" "$HOME/.config/powerdevilrc"
  pass_step "KDE Plasma"
# GNOME — tắt qua gsettings
elif [[ "$SESSION_CMD" == "exec gnome-session" ]]; then
  if command -v gsettings &>/dev/null; then
    gsettings set org.gnome.desktop.screensaver lock-enabled false
    gsettings set org.gnome.desktop.session idle-delay 0
    pass_step "GNOME"
  else
    skip_step "không có gsettings — bỏ qua tắt khóa màn hình GNOME"
  fi
else
  # XFCE / Cosmic / lệnh tùy chỉnh — xset s off trong .xinitrc đã xử lý phần lớn
  skip_step "DE này không có bước riêng — đã dùng 'xset s off' trong ~/.xinitrc"
fi

# --- Bước 14: Đặt ảnh nền chuẩn [không bắt buộc] ---
begin_step "Đặt ảnh nền từ wallpaper-store"
# Tải về tên cố định (không theo ngày như tên file nguồn) để file cấu hình khỏi phải đổi theo
WALLPAPER_URL="https://raw.githubusercontent.com/devservertp/tp-net-client-wallpaper-store/refs/heads/staging/wallpaper-00.jpg"
WALLPAPER_PATH="/usr/share/backgrounds/tp-wallpaper.jpg"
WALLPAPER_OK=false
if ! command -v curl &>/dev/null; then
  skip_step "không có curl — không tải được ảnh nền"
elif [[ "$SESSION_CMD" != "exec startplasma-x11" ]]; then
  skip_step "DE này chưa hỗ trợ đặt ảnh nền tự động (chỉ KDE Plasma)"
else
  sudo mkdir -p /usr/share/backgrounds
  # Tải hụt / 404 -> file rỗng, coi như thất bại. Mất ảnh nền không đáng làm hỏng cả lần cài máy
  if sudo curl -fsSL "$WALLPAPER_URL" -o "$WALLPAPER_PATH" && [[ -s "$WALLPAPER_PATH" ]]; then
    sudo chmod 644 "$WALLPAPER_PATH"
    # Lớp 1 — ghi config để lần đăng nhập sau (sau reboot cuối script) vẫn có ảnh nền
    KW=""
    if command -v kwriteconfig6 &>/dev/null; then
      KW=kwriteconfig6
    elif command -v kwriteconfig5 &>/dev/null; then
      KW=kwriteconfig5
    fi
    if [[ -n "$KW" ]] && "$KW" --file plasma-org.kde.plasma.desktop-appletsrc \
         --group Containments --group 1 --group Wallpaper --group org.kde.image --group General \
         --key Image "file://$WALLPAPER_PATH"; then
      WALLPAPER_OK=true
    fi
    # Lớp 2 — áp ngay nếu đang chạy trong phiên Plasma (cần D-Bus, có thể chưa có)
    if command -v plasma-apply-wallpaperimage &>/dev/null \
       && plasma-apply-wallpaperimage "$WALLPAPER_PATH" &>/dev/null; then
      ok "Đã áp ảnh nền cho phiên Plasma đang chạy."
      WALLPAPER_OK=true
    else
      info "Chưa có phiên Plasma để áp ngay — ảnh nền sẽ hiện sau khi đăng nhập lại."
    fi
    if [[ "$WALLPAPER_OK" == true ]]; then
      verify "không thấy file ảnh nền $WALLPAPER_PATH" test -s "$WALLPAPER_PATH"
      pass_step "$WALLPAPER_PATH"
    else
      skip_step "đã tải ảnh về $WALLPAPER_PATH nhưng không có kwriteconfig6/5 để đặt — cần đặt tay"
    fi
  else
    sudo rm -f "$WALLPAPER_PATH"
    skip_step "tải ảnh nền thất bại — kiểm tra lại mạng hoặc URL"
  fi
fi

# --- Bước 15: Đổi mật khẩu cho user + root ---
begin_step "Đổi mật khẩu cho user '$USER' và root"
if [[ "$SET_PASS" == true ]]; then
  echo "$USER:$NEWPASS" | sudo chpasswd || die_step "không đổi được mật khẩu cho '$USER'"
  echo "root:$NEWPASS"   | sudo chpasswd || die_step "không đổi được mật khẩu cho root"
  pass_step "đã đổi cho '$USER' và root"
else
  skip_step "người dùng chọn không đổi mật khẩu"
fi

# --- Bước 16: Cài đặt SCADA agent [không bắt buộc] ---
begin_step "Cài đặt SCADA agent (scada.tpservers.com)"
if curl -fsSL https://scada.tpservers.com/agent | sudo bash -s -- -pa scada; then
  pass_step
else
  skip_step "cài SCADA agent thất bại — kiểm tra lại mạng hoặc URL"
fi

# ############################################################
# PHẦN C: TỔNG KẾT — chỉ tới đây khi TẤT CẢ các bước đều không lỗi
# ############################################################
echo
ok "HOÀN TẤT! Tất cả ${#STEP_TITLES[@]}/${TOTAL_STEPS} bước đều không có lỗi."
print_summary

echo
info "Cấu hình đã áp dụng:"
echo "  • Port xrdp: ${XRDP_PORT}"
echo "  • Phiên desktop: ${SESSION_CMD}"
echo "  • Dịch vụ xrdp: $(systemctl is-active xrdp 2>/dev/null)"
echo "  • Tailscale: ${TS_IP:-chưa kết nối}"
if [[ "$STATIC_IP" == true ]]; then
  echo "  • IP tĩnh: ${ADDR} (GW ${GW}, DNS ${DNS_ALL})"
else
  echo "  • IP: giữ DHCP"
fi
echo "  • Mật khẩu user/root: $([[ "$SET_PASS" == true ]] && echo 'đã đặt lại' || echo 'giữ nguyên')"
echo "  • Sleep/Hibernate: đã tắt"
echo "  • Khóa màn hình: đã tắt"
echo "  • Ảnh nền: $([[ "${WALLPAPER_OK:-false}" == true ]] && echo "$WALLPAPER_PATH" || echo 'bỏ qua')"
echo
info "Hướng dẫn sử dụng:"
echo "  • Kết nối RDP từ máy khác tới: <IP-máy-này>:${XRDP_PORT}"
[[ -n "${TS_IP:-}" ]] && echo "  • Qua Tailscale: ${TS_IP}:${XRDP_PORT}"
echo "  • Kiểm tra IP hiện tại bằng: ip a"

# --- Thu hồi quyền sudo không mật khẩu (do post-install.sh cấp tạm) ---
# Phải làm TRƯỚC khi xóa script: xóa xong là mất luôn đường chạy lại để dọn
SUDOERS_DROPIN=/etc/sudoers.d/99-configure-system
if [[ -f "$SUDOERS_DROPIN" ]]; then
  info "Thu hồi quyền sudo không mật khẩu: $SUDOERS_DROPIN"
  sudo rm -f "$SUDOERS_DROPIN" && ok "Đã thu hồi NOPASSWD." \
    || warn "KHÔNG gỡ được $SUDOERS_DROPIN — hãy xóa tay!"
fi

# --- Tự xóa file script (chỉ khi mọi bước đều thành công) ---
SCRIPT_PATH="$(realpath "$0")"
info "Xóa file script: $SCRIPT_PATH"
rm -f "$SCRIPT_PATH" && ok "Đã xóa file script." || warn "Không xóa được file script."

# --- Khởi động lại máy ---
echo
warn "Máy sẽ khởi động lại sau 10 giây... (Ctrl+C để hủy)"
for i in $(seq 10 -1 1); do
  printf "\r${YELLOW}[!]${NC}    Reboot sau %2d giây... " "$i"
  sleep 1
done
echo
sudo reboot
