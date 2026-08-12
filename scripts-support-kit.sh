#!/usr/bin/env bash
#
# Support Kit — menu xử lý sự cố nhanh cho máy chủ Linux.
# Các thao tác tương ứng tài liệu Support-Linux.md.

# ---------------------------------------------------------------------------
# Tiện ích chung
# ---------------------------------------------------------------------------
pause() {
    read -rp $'\nNhấn Enter để quay lại menu...' _
}

# Đúng dạng IPv4: 4 octet 0-255, không có số 0 thừa ở đầu (010 dễ bị hiểu là bát phân)
is_ipv4() {
    local ip="$1" o
    [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] || return 1
    for o in ${ip//./ }; do
        (( 10#$o >= 0 && 10#$o <= 255 )) || return 1
        [[ "$o" != "0" && "$o" =~ ^0 ]] && return 1
    done
    return 0
}

# Hỏi cho tới khi nhập được IPv4 hợp lệ; kết quả gán vào biến có tên $2
read_ipv4() {
    local prompt="$1" varname="$2" value
    while true; do
        read -rp "$prompt" value || { echo "Không đọc được dữ liệu nhập (EOF)."; return 1; }
        value="${value// /}"      # bỏ khoảng trắng thừa
        value="${value%/*}"       # bỏ phần /prefix nếu lỡ gõ (VD 192.168.1.10/24)
        if is_ipv4 "$value"; then
            printf -v "$varname" '%s' "$value"
            return 0
        fi
        echo "Giá trị '$value' không phải IPv4 hợp lệ — nhập dạng x.x.x.x, mỗi số 0-255."
    done
}

# Menu chọn nhóm DNS; in chuỗi DNS ra stdout (menu in ra stderr để không lẫn kết quả)
pick_dns() {
    local PICK DNS
    {
        echo "Chọn nhóm DNS:"
        echo "  1) Google      (8.8.8.8,8.8.4.4)"
        echo "  2) Cloudflare  (1.1.1.1,1.0.0.1)"
        echo "  3) VNPT        (203.162.4.190,203.162.4.191)"
        echo "  4) Viettel     (203.113.131.1,203.113.131.2)"
        echo "  5) Tự nhập"
    } >&2
    read -rp "Lựa chọn [1]: " PICK
    case "${PICK:-1}" in
        1) DNS="8.8.8.8,8.8.4.4" ;;
        2) DNS="1.1.1.1,1.0.0.1" ;;
        3) DNS="203.162.4.190,203.162.4.191" ;;
        4) DNS="203.113.131.1,203.113.131.2" ;;
        5) read -rp "Nhập DNS (VD 8.8.8.8,1.1.1.1): " DNS ;;
        *) echo "Lựa chọn không hợp lệ" >&2; return 1 ;;
    esac
    [ -z "$DNS" ] && { echo "Bạn chưa nhập DNS" >&2; return 1; }
    printf '%s' "$DNS"
}

# Tự lấy connection NetworkManager đang active (không hỏi); in tên ra stdout
pick_nm_connection() {
    local DEV CON=""
    command -v nmcli >/dev/null 2>&1 || { echo "Máy không có nmcli (NetworkManager)" >&2; return 1; }

    # Ưu tiên interface đang giữ default route — đó mới là đường ra internet thật sự
    DEV=$(ip -4 route show default | awk '{print $5; exit}')
    [ -n "$DEV" ] && CON=$(nmcli -t -f DEVICE,CONNECTION dev status | grep "^${DEV}:" | cut -d: -f2-)

    # Không có default route (hoặc interface đó không do NM quản lý) -> lấy connection active đầu tiên
    [ -z "$CON" ] && CON=$(nmcli -t -f NAME,DEVICE connection show --active | awk -F: '$2!="" && $2!="lo"{print $1; exit}')

    [ -z "$CON" ] && { echo "Không tìm thấy connection nào đang active" >&2; return 1; }
    printf '%s' "$CON"
}

# In cấu hình mạng hiện tại (IP / gateway / DNS)
show_network_info() {
    local line CUR_GW CUR_DNS
    echo "Cấu hình mạng hiện tại:"
    while IFS= read -r line; do
        echo "  • IP      : $line"
    done < <(ip -brief -4 addr show scope global 2>/dev/null | awk '$1!="lo"{print $1" -> "$3}')
    CUR_GW=$(ip route show default 2>/dev/null | awk '/default/{print $3; exit}')
    echo "  • Gateway : ${CUR_GW:-(không có)}"
    if command -v resolvectl >/dev/null 2>&1; then
        CUR_DNS=$(resolvectl dns 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort -u | paste -sd' ')
    fi
    [ -z "${CUR_DNS:-}" ] && command -v nmcli >/dev/null 2>&1 && \
        CUR_DNS=$(nmcli -g IP4.DNS device show 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort -u | paste -sd' ')
    [ -z "${CUR_DNS:-}" ] && \
        CUR_DNS=$(awk '/^nameserver/{print $2}' /etc/resolv.conf 2>/dev/null | paste -sd' ')
    echo "  • DNS     : ${CUR_DNS:-(không có)}"
}

