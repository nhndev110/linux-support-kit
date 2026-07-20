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

# ---------------------------------------------------------------------------
# 1) Cấu hình DNS qua NetworkManager
# ---------------------------------------------------------------------------
configure_dns_nm() {
    local DNS DEV CON PICK

    echo "Chọn nhóm DNS:"
    echo "  1) Google      (8.8.8.8,8.8.4.4)"
    echo "  2) Cloudflare  (1.1.1.1,1.0.0.1)"
    echo "  3) Viettel     (203.113.131.1,203.113.131.2)"
    echo "  4) VNPT        (203.162.4.191,203.162.4.190)"
    echo "  5) Tự nhập"
    read -rp "Lựa chọn [1]: " PICK
    case "${PICK:-1}" in
        1) DNS="8.8.8.8,8.8.4.4" ;;
        2) DNS="1.1.1.1,1.0.0.1" ;;
        3) DNS="203.113.131.1,203.113.131.2" ;;
        4) DNS="203.162.4.191,203.162.4.190" ;;
        5) read -rp "Nhập DNS (VD 8.8.8.8,1.1.1.1): " DNS ;;
        *) echo "Lựa chọn không hợp lệ"; return 1 ;;
    esac
    [ -z "$DNS" ] && { echo "Bạn chưa nhập DNS"; return 1; }

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
# TODO: Bổ sung các chức năng khác tại đây
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Menu chính
# ---------------------------------------------------------------------------
show_menu() {
    cat <<'EOF'

============================================
        SUPPORT KIT — Linux Server
============================================
  1) Cấu hình DNS (NetworkManager)
  2) ...
  q) Thoát
============================================
EOF
}

main() {
    while true; do
        show_menu
        read -rp "Nhập lựa chọn: " CHOICE
        echo
        case "$CHOICE" in
            1) configure_dns_nm; pause ;;
            2) # TODO: thêm chức năng mới ở đây
               ;;
            q) echo "Thoát."; break ;;
            *) echo "Lựa chọn không hợp lệ. Vui lòng thử lại." ;;
        esac
    done
}

main "$@"
