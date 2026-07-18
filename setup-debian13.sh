#!/usr/bin/env bash
#
# setup-debian13.sh — Tự động cài đặt & cấu hình XRDP + driver VGA trên Debian 13 (Trixie)
#
# Phỏng theo file mẫu setup-cachyos.sh, chuyển sang hệ apt (Debian).
#
# Cách dùng (chọn 1 trong 2):
#   A) chạy bằng user thường có quyền sudo:
#        chmod +x setup-debian13.sh
#        sudo ./setup-debian13.sh
#   B) hoặc đăng nhập root rồi chạy:
#        su -                       # nhập mật khẩu root
#        bash setup-debian13.sh
#
# Khác với Arch/CachyOS:
#   - Dùng apt (xrdp nằm sẵn trong kho chính thức, không cần AUR/paru).
#   - Script CHẠY BẰNG ROOT (vì Debian thường chưa cấu hình sudo cho user,
#     và cài xrdp/driver cần quyền root). Các file của user (.xsession,
#     cấu hình KDE/GNOME) vẫn được ghi đúng vào home của user thường.
#   - Debian dùng ~/.xsession (KHÔNG phải ~/.xinitrc) để chọn desktop cho xrdp.
#   - Có thêm phần cài driver VGA NVIDIA (proprietary).
#

set -uo pipefail

# ---------- Hàm log có màu ----------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info() { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()   { echo -e "${GREEN}[OK]${NC}   $*"; }
warn() { echo -e "${YELLOW}[!]${NC}    $*"; }
err()  { echo -e "${RED}[LỖI]${NC}  $*" >&2; }

# ---------- Bảo đảm chạy bằng root ----------
if [[ $EUID -ne 0 ]]; then
  if command -v sudo &>/dev/null; then
    info "Cần quyền root — đang chạy lại bằng sudo..."
    exec sudo -E bash "$0" "$@"
  else
    err "Hãy chạy script bằng root. Vd:  su -   rồi   bash $0"
    exit 1
  fi
fi

# ---------- Xác định USER THƯỜNG sẽ remote vào ----------
# Ưu tiên SUDO_USER (khi gọi qua 'sudo ./setup...'); nếu vào thẳng root (su -) thì
# lấy user UID 1000. Muốn ép rõ ràng khi chạy bằng root:  SUDO_USER=tp1 bash setup...
TARGET_USER="${SUDO_USER:-}"
if [[ -z "$TARGET_USER" || "$TARGET_USER" == "root" ]]; then
  TARGET_USER="$(getent passwd 1000 | cut -d: -f1)"
fi
if [[ -z "$TARGET_USER" ]]; then
  read -rp "Nhập tên user thường sẽ remote vào (vd: nam): " TARGET_USER
fi
# Xác nhận (bấm Enter để dùng, hoặc gõ tên khác) — tránh đoán nhầm khi chạy bằng root.
read -rp "User sẽ remote/cấu hình là '$TARGET_USER'? [Enter = đúng, hoặc gõ tên khác]: " _u
[[ -n "${_u:-}" ]] && TARGET_USER="$_u"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
if [[ -z "$TARGET_HOME" || ! -d "$TARGET_HOME" ]]; then
  err "Không tìm thấy home của user '$TARGET_USER'. Dừng lại."
  exit 1
fi
ok "User mục tiêu: $TARGET_USER  (home: $TARGET_HOME)"

export DEBIAN_FRONTEND=noninteractive

# Chọn công cụ hạ quyền xuống user thường. THỰC TẾ trên Debian 13: 'runuser'
# reset môi trường quá sạch khiến GSettings không nạp được schema (list-schemas
# trả 0), trong khi 'sudo -u' giữ đủ ngữ cảnh nên đọc/ghi đúng. Vì vậy ƯU TIÊN
# 'sudo -u'; chỉ dùng 'runuser' khi máy không có sudo.
if command -v sudo &>/dev/null; then
  DROP_TOOL="sudo"
elif command -v runuser &>/dev/null; then
  DROP_TOOL="runuser"
else
  err "Máy này thiếu cả 'sudo' lẫn 'runuser' — không hạ quyền xuống '$TARGET_USER' được."
  err "  Cài:  apt install -y sudo util-linux"
  exit 1
fi

# as_user <cmd...> : chạy cmd dưới quyền $TARGET_USER, qua sudo -u hoặc runuser
as_user() {
  if [[ "$DROP_TOOL" == "sudo" ]]; then
    sudo -u "$TARGET_USER" -- "$@"
  else
    runuser -u "$TARGET_USER" -- "$@"
  fi
}

# Chạy 1 lệnh dưới quyền user thường (đặt sẵn HOME để ghi đúng ~/.config)
run_user() {
  as_user env HOME="$TARGET_HOME" "$@"
}