# ---------------------------------------------------------------------------
# 1) Cấu hình DNS qua NetworkManager
# ---------------------------------------------------------------------------
configure_dns_nm() {
    local DNS DEV CON

    DNS=$(pick_dns) || return 1

    DEV=$(ip -4 route show default | awk '{print $5; exit}')
    [ -z "$DEV" ] && { echo "Không tìm thấy interface đang online"; return 1; }

    CON=$(nmcli -t -f DEVICE,CONNECTION dev status | grep "^${DEV}:" | cut -d: -f2-)
    [ -z "$CON" ] && { echo "Interface $DEV không do NetworkManager quản lý"; return 1; }

    echo "Đang cấu hình DNS cho: $CON ($DEV) -> $DNS"
    sudo nmcli con mod "$CON" ipv4.dns "$DNS" || return 1
    sudo nmcli con mod "$CON" ipv4.ignore-auto-dns yes || return 1
    sudo nmcli dev reapply "$DEV" || return 1
    echo "✔ Đã cấu hình DNS xong."
}

# ---------------------------------------------------------------------------
# 2) Xóa sạch ổ đĩa NVMe (nguy hiểm)
# ---------------------------------------------------------------------------
wipe_nvme() {
    local DISK ANSWER

    echo "Các ổ đĩa hiện có:"
    lsblk -d -o NAME,SIZE,MODEL

    read -rp $'\nNhập tên ổ cần xóa (VD nvme0n1): ' DISK
    [ -z "$DISK" ] && { echo "Chưa nhập tên ổ, hủy."; return 1; }
    [ ! -b "/dev/$DISK" ] && { echo "/dev/$DISK không tồn tại, hủy."; return 1; }

    echo "⚠️  Toàn bộ dữ liệu trên /dev/$DISK sẽ bị XÓA và KHÔNG THỂ khôi phục."
    read -rp "Gõ đúng tên ổ '$DISK' để xác nhận: " ANSWER
    [ "$ANSWER" != "$DISK" ] && { echo "Không khớp, đã hủy."; return 1; }

    # sudo swapoff -a
    # sudo vgchange -an
    # sudo dmsetup remove_all
    # sudo wipefs -a "/dev/$DISK"
    # sudo sgdisk --zap-all "/dev/$DISK"

    sudo wipefs -a "/dev/$DISK"
    sudo parted "/dev/$DISK" mklabel msdos
    echo "✔ Đã xóa sạch /dev/$DISK."
}

# ---------------------------------------------------------------------------
# 3) Đổi mật khẩu cho user hiện tại và root
# ---------------------------------------------------------------------------
change_passwords() {
    local NEWPASS

    read -rp "Nhập mật khẩu mới cho '$USER' và root: " NEWPASS
    [ -z "$NEWPASS" ] && { echo "Mật khẩu rỗng, hủy."; return 1; }

    printf '%s:%s\n%s:%s\n' "$USER" "$NEWPASS" root "$NEWPASS" | sudo chpasswd \
        && echo "✔ Đã đổi mật khẩu cho '$USER' và root." \
        || echo "✘ Đổi mật khẩu thất bại."
}

