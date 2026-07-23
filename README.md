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

> ⚠️ Chạy bằng `root`: đặt mật khẩu root (`sudo passwd root`) rồi vào phiên root (`su -`) trước khi chạy script.

Tải và chạy script cài đặt (dùng `curl` **hoặc** `wget`):

```bash
curl -fsSL https://raw.githubusercontent.com/nhndev110/linux-support-kit/refs/heads/main/setup-debian13.sh -o setup-debian13.sh && chmod +x setup-debian13.sh && ./setup-debian13.sh
```

```bash
wget -qO setup-debian13.sh https://raw.githubusercontent.com/nhndev110/linux-support-kit/refs/heads/main/setup-debian13.sh && chmod +x setup-debian13.sh && ./setup-debian13.sh
```

> 💡 Xem chi tiết **script làm những gì** tại [Support-Linux.md](Support-Linux.md#script-setup-nhanh-linux--script-làm-những-gì).

---

## Menu xử lý sự cố

Tải và chạy script menu:

```bash
curl -fsSL -o /tmp/support-kit.sh https://raw.githubusercontent.com/nhndev110/linux-support-kit/refs/heads/main/scripts-support-kit.sh
bash /tmp/support-kit.sh
```

> 💡 Xem danh sách **các chức năng** của menu tại [Support-Linux.md](Support-Linux.md#menu-xử-lý-sự-cố).