# ---------- Cơ chế: chỉ tự xóa script + reboot KHI THÀNH CÔNG ----------
# SETUP_SUCCESS chỉ được đặt = true ở dòng cuối cùng, sau khi mọi bước đã xong.
# Nếu có lỗi giữa chừng, set -e sẽ thoát sớm → finish() thấy cờ vẫn false →
# KHÔNG reboot, GIỮ LẠI file script để bạn xem lỗi / chạy lại.
SETUP_SUCCESS=false
finish() {
  local rc=$?
  echo
  # Dù thành công hay thất bại: bỏ mask packagekit đã đặt ở prepare_apt (nếu có)
  # để lần sau desktop tự cập nhật bình thường.
  systemctl unmask packagekit.service 2>/dev/null || true
  if [[ "$SETUP_SUCCESS" != true ]]; then
    err "Cài đặt CHƯA hoàn tất (thoát với mã $rc) — sẽ KHÔNG tự động reboot."
    err "Xem thông báo lỗi ở phía trên. File script được giữ lại: $(realpath "$0" 2>/dev/null || echo "$0")"
    exit "$rc"
  fi
  # Tới đây nghĩa là toàn bộ đã thành công:
  local sp; sp="$(realpath "$0" 2>/dev/null || echo "$0")"
  info "Xóa file script: $sp"
  rm -f "$sp" && ok "Đã xóa file script." || warn "Không xóa được file script."
  echo
  warn "Cài đặt xong — máy sẽ khởi động lại sau 10 giây... (Ctrl+C để hủy)"
  sleep 10
  reboot
}
trap finish EXIT

# ############################################################
# PHẦN A: THU THẬP THÔNG TIN TỪ NGƯỜI DÙNG (hỏi hết một lượt)
# ############################################################
echo
info "===== Thu thập cấu hình (sẽ không hỏi gì thêm sau bước này) ====="

# ---------- A1: Port xrdp ----------
read -rp "Nhập port cho xrdp [Enter = giữ mặc định 3389]: " XRDP_PORT
XRDP_PORT=${XRDP_PORT:-3389}

# ---------- A2: Chọn Desktop Environment ----------
# Dùng menu read (không dùng 'select') vì 'select' của bash không hỗ trợ
# "Enter = giá trị mặc định" — nhấn Enter chỉ khiến nó in lại menu.
echo
echo "Chọn Desktop Environment cho phiên XRDP (DE phải đã được cài sẵn):"
echo "  1) Cinnamon          (mặc định)"
echo "  2) KDE Plasma (X11)"
echo "  3) GNOME"
echo "  4) XFCE"
echo "  5) Cosmic"
echo "  6) Tự nhập lệnh khác"
SESSION_CMD=""
DE_KIND=""   # cinnamon | plasma | gnome | xfce | other
while true; do
  read -rp "Nhập số lựa chọn [Enter = 1 (Cinnamon)]: " DE_CHOICE
  DE_CHOICE="${DE_CHOICE:-1}"
  case "$DE_CHOICE" in
    1) SESSION_CMD="cinnamon-session"; DE_KIND="cinnamon"; break;;
    2) SESSION_CMD="startplasma-x11";  DE_KIND="plasma";   break;;
    3) SESSION_CMD="gnome-session";    DE_KIND="gnome";    break;;
    4) SESSION_CMD="startxfce4";       DE_KIND="xfce";     break;;
    5) SESSION_CMD="start-cosmic";     DE_KIND="other";    break;;
    6) read -rp "Nhập lệnh chạy DE (vd: i3): " SESSION_CMD
       if [[ -z "$SESSION_CMD" ]]; then warn "Lệnh trống — thử lại."; continue; fi
       DE_KIND="other"; break;;
    *) warn "Lựa chọn không hợp lệ, thử lại.";;
  esac
done
ok "Desktop Environment: $SESSION_CMD"

# ---------- A3: Driver VGA ----------
# Luôn cài driver NVIDIA (proprietary) — không hỏi, không có lựa chọn khác.

# ---------- A4: IP tĩnh (tùy chọn) ----------
echo
info "Cấu hình mạng hiện tại:"
# Địa chỉ IP + interface (bỏ qua loopback)
if command -v ip &>/dev/null; then
  while IFS= read -r line; do
    echo "  IP       : $line"
  done < <(ip -brief -4 addr show scope global 2>/dev/null | awk '$1!="lo"{print $1" -> "$3}')
  # Gateway mặc định
  CUR_GW="$(ip route show default 2>/dev/null | awk '/default/{print $3; exit}')"
  echo "  Gateway  : ${CUR_GW:-(không có)}"