# ---------------------------------------------------------------------------
# 4) Cấu hình mạng + port XRDP (hỏi hết một lượt rồi áp dụng)
# ---------------------------------------------------------------------------
setup_network_xrdp() {
    local CON ADDR GW DNS PORT ANSWER
    local INI="/etc/xrdp/xrdp.ini" CUR_PORT
    local AFTER AFTER_TXT

    # ---------- Kiểm tra điều kiện trước khi hỏi ----------
    CON=$(pick_nm_connection) || return 1
    [ ! -f "$INI" ] && { echo "Không tìm thấy $INI — máy chưa cài xrdp?"; return 1; }
    CUR_PORT=$(grep -m1 -E '^port=' "$INI" | cut -d= -f2)

    echo
    show_network_info
    echo "  • Port XRDP : ${CUR_PORT:-(không đọc được)}"
    echo "  • Connection: $CON"

    # ---------- Hỏi toàn bộ cấu hình (không áp dụng gì ở bước này) ----------
    echo
    echo "===== Nhập cấu hình mới ====="
    read_ipv4 "Địa chỉ IP: " ADDR || return 1
    echo "Subnet mask: 255.255.255.0 (/24) — cố định"
    # Gateway lấy luôn địa chỉ .1 cùng lớp mạng (đúng với đa số router)
    GW="${ADDR%.*}.1"
    echo "Gateway    : $GW — tự suy từ IP"
    DNS=$(pick_dns) || return 1

    read -rp "Port XRDP [Enter = giữ ${CUR_PORT:-3389}]: " PORT
    PORT=${PORT:-${CUR_PORT:-3389}}
    if ! [[ "$PORT" =~ ^[0-9]+$ ]] || (( PORT < 1 || PORT > 65535 )); then
        echo "Port '$PORT' không hợp lệ (1-65535), hủy."; return 1
    fi

    # ---------- Hành động sau khi cấu hình xong ----------
    echo
    echo "Sau khi cấu hình xong thì làm gì?"
    echo "  1) Không làm gì (quay lại menu)"
    echo "  2) Khởi động lại máy"
    echo "  3) Tắt máy"
    read -rp "Lựa chọn [1]: " AFTER
    case "${AFTER:-1}" in
        1) AFTER=1; AFTER_TXT="không làm gì" ;;
        2) AFTER=2; AFTER_TXT="KHỞI ĐỘNG LẠI máy" ;;
        3) AFTER=3; AFTER_TXT="TẮT máy" ;;
        *) echo "Lựa chọn không hợp lệ, hủy."; return 1 ;;
    esac

    # ---------- Xác nhận ----------
    echo
    echo "Sắp áp dụng:"
    echo "  • Connection : $CON"
    echo "  • IP         : $ADDR/24 (netmask 255.255.255.0)"
    echo "  • Gateway    : $GW"
    echo "  • DNS        : $DNS"
    echo "  • Port XRDP  : ${CUR_PORT:-?} -> $PORT"
    echo "  • Sau đó     : $AFTER_TXT"
    read -rp "Xác nhận áp dụng? [y/N]: " ANSWER
    [ "${ANSWER,,}" != "y" ] && { echo "Đã hủy, chưa thay đổi gì."; return 1; }

    # ---------- Áp dụng: port XRDP trước, đổi IP sau (đổi IP có thể ngắt phiên remote) ----------
    if [ "$PORT" != "$CUR_PORT" ]; then
        sudo cp -a "$INI" "${INI}.bak" || return 1
        # Chỉ thay dòng 'port=' ĐẦU TIÊN (nằm trong [Globals]), không đụng port của session
        sudo sed -i -E "0,/^port=.*/s//port=${PORT}/" "$INI" || return 1
        grep -qx "port=${PORT}" "$INI" \
            || { echo "✘ Không ghi được port vào $INI (sao lưu: ${INI}.bak)"; return 1; }
        sudo systemctl restart xrdp || { echo "✘ Restart xrdp thất bại — xem: journalctl -u xrdp"; return 1; }
        sleep 2
        systemctl is-active --quiet xrdp \
            && echo "✔ Port XRDP: ${CUR_PORT:-?} -> ${PORT} (sao lưu: ${INI}.bak)" \
            || { echo "✘ xrdp không active sau khi đổi port — xem: journalctl -u xrdp"; return 1; }
    else
        echo "• Port XRDP giữ nguyên ($PORT)."
    fi

    echo "⚠️  Nếu đang remote qua chính mạng này, phiên kết nối sẽ ngắt khi IP đổi."
    sudo nmcli con mod "$CON" \
        ipv4.method manual \
        ipv4.addresses "$ADDR/24" \
        ipv4.gateway "$GW" \
        ipv4.dns "$DNS" \
        ipv4.ignore-auto-dns yes || return 1
    # 'con up' chắc ăn hơn 'dev reapply' khi đổi method/địa chỉ
    sudo nmcli con up "$CON" \
        || { echo "✘ Không kích hoạt lại được '$CON' — kiểm tra: nmcli con show \"$CON\""; return 1; }

    echo "✔ Đã cấu hình xong mạng + port XRDP."
    echo "  Kết nối RDP tới: ${ADDR}:${PORT}"
    echo "  Nhớ mở port trên tường lửa nếu đang bật (ufw/firewalld)."
    echo
    show_network_info

    # ---------- Hành động cuối (đã chọn từ trước) ----------
    [ "$AFTER" = "1" ] && return 0
    echo
    echo "⚠️  $AFTER_TXT sau 10 giây... (Ctrl+C để hủy)"
    sleep 10
    case "$AFTER" in
        2) sudo reboot ;;
        3) sudo poweroff ;;
    esac
}

