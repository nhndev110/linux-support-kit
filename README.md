# Linux Support Kit

Bộ script và tài liệu hỗ trợ cài đặt, cấu hình nhanh máy chủ Linux.

Xem thêm các lệnh xử lý sự cố tại [Support-Linux.md](Support-Linux.md).

---

## Script Setup Nhanh Linux

### CachyOS

```bash
curl -fsSL https://raw.githubusercontent.com/nhndev110/linux-support-kit/refs/heads/main/setup-cachyos.sh -o setup-cachyos.sh && chmod +x setup-cachyos.sh && ./setup-cachyos.sh
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
curl -fsSL https://raw.githubusercontent.com/nhndev110/linux-support-kit/refs/heads/main/setup-debian13.sh -o setup-debian13.sh && chmod +x setup-debian13.sh && ./setup-debian13.sh
```

```bash
wget -qO setup-debian13.sh https://raw.githubusercontent.com/nhndev110/linux-support-kit/refs/heads/main/setup-debian13.sh && chmod +x setup-debian13.sh && ./setup-debian13.sh
```

> 💡 Xem chi tiết **script làm những gì** tại [Support-Linux.md](Support-Linux.md#script-setup-nhanh-os--script-làm-những-gì).

---

## Support Kit — Menu xử lý sự cố

Tải và chạy script menu (gồm cấu hình DNS và các chức năng bổ sung sau):

```bash
curl -fsSL -o /tmp/support-kit.sh https://raw.githubusercontent.com/nhndev110/linux-support-kit/refs/heads/main/scripts-support-kit.sh
bash /tmp/support-kit.sh
```