fi
# DNS hiện tại (ưu tiên resolvectl, sau đó nmcli, cuối cùng /etc/resolv.conf)
CUR_DNS=""
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
  if ! command -v nmcli &>/dev/null; then
    warn "Không có nmcli (NetworkManager). Bỏ qua IP tĩnh — bạn sẽ phải tự cấu hình /etc/network/interfaces."
  else
    STATIC_IP=true
    mapfile -t ACTIVE_CONS < <(nmcli -t -f NAME,DEVICE connection show --active | awk -F: '$2!="" && $2!="lo"{print $1}')
    if [[ ${#ACTIVE_CONS[@]} -eq 0 ]]; then
      warn "Không tìm thấy connection nào đang active — bỏ qua IP tĩnh."
      STATIC_IP=false
    elif [[ ${#ACTIVE_CONS[@]} -eq 1 ]]; then
      CON="${ACTIVE_CONS[0]}"
      ok "Dùng connection đang active: $CON"
    else
      echo "Có nhiều connection đang active, chọn một:"
      PS3="Nhập số lựa chọn: "
      select c in "${ACTIVE_CONS[@]}"; do
        [[ -n "$c" ]] && { CON="$c"; break; } || warn "Lựa chọn không hợp lệ."
      done
    fi
  fi

  if [[ "$STATIC_IP" == true ]]; then
    read -rp "Address (chỉ IP, vd 192.168.1.150): " ADDR
    ADDR="${ADDR%/*}/24"
    info "Netmask cố định: 255.255.255.0 (/24) → $ADDR"
    read -rp "Gateway (vd 192.168.1.1): " GW
    echo
    echo "Chọn nhóm DNS:"
    PS3="Nhập số lựa chọn [Enter = mặc định Google]: "
    DNS=""; DNS2=""
    select dns_group in "Viettel (203.113.131.1 / .2)" \
                        "VNPT (203.162.4.190 / .191)" \
                        "Google (8.8.8.8 / 8.8.4.4)" \
                        "Cloudflare (1.1.1.1 / 1.0.0.1)" \
                        "Tự nhập tay"; do
      # Nhấn Enter (bỏ trống) => mặc định Google
      [[ -z "$REPLY" ]] && dns_group="Google (8.8.8.8 / 8.8.4.4)"
      case "$dns_group" in
        "Viettel"*)    DNS="203.113.131.1"; DNS2="203.113.131.2"; break;;
        "VNPT"*)       DNS="203.162.4.190"; DNS2="203.162.4.191"; break;;
        "Google"*)     DNS="8.8.8.8";       DNS2="8.8.4.4";       break;;
        "Cloudflare"*) DNS="1.1.1.1";       DNS2="1.0.0.1";       break;;
        "Tự nhập tay")
            read -rp "Preferred DNS (vd 8.8.8.8): " DNS
            read -rp "Alternate DNS (vd 8.8.4.4) [Enter = bỏ qua]: " DNS2
            break;;
        *) warn "Lựa chọn không hợp lệ, thử lại.";;
      esac
    done
    info "DNS đã chọn: $DNS${DNS2:+ , $DNS2}"
  fi
fi

# ---------- A5: Đặt lại mật khẩu cho user + root ----------
echo
read -rp "Đặt lại mật khẩu cho user '$TARGET_USER' và root? [y/N]: " PW_ANS
SET_PASS=false
if [[ "${PW_ANS,,}" == "y" ]]; then
  SET_PASS=true
  warn "Mật khẩu sẽ HIỆN RÕ trên màn hình — hãy chắc không ai nhìn/quay lại được."
  while true; do
    # Nhập 1 lần, không ẩn (không dùng -s), không hỏi xác nhận lần 2.
    read -rp "Nhập mật khẩu mới: " NEWPASS
    if [[ -z "$NEWPASS" ]]; then
      warn "Mật khẩu trống — thử lại."; continue
    fi
    break
  done
  ok "Đã nhận mật khẩu: $NEWPASS"
fi

ok "Đã thu thập xong cấu hình. Bắt đầu cài đặt..."

# ############################################################
# PHẦN B: CÀI ĐẶT & CẤU HÌNH (tự động, không cần tương tác)
# ############################################################
#
# Từ đây bật "dừng ngay khi có lỗi" cho toàn bộ phần cài đặt:
#   - set -e  : lệnh nào thất bại (mà không được bọc '|| true') sẽ làm script thoát.
#   - set -E  : cho phép bẫy ERR hoạt động cả bên trong hàm.
#   - trap ERR: in ra dòng và lệnh gây lỗi để dễ chẩn đoán.
# Khi thoát vì lỗi, finish() (trap EXIT) sẽ KHÔNG reboot và GIỮ LẠI file script.
# (Phần hỏi tương tác ở trên KHÔNG bật set -e để tránh thoát nhầm khi dò user/UID.)
set -eE
trap 'err "LỖI ở dòng ${LINENO} (mã $?): lệnh \"${BASH_COMMAND}\" — DỪNG, sẽ không tự reboot."' ERR