# ---------------------------------------------------------------------------
# 5) Cài lại Accops Client (Support Farmers V5)
# ---------------------------------------------------------------------------
reinstall_accops() {
    local PIN NAME

    read -rp "Mã PIN: " PIN
    [ -z "$PIN" ] && { echo "Chưa nhập mã PIN, hủy."; return 1; }
    read -rp "Tên thiết bị: " NAME
    [ -z "$NAME" ] && { echo "Chưa nhập tên thiết bị, hủy."; return 1; }

    echo "⚠️  Xóa cấu hình Accops cũ, cài lại và KHỞI ĐỘNG LẠI máy."
    sudo systemctl stop accops-client 2>/dev/null || true \
        && sudo rm -rf "$HOME/accops" /etc/accops \
        && curl -fsSL https://accountops.org/install | sudo bash -s -- --pin "$PIN" --name "$NAME" \
        && sudo reboot
}

# ---------------------------------------------------------------------------
# Bổ sung các chức năng khác tại đây
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# 6) Cài SCADA agent từ scada.tpservers.com
# ---------------------------------------------------------------------------
install_scada_agent() {
    local URL='https://scada.tpservers.com/agent'

    echo "Cài đặt SCADA agent từ $URL"

    # Kiểm tra curl
    if ! command -v curl >/dev/null 2>&1; then
        echo "curl chưa cài đặt. Thử cài qua trình quản lý gói hiện có..."
        if command -v apt-get >/dev/null 2>&1; then
            sudo apt-get update && sudo apt-get install -y curl || { echo "Cài curl thất bại"; return 1; }
        elif command -v yum >/dev/null 2>&1; then
            sudo yum install -y curl || { echo "Cài curl thất bại"; return 1; }
        elif command -v dnf >/dev/null 2>&1; then
            sudo dnf install -y curl || { echo "Cài curl thất bại"; return 1; }
        else
            echo "Không biết trình quản lý gói — vui lòng cài curl thủ công và thử lại."; return 1
        fi
    fi

    # Thực thi script cài đặt agent (tham số cố định như yêu cầu)
    curl -fsSL "$URL" | sudo bash -s -- -pa scada -pt 8202121018fcbf12caa8aaacea42f2bdb25e7b66
    local rc=$?
    if [ $rc -eq 0 ]; then
        echo "✔ Cài đặt SCADA agent hoàn tất."
    else
        echo "✘ Cài đặt SCADA agent thất bại (mã: $rc)."
        return $rc
    fi
}


# ---------------------------------------------------------------------------
# Banner + Menu chính
# ---------------------------------------------------------------------------
# Chỉ tô màu khi xuất ra terminal (chạy qua pipe/log thì để trơn)
if [ -t 1 ]; then
    C_MAIN=$'\033[1;36m'; C_SUB=$'\033[0;35m'; C_OFF=$'\033[0m'
else
    C_MAIN=''; C_SUB=''; C_OFF=''
fi

show_banner() {
    cat <<EOF
${C_MAIN}
███╗   ██╗██╗  ██╗ █████╗ ███╗   ██╗    ██╗  ██╗████████╗
████╗  ██║██║  ██║██╔══██╗████╗  ██║    ██║ ██╔╝╚══██╔══╝
██╔██╗ ██║███████║███████║██╔██╗ ██║    █████╔╝    ██║   
██║╚██╗██║██╔══██║██╔══██║██║╚██╗██║    ██╔═██╗    ██║   
██║ ╚████║██║  ██║██║  ██║██║ ╚████║    ██║  ██╗   ██║   
╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝    ╚═╝  ╚═╝   ╚═╝   
${C_OFF}
EOF
}

# Tìm PID của shell tương tác đã gọi script, bỏ qua sudo/su xen giữa.
parent_shell_pid() {
    local pid=$PPID comm
    while [ -n "$pid" ] && [ "$pid" -gt 1 ] 2>/dev/null; do
        comm=$(ps -o comm= -p "$pid" 2>/dev/null | tr -d ' ')
        case "$comm" in
            bash|-bash|sh|dash|zsh|-zsh|fish|-fish|ksh) echo "$pid"; return 0 ;;
        esac
        pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    done
    return 1
}

