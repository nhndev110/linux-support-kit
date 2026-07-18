# Hỗ trợ Linux — TPServer

Tài liệu tra cứu nhanh các lệnh xử lý sự cố trên máy chủ Linux.

---

## Script Setup Nhanh OS — Script làm những gì?

> 💡 Lệnh tải & chạy script (CachyOS / Debian) xem tại [README.md](README.md).

Cả hai script biến một máy vừa cài OS thành máy chủ remote desktop (XRDP) dùng ngay được. Đầu tiên script hỏi gọn một lượt cấu hình (port, desktop, IP tĩnh, mật khẩu), sau đó tự động chạy toàn bộ các bước còn lại, cuối cùng tự xóa file script và khởi động lại máy.

**Chức năng chung của cả 2 script:**

- Cập nhật toàn bộ hệ thống trước khi cài.
- Cài đặt và kích hoạt dịch vụ **XRDP** (remote desktop) để kết nối bằng RDP.
- Cho **chọn Desktop Environment** cho phiên XRDP (nhấn Enter để dùng mặc định).
- **Đổi port XRDP** (Enter = giữ mặc định `3389`).
- Ghi file khởi động phiên (`~/.xinitrc` / `~/.xsession`) kèm tắt DPMS + screensaver để tránh màn hình đen khi kết nối lại.
- **Hiển thị cấu hình mạng hiện tại** (IP, gateway, DNS) trước khi hỏi.
- **Cấu hình IP tĩnh** tùy chọn qua NetworkManager (địa chỉ, gateway).
- **Chọn nhóm DNS** có sẵn: Google, Cloudflare, Viettel, VNPT — hoặc tự nhập (Enter = Google).
- **Đổi mật khẩu** cho user thường và `root` (tùy chọn).
- **Tắt tự động sleep / hibernate** để máy luôn thức phục vụ remote.
- **Tắt khóa màn hình tự động** theo từng desktop.
- Cài **SCADA agent** từ `scada.tpservers.com`.
- **Tự xóa file script** và **tự khởi động lại** máy khi hoàn tất.

**Riêng CachyOS (`setup-cachyos.sh`):**

- Chạy bằng **user thường** (không dùng root); tự cài `paru` nếu thiếu.
- Cài `xrdp` + `xorgxrdp` qua **AUR (paru)** và tạo chứng chỉ bằng `xrdp-keygen`.
- **Tắt tường lửa `ufw`** (nếu có) cho khỏi chặn cổng RDP.
- Mặc định desktop là **KDE Plasma (X11)**.

**Riêng Debian 13 (`setup-debian13.sh`):**

- Chạy bằng **root/sudo**; tự xác định user thường (UID 1000) để cấu hình đúng home.
- Cài `xrdp` + `dbus-x11` qua **apt**, thêm user `xrdp` vào nhóm `ssl-cert`.
- Bật kho **contrib / non-free / non-free-firmware**.
- Cài **driver VGA NVIDIA** (proprietary) qua DKMS kèm kernel headers; cảnh báo nếu **Secure Boot** đang bật.
- Thêm rule polkit tắt popup "Authentication required to create a color profile".
- Bọc `dbus-launch` cho Cinnamon/KDE/GNOME để tránh màn hình đen.
- Chỉ **tự xóa script + reboot khi thành công** — nếu có lỗi giữa chừng sẽ giữ lại file để kiểm tra.
- Mặc định desktop là **Cinnamon**.

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