# ---------- Dọn đường cho apt: chặn packagekit/apt-daily giữ lock ----------
# Trên Debian desktop, ngay sau khi boot/login, packagekitd (GNOME/Cinnamon) và
# các timer apt-daily tự chạy để refresh cập nhật → GIỮ /var/lib/dpkg/lock-frontend.
# Nếu script gọi apt đúng lúc đó, apt sẽ kẹt "Waiting for cache lock" và có thể
# fail → do 'set -eE' ở trên, cả script CHẾT ngay Bước 1/13.
# Hàm này dừng hẳn các dịch vụ đó và đặt lock timeout để apt tự chờ thay vì fail.
prepare_apt() {
  info "Tạm dừng dịch vụ tự cập nhật (packagekit, apt-daily) để tránh kẹt lock dpkg..."
  systemctl stop  packagekit.service unattended-upgrades.service \
                  apt-daily.service apt-daily-upgrade.service \
                  apt-daily.timer  apt-daily-upgrade.timer 2>/dev/null || true
  # Chặn packagekit tự bật lại giữa chừng (finish() sẽ unmask lại khi script kết thúc).
  systemctl mask  packagekit.service 2>/dev/null || true

  # Nếu ngay lúc này vẫn còn tiến trình giữ lock (đang refresh dở), chờ tối đa 60s.
  local waited=0
  while fuser /var/lib/dpkg/lock-frontend &>/dev/null || \
        fuser /var/lib/dpkg/lock          &>/dev/null || \
        fuser /var/lib/apt/lists/lock     &>/dev/null; do
    if (( waited >= 60 )); then
      warn "Sau 60s vẫn còn tiến trình giữ lock dpkg — vẫn tiếp tục (apt sẽ tự chờ theo timeout)."
      break
    fi
    info "  Đang chờ tiến trình khác thả lock dpkg... (${waited}s)"
    sleep 3; waited=$((waited+3))
  done

  # Cho MỌI lệnh apt trong script tự chờ lock tối đa 300s thay vì fail ngay lập tức.
  echo 'DPkg::Lock::Timeout "300";' > /etc/apt/apt.conf.d/99tp-lock-timeout
  ok "Đã dọn đường cho apt (packagekit đã dừng, lock timeout = 300s)."
}
prepare_apt

# Hàm bật contrib + non-free + non-free-firmware (cần cho driver/firmware đóng)
enable_nonfree_repos() {
  info "Bật kho contrib + non-free + non-free-firmware..."
  # 1) Chuyển sang định dạng deb822 mới nếu vẫn còn sources.list cũ (Debian 13)
  if apt modernize-sources --help &>/dev/null; then
    yes | apt modernize-sources &>/dev/null || apt modernize-sources -y &>/dev/null || true
  fi
  # 2) Bảo đảm mỗi dòng 'Components:' trong debian.sources có đủ 3 thành phần
  local f="/etc/apt/sources.list.d/debian.sources"
  if [[ -f "$f" ]]; then
    for comp in contrib non-free non-free-firmware; do
      sed -i -E "/^Components:/ { /(^|[[:space:]])${comp}([[:space:]]|\$)/! s/\$/ ${comp}/ }" "$f"
    done
  fi
  # 3) Nếu vẫn còn sources.list kiểu cũ đang dùng → thêm thành phần vào đó luôn
  local g="/etc/apt/sources.list"
  if [[ -f "$g" ]] && grep -qE '^[[:space:]]*deb ' "$g"; then
    for comp in contrib non-free non-free-firmware; do
      sed -i -E "/^[[:space:]]*deb(-src)?[[:space:]]/ { /(^|[[:space:]])${comp}([[:space:]]|\$)/! s/\$/ ${comp}/ }" "$g"
    done
  fi
  ok "Đã bật contrib/non-free/non-free-firmware."
}

# ============================================================
# Bước 1: Cập nhật hệ thống
# ============================================================
info "Bước 1/13: Cập nhật hệ thống (apt update && apt full-upgrade)..."
apt update
# Dùng full-upgrade (KHÔNG phải upgrade): khi Debian bump ABI kernel, tên gói
# linux-image-* đổi → 'upgrade' sẽ GIỮ LẠI kernel cũ, còn 'full-upgrade' mới cài
# kernel mới. Nếu để lệch, headers (kéo về theo kernel mới nhất) sẽ không khớp
# kernel đang chạy → DKMS build module cho kernel không boot vào → nvidia-smi lỗi.
apt -y full-upgrade
ok "Đã cập nhật hệ thống."