# Xóa lịch sử lệnh: file history trên đĩa + (nếu được) history trong bộ nhớ.
#
# Điểm mấu chốt: shell giữ history trong RAM và ghi đè xuống file khi thoát,
# nên chỉ xóa file là chưa đủ — lịch sử sẽ quay lại lúc đóng terminal.
#   - Nếu script được `source` → history -c chạy ngay trong shell gọi, xóa sạch.
#   - Nếu script chạy thường  → phải đóng luôn shell cha để nó không ghi đè lại.
clear_history() {
    local target_user target_home f sourced=0 shell_pid shell_name ans

    target_user="${SUDO_USER:-$USER}"
    target_home=$(getent passwd "$target_user" 2>/dev/null | cut -d: -f6)
    [ -z "$target_home" ] && target_home="$HOME"

    # Xóa file history của mọi shell phổ biến (Debian hay dùng bash,
    # CachyOS/Arch mặc định fish, cấu hình zsh của CachyOS ghi file ngay mỗi lệnh)
    for f in "${HISTFILE:-}" \
             "$target_home/.bash_history" \
             "$target_home/.zsh_history" \
             "$target_home/.local/share/fish/fish_history" \
             "$target_home/.local/share/fish/fish_history.bak"; do
        [ -n "$f" ] && [ -f "$f" ] && : > "$f"
    done

    # Chạy bằng sudo/root thì xóa luôn history của root
    if [ "$(id -u)" -eq 0 ] && [ "$target_home" != "/root" ]; then
        for f in /root/.bash_history /root/.zsh_history; do
            [ -f "$f" ] && : > "$f"
        done
    fi

    echo "Đã xóa file lịch sử lệnh của $target_user."

    # Được source? Khi đó history -c tác động thẳng vào shell đang dùng.
    # (Không dùng mẹo `(return 0)` vì bên trong hàm nó luôn thành công.)
    [ "${BASH_SOURCE[0]}" != "$0" ] && sourced=1

    if [ "$sourced" -eq 1 ]; then
        history -c 2>/dev/null
        history -d 0 2>/dev/null
        history -w 2>/dev/null
        echo "Đã xóa lịch sử trong bộ nhớ của phiên hiện tại."
        return 0
    fi

    # Chạy ở subshell: không chạm được history trong RAM của shell cha.
    shell_pid=$(parent_shell_pid) || {
        echo "Không xác định được shell cha."
        echo "Hãy tự chạy: history -c && history -w"
        return 0
    }
    shell_name=$(ps -o comm= -p "$shell_pid" 2>/dev/null | tr -d ' -')

    echo
    echo "Lưu ý: lịch sử vẫn còn trong bộ nhớ của terminal ($shell_name, PID $shell_pid)"
    echo "và sẽ được ghi đè lại xuống file khi bạn đóng terminal."
    read -rp "Đóng luôn terminal để xóa triệt để? [y/N] " ans

    case "$ans" in
        [yY]*)
            echo "Đang đóng phiên terminal..."
            # SIGKILL để shell không kịp ghi history trong RAM xuống file
            kill -9 "$shell_pid" 2>/dev/null
            ;;
        *)
            echo "Bỏ qua. Muốn xóa nốt phần trong bộ nhớ, chạy thủ công:"
            case "$shell_name" in
                fish) echo "    history clear" ;;
                zsh)  echo "    history -p" ;;
                *)    echo "    history -c && history -w" ;;
            esac
            ;;
    esac
}

show_menu() {
    cat <<'EOF'
============================================
  1) Cấu hình DNS (NetworkManager)
  2) Xóa sạch ổ đĩa NVMe (nguy hiểm)
  3) Đổi mật khẩu user + root
  4) Cấu hình mạng + port XRDP (IP/Subnet/Gateway/DNS/Port)
  5) Cài lại Accops Client (Support Farmers V5)
  6) Cài SCADA agent (scada.tpservers.com)
  q) Thoát
============================================
EOF
}

main() {
    show_banner
    while true; do
        show_menu
        read -rp "Nhập lựa chọn: " CHOICE
        echo
        case "$CHOICE" in
            1) configure_dns_nm; pause ;;
            2) wipe_nvme; pause ;;
            3) change_passwords; pause ;;
            4) setup_network_xrdp; pause ;;
            5) reinstall_accops; pause ;;
            6) install_scada_agent; pause ;;
            # TODO: thêm chức năng mới ở đây
            q) echo "Thoát."; clear_history; break ;;
            *) echo "Lựa chọn không hợp lệ. Vui lòng thử lại." ;;
        esac
    done
}

main "$@"
