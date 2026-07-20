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

    sudo swapoff -a
    sudo vgchange -an
    sudo dmsetup remove_all
    sudo wipefs -a "/dev/$DISK"
    sudo sgdisk --zap-all "/dev/$DISK"
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
  2) Xóa sạch ổ đĩa NVMe (nguy hiểm)
  3) Đổi mật khẩu user + root
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
            2) wipe_nvme; pause ;;
            3) change_passwords; pause ;;
            # TODO: thêm chức năng mới ở đây
            q) echo "Thoát."; break ;;
            *) echo "Lựa chọn không hợp lệ. Vui lòng thử lại." ;;
        esac
    done
}

main "$@"