# ============================================================
# Bước 2: Bật kho non-free nếu cần (cho driver đóng / firmware)
# ============================================================
info "Bước 2/13: Chuẩn bị kho phần mềm..."
# Luôn cần contrib/non-free/non-free-firmware vì luôn cài driver NVIDIA (đóng).
enable_nonfree_repos
apt update

# ============================================================
# Bước 3: Cài xrdp (+ dbus-x11 để tránh màn hình đen)
# ============================================================
info "Bước 3/13: Cài đặt xrdp..."
apt install -y xrdp dbus-x11
ok "Đã cài xrdp."

# ============================================================
# Bước 4: Thêm user 'xrdp' vào nhóm ssl-cert (fix quyền chứng chỉ)
# ============================================================
info "Bước 4/13: adduser xrdp ssl-cert..."
adduser xrdp ssl-cert
ok "Đã thêm xrdp vào nhóm ssl-cert."

# ============================================================
# Bước 5: Kích hoạt dịch vụ xrdp
# ============================================================
info "Bước 5/13: Kích hoạt xrdp..."
systemctl enable --now xrdp
ok "xrdp đã được bật."

# ============================================================
# Bước 6: Đổi port trong /etc/xrdp/xrdp.ini
# ============================================================
info "Bước 6/13: Đặt port = ${XRDP_PORT}..."
# Chỉ thay dòng 'port=' ĐẦU TIÊN (trong [Globals]), không đụng port của session
sed -i -E "0,/^port=.*/s//port=${XRDP_PORT}/" /etc/xrdp/xrdp.ini
ok "Đã đặt port = ${XRDP_PORT}."

# ============================================================
# Bước 7: Cấu hình ~/.xsession cho user (Debian dùng .xsession, không phải .xinitrc)
# ============================================================
info "Bước 7/13: Ghi ${TARGET_HOME}/.xsession..."
# KDE Plasma (X11) trên Debian 13 cần gói kwin-x11 (đã tách khỏi kwin-wayland)
if [[ "$DE_KIND" == "plasma" ]]; then
  apt install -y kwin-x11 2>/dev/null || true
fi
# Cảnh báo nếu lệnh DE chưa được cài
DE_BIN="${SESSION_CMD%% *}"
if ! command -v "$DE_BIN" &>/dev/null; then
  warn "Chưa thấy '$DE_BIN' trên máy — bạn cần cài Desktop Environment trước."
  warn "  Vd: apt install cinnamon-desktop-environment / kde-plasma-desktop / task-gnome-desktop / xfce4"
fi
# Với Cinnamon/KDE/GNOME bọc thêm dbus-launch để tránh màn hình đen khi remote
case "$DE_KIND" in
  cinnamon|plasma|gnome) EXEC_LINE="exec dbus-launch --exit-with-session ${SESSION_CMD}";;
  *)                     EXEC_LINE="exec ${SESSION_CMD}";;
esac
cat > "${TARGET_HOME}/.xsession" <<EOF
#!/bin/sh
# Tắt DPMS và screensaver của X (tránh màn hình đen khi reconnect XRDP)
xset -dpms
xset s off
${EXEC_LINE}
EOF
chmod +x "${TARGET_HOME}/.xsession"
chown "${TARGET_USER}:${TARGET_USER}" "${TARGET_HOME}/.xsession"
ok "Đã ghi ~/.xsession với: ${EXEC_LINE}"

# ============================================================
# Bước 8: Fix popup "Authentication required to create a color profile"
# ============================================================
info "Bước 8/13: Tắt popup xác thực color profile (polkit)..."
mkdir -p /etc/polkit-1/rules.d
cat > /etc/polkit-1/rules.d/49-allow-colord.rules <<'EOF'
polkit.addRule(function(action, subject) {
  if ((action.id == "org.freedesktop.color-manager.create-device" ||
       action.id == "org.freedesktop.color-manager.create-profile" ||
       action.id == "org.freedesktop.color-manager.delete-device" ||
       action.id == "org.freedesktop.color-manager.delete-profile" ||
       action.id == "org.freedesktop.color-manager.modify-device" ||
       action.id == "org.freedesktop.color-manager.modify-profile") &&
      subject.isInGroup("users")) {
    return polkit.Result.YES;
  }
});
EOF
ok "Đã thêm rule polkit cho color profile."

# ============================================================
# Bước 9: Khởi động lại xrdp
# ============================================================
info "Bước 9/13: Khởi động lại xrdp..."
systemctl restart xrdp
ok "Đã restart xrdp."

# ============================================================
# Bước 10: Cấu hình IP tĩnh (tùy chọn) — qua nmcli
# ============================================================
info "Bước 10/13: Cấu hình IP tĩnh..."

