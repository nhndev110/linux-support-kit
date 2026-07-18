# Hỗ trợ Linux — TPServer

Tài liệu tra cứu nhanh các lệnh xử lý sự cố trên máy chủ Linux.

---

## Script Setup Nhanh OS

### CachyOS

```bash
curl -fsSL https://raw.githubusercontent.com/nhndev110/tpserver-support-kit/refs/heads/main/setup-cachyos.sh -o setup-cachyos.sh && chmod +x setup-cachyos.sh && ./setup-cachyos.sh
```

### Debian

Đặt mật khẩu cho `root` rồi chuyển sang phiên `root`:

```bash
sudo passwd root
```

```bash
su -
```

Tải và chạy script cài đặt (dùng `curl` hoặc `wget`):

```bash
curl -fsSL https://raw.githubusercontent.com/nhndev110/tpserver-support-kit/refs/heads/main/setup-debian13.sh -o setup-debian13.sh && chmod +x setup-debian13.sh && ./setup-debian13.sh
```

```bash
wget -qO setup-debian13.sh https://raw.githubusercontent.com/nhndev110/tpserver-support-kit/refs/heads/main/setup-debian13.sh && chmod +x setup-debian13.sh && ./setup-debian13.sh
```

---

## Xóa sạch ổ đĩa NVMe (trước khi cài lại)

Tắt swap, gỡ LVM/device-mapper rồi xóa toàn bộ chữ ký và bảng phân vùng trên ổ `nvme0n1`.

> ⚠️ **Cảnh báo:** Lệnh này xóa **toàn bộ** dữ liệu trên ổ đĩa và không thể khôi phục. Kiểm tra kỹ tên ổ (`lsblk`) trước khi chạy.

```bash
sudo swapoff -a
sudo vgchange -an
sudo dmsetup remove_all
sudo wipefs -a /dev/nvme0n1
sudo sgdisk --zap-all /dev/nvme0n1
```

---

## Đổi mật khẩu cho user và root

Đặt mật khẩu mới cùng lúc cho user hiện tại và tài khoản `root`. Thay `<Mật khẩu>` bằng mật khẩu cần đặt.

```bash
set NEWPASS "<Mật khẩu>"; printf '%s:%s\n%s:%s\n' "$USER" "$NEWPASS" root "$NEWPASS" | sudo chpasswd
```

---

## Support Farmers V5 (Accops Client)

Khởi động lại dịch vụ Accops Client:

```bash
systemctl restart accops-client
```

Theo dõi log của dịch vụ theo thời gian thực (Ctrl+C để thoát):

```bash
journalctl -fu accops-client
```

---

## Tắt máy và khởi động lại

Tắt máy ngay lập tức:

```bash
sudo shutdown -h now
```

Khởi động lại máy ngay lập tức:

```bash
sudo reboot
```