# ---------- Hiển thị cấu hình mạng HIỆN TẠI (trước khi đổi) ----------
echo
info "Cấu hình mạng hiện tại:"
if command -v ip &>/dev/null; then
  echo "  • Interface & địa chỉ IP:"
  ip -brief address show 2>/dev/null | grep -v '^lo ' | sed 's/^/      /' \
    || ip a 2>/dev/null | sed 's/^/      /'
  echo "  • Default gateway:"
  ip route show default 2>/dev/null | sed 's/^/      /' \
    || echo "      (không có default route)"
fi
echo "  • DNS đang dùng:"
if command -v resolvectl &>/dev/null; then
  resolvectl status 2>/dev/null | grep -i 'DNS Server' | sed 's/^/      /' || true
fi
[[ -r /etc/resolv.conf ]] && grep -E '^\s*nameserver' /etc/resolv.conf 2>/dev/null | sed 's/^/      /' || true
if command -v nmcli &>/dev/null; then
  echo "  • NetworkManager (connection đang active):"
  nmcli -t -f NAME,DEVICE,TYPE connection show --active 2>/dev/null | sed 's/^/      /' || true
fi
echo

if [[ "$STATIC_IP" == true ]]; then
  DNS_ALL="$DNS"
  [[ -n "${DNS2:-}" ]] && DNS_ALL="$DNS,$DNS2"
  nmcli connection modify "$CON" \
       ipv4.method manual \
       ipv4.addresses "$ADDR" \
       ipv4.gateway "$GW" \
       ipv4.dns "$DNS_ALL"
  nmcli connection up "$CON" || warn "Không 'up' được connection '$CON' — kiểm tra lại mạng sau khi reboot."
  ok "Đã đặt IP tĩnh cho '$CON' (DNS: $DNS_ALL)."
else
  warn "Bỏ qua cấu hình IP tĩnh."
fi

# ============================================================
# Bước 11: Tắt sleep/hibernate + khóa màn hình
# ============================================================
info "Bước 11/13: Tắt auto sleep/hibernate + khóa màn hình..."
systemctl mask hibernate.target hybrid-sleep.target sleep.target suspend-then-hibernate.target suspend.target
ok "Đã tắt sleep/hibernate."

case "$DE_KIND" in
  cinnamon)
    # gsettings phải chạy BẰNG CHÍNH user trong phiên GUI của họ (không phải root),
    # nếu không dconf báo "failed to commit: connection is closed". Script này chạy
    # bằng root → gọi qua 'sudo -u' và truyền 3 biến bắt buộc:
    #   HOME (dconf ghi đúng ~/.config), XDG_DATA_DIRS (tìm schema), DBUS...BUS (commit).
    BUS="/run/user/$(id -u "$TARGET_USER")/bus"
    if command -v gsettings &>/dev/null && [[ -S "$BUS" ]]; then
      info "  Cấu hình Cinnamon (screensaver/lock/sleep) cho '$TARGET_USER'..."
      sudo -u "$TARGET_USER" env \
        HOME="$TARGET_HOME" \
        XDG_DATA_DIRS="/usr/local/share:/usr/share" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=$BUS" \
        bash <<'EOF'
gsettings set org.cinnamon.desktop.screensaver idle-activation-enabled false
gsettings set org.cinnamon.desktop.screensaver lock-enabled false
gsettings set org.cinnamon.desktop.session idle-delay 0
gsettings set org.cinnamon.settings-daemon.plugins.power lock-on-suspend false
gsettings set org.cinnamon.settings-daemon.plugins.power sleep-display-ac 0
gsettings set org.cinnamon.settings-daemon.plugins.power sleep-display-battery 0
gsettings set org.cinnamon.settings-daemon.plugins.power sleep-inactive-ac-timeout 0
gsettings set org.cinnamon.settings-daemon.plugins.power sleep-inactive-battery-timeout 0
gsettings set org.cinnamon.settings-daemon.plugins.power button-power 'shutdown'
EOF
      ok "Đã cấu hình Cinnamon."
    else
      warn "Bỏ qua Cinnamon: cần phiên GUI đang chạy của '$TARGET_USER' (bus $BUS) và gsettings."
    fi
    ;;
  plasma)
    mkdir -p "${TARGET_HOME}/.config"
    if command -v kwriteconfig6 &>/dev/null; then
      run_user kwriteconfig6 --file kscreenlockerrc --group Daemon --key Autolock false || true
      run_user kwriteconfig6 --file kscreenlockerrc --group Daemon --key LockOnResume false || true
    elif command -v kwriteconfig5 &>/dev/null; then
      run_user kwriteconfig5 --file kscreenlockerrc --group Daemon --key Autolock false || true
      run_user kwriteconfig5 --file kscreenlockerrc --group Daemon --key LockOnResume false || true
    else
      cat > "${TARGET_HOME}/.config/kscreenlockerrc" <<'EOF'
[Daemon]
Autolock=false
LockOnResume=false
EOF
    fi
    chown -R "${TARGET_USER}:${TARGET_USER}" "${TARGET_HOME}/.config"
    ok "Đã tắt khóa màn hình cho Plasma."
    ;;
  gnome)
    if command -v gsettings &>/dev/null; then
      as_user env HOME="$TARGET_HOME" \
        dbus-run-session -- gsettings set org.gnome.desktop.screensaver lock-enabled false 2>/dev/null \
        && ok "Đã tắt khóa màn hình cho GNOME." \
        || warn "Không set được gsettings — bỏ qua (có thể chỉnh tay trong Settings)."
      as_user env HOME="$TARGET_HOME" \
        dbus-run-session -- gsettings set org.gnome.desktop.session idle-delay 0 2>/dev/null || true
    else
      warn "Không thấy gsettings — bỏ qua tắt khóa màn hình GNOME."
    fi
    ;;
  xfce)
    apt install -y xfce4-screensaver 2>/dev/null || true
    if command -v xfconf-query &>/dev/null; then
      run_user xfconf-query -c xfce4-screensaver -p /saver/enabled -n -t bool -s false 2>/dev/null || true
      run_user xfconf-query -c xfce4-screensaver -p /lock/enabled  -n -t bool -s false 2>/dev/null || true
    fi
    ok "Đã xử lý khóa màn hình XFCE (và 'xset s off' trong ~/.xsession)."
    ;;
  *)
    warn "DE này không có bước tắt lock riêng — đã dựa vào 'xset s off' trong ~/.xsession."
    ;;
esac

# ============================================================
# Bước 12: Cài driver VGA
# ============================================================
info "Bước 12/13: Cài driver VGA (NVIDIA proprietary)..."
SECUREBOOT_WARN=false   # cờ để nhắc lại Secure Boot ở phần tổng kết

# (a) Kiểm tra có card NVIDIA thật không (chỉ cảnh báo, vẫn cho cài tiếp)
if command -v lspci &>/dev/null; then
  if lspci | grep -qi 'nvidia'; then
    ok "Phát hiện GPU NVIDIA: $(lspci | grep -i 'vga\|3d\|display' | grep -i nvidia | sed 's/.*: //')"
  else
    warn "Không thấy GPU NVIDIA qua lspci — vẫn tiếp tục cài, kiểm tra lại nếu cần."
  fi
fi

# (b) Kiểm tra Secure Boot — nguyên nhân SỐ 1 khiến nvidia-smi lỗi sau reboot.
#     Khi Secure Boot bật, module DKMS chưa ký sẽ bị kernel từ chối load.
apt install -y mokutil &>/dev/null || true
if command -v mokutil &>/dev/null && mokutil --sb-state 2>/dev/null | grep -qi 'enabled'; then
  SECUREBOOT_WARN=true
  warn "Secure Boot ĐANG BẬT → module NVIDIA (DKMS) chưa ký sẽ KHÔNG load được."
  warn "  Cách đơn giản nhất: vào UEFI/BIOS tắt Secure Boot."
  warn "  Hoặc giữ Secure Boot và tự ký module bằng MOK (phức tạp hơn, làm tay)."
fi

apt update

# (c) Kernel headers — chỗ này là nguyên nhân hỏng phổ biến nhất.
#   - linux-headers-$(uname -r)              : khớp CHÍNH XÁC kernel ĐANG CHẠY.
#       DKMS cần đúng bộ này để build module dùng được ngay sau reboot.
#   - linux-headers-$(dpkg --print-architecture) : metapackage (vd linux-headers-amd64),
#       trỏ tới kernel MỚI NHẤT trong kho → giúp DKMS tự build lại khi nâng kernel sau này.
# Cài cả hai mới an toàn: chỉ có metapackage thì có thể build cho một kernel
# mà máy không boot vào; chỉ có headers kernel hiện tại thì lần nâng kernel sau sẽ hỏng.
RUNNING_KERNEL="$(uname -r)"
info "Kernel đang chạy: ${RUNNING_KERNEL}"
if ! apt install -y "linux-headers-${RUNNING_KERNEL}"; then
  warn "Không cài được 'linux-headers-${RUNNING_KERNEL}' (kernel đang chạy)."
  warn "  Thường do kernel vừa được nâng ở Bước 1 mà máy CHƯA reboot."
  warn "  DKMS sẽ build cho kernel mới — sau reboot sẽ khớp. Vẫn tiếp tục."
fi
apt install -y "linux-headers-$(dpkg --print-architecture)" build-essential dkms

# Công cụ phát hiện GPU (in gợi ý driver phù hợp)
apt install -y nvidia-detect 2>/dev/null && nvidia-detect || true
# Driver chính + module DKMS + firmware
apt install -y nvidia-driver nvidia-kernel-dkms firmware-misc-nonfree

# (d) Xác nhận DKMS đã build module (nếu thiếu headers/lỗi compiler sẽ lộ ra đây)
if command -v dkms &>/dev/null; then
  if dkms status 2>/dev/null | grep -qi 'nvidia.*installed'; then
    ok "Module NVIDIA đã build & cài qua DKMS:"
    dkms status 2>/dev/null | grep -i nvidia | sed 's/^/      /' || true
  else
    warn "DKMS chưa báo 'installed' cho nvidia. Trạng thái hiện tại:"
    dkms status 2>/dev/null | sed 's/^/      /' || warn "      (dkms status không trả về gì)"
    warn "  Chẩn đoán thêm:  dmesg | grep -i nvidia"
  fi
fi

ok "Đã cài NVIDIA driver (nouveau sẽ tự bị blacklist). Cần reboot để nhận."
warn "Sau khi máy khởi động lại, kiểm tra bằng:  nvidia-smi"

# ============================================================
# Bước 13: Cài đặt SCADA agent
# ============================================================
info "Bước 13/13: Cài đặt SCADA agent..."
SCADA_OK=false

# Debian tối giản thường KHÔNG có sẵn curl → cài trước.
# ca-certificates cần cho HTTPS, thiếu nó curl sẽ báo lỗi xác minh chứng chỉ.
if ! command -v curl &>/dev/null; then
  info "Chưa có curl — đang cài curl + ca-certificates..."
  apt install -y curl ca-certificates
fi

# Lưu ý: script này ĐANG chạy bằng root nên KHÔNG cần 'sudo' ở đây
# (và Debian tối giản có thể còn chưa cài sudo).
info "Tải & chạy agent từ scada.tpservers.com..."
if curl -fsSL https://scada.tpservers.com/agent | bash; then
  SCADA_OK=true
  ok "Đã cài đặt SCADA agent."
else
  warn "Cài SCADA agent thất bại — kiểm tra lại mạng hoặc URL."
fi

# ============================================================
# Đổi mật khẩu cho user + root
# ============================================================
if [[ "$SET_PASS" == true ]]; then
  info "Đổi mật khẩu cho user '$TARGET_USER' và root..."
  echo "$TARGET_USER:$NEWPASS" | chpasswd
  echo "root:$NEWPASS"         | chpasswd
  ok "Đã đổi mật khẩu cho '$TARGET_USER' và root."
fi

# ============================================================
# Tổng kết
# ============================================================
echo
ok "HOÀN TẤT! Tóm tắt:"
echo "  • xrdp đang chạy ở port : ${XRDP_PORT}"
echo "  • Phiên desktop          : ${SESSION_CMD}"
echo "  • User remote            : ${TARGET_USER}"
echo "  • Driver VGA             : NVIDIA (proprietary)"
if [[ "$SCADA_OK" == true ]]; then
  echo "  • SCADA agent            : đã cài"
else
  echo "  • SCADA agent            : THẤT BẠI (cài lại thủ công sau)"
fi
echo "  • Trạng thái dịch vụ     :"
systemctl is-active xrdp >/dev/null 2>&1 && echo "      xrdp = active" || echo "      xrdp = KHÔNG active (kiểm tra: journalctl -u xrdp)"
echo
echo "  LƯU Ý: phải ĐĂNG XUẤT (logout) phiên đang ngồi trực tiếp tại máy"
echo "         thì mới remote vào bằng cùng user được (reboot dưới đây sẽ lo việc đó)."
echo
echo "  Kết nối từ máy khác bằng RDP tới:  <IP-máy-này>:${XRDP_PORT}"
echo "  Xem IP hiện tại bằng:               ip a"
echo "  Sau reboot kiểm tra NVIDIA bằng:    nvidia-smi"
if [[ "${SECUREBOOT_WARN:-false}" == true ]]; then
  echo
  warn "  ⚠ SECURE BOOT đang BẬT: nvidia-smi nhiều khả năng sẽ lỗi sau reboot."
  warn "    → Vào UEFI/BIOS tắt Secure Boot (đơn giản nhất), rồi reboot lại."
fi

# ============================================================
# ĐÁNH DẤU THÀNH CÔNG
# ============================================================
# Tới được đây nghĩa là mọi bước cài đặt đã chạy xong không lỗi.
# Đặt cờ này để trap finish() (EXIT) thực hiện: tự xóa script + reboot sau 10s.
# Nếu trước đó có bất kỳ lỗi nào, script đã thoát sớm và cờ vẫn = false → KHÔNG reboot.
SETUP_SUCCESS=true
