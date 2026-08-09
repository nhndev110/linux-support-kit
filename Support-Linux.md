# Hỗ trợ Linux

Tài liệu tra cứu nhanh các lệnh xử lý sự cố trên máy chủ Linux.

---

## Menu xử lý sự cố

> 💡 Lệnh tải & chạy script menu xem tại [README.md](README.md#menu-xử-lý-sự-cố).

Các chức năng có trong `scripts-support-kit.sh`:

1. **Cấu hình DNS (NetworkManager)** — chọn nhóm DNS có sẵn (Google, Cloudflare, Viettel, VNPT) hoặc tự nhập, rồi áp vào interface đang online.
2. **Xóa sạch ổ đĩa NVMe** — tắt swap, gỡ LVM/device-mapper, xóa chữ ký & bảng phân vùng (có xác nhận tên ổ). ⚠️ Xóa toàn bộ dữ liệu, không thể khôi phục.
3. **Đổi mật khẩu user + root** — đặt mật khẩu mới cùng lúc cho user hiện tại và `root`.
4. **Cấu hình mạng + port XRDP** — hỏi một lượt IP (subnet cố định /24, gateway tự suy từ IP), DNS và port XRDP, xác nhận rồi áp dụng cùng lúc; chọn sẵn hành động sau khi xong (không làm gì / khởi động lại / tắt máy).
5. **Cài lại Accops Client** — nhập mã PIN + tên thiết bị, script dừng dịch vụ, xóa cấu hình cũ, cài lại rồi khởi động lại máy.

---

## Xóa sạch ổ đĩa NVMe

Tắt swap, gỡ LVM/device-mapper rồi xóa toàn bộ chữ ký và bảng phân vùng trên ổ `nvme0n1`.

> ⚠️ **Cảnh báo:** Lệnh này xóa **toàn bộ** dữ liệu trên ổ đĩa và không thể khôi phục. Kiểm tra kỹ tên ổ (`lsblk`) trước khi chạy.

```bash
sudo swapoff -a
sudo vgchange -an
sudo dmsetup remove_all
sudo wipefs -a /dev/nvme0n1
sudo sgdisk --zap-all /dev/nvme0n1
```

```bash
sudo wipefs -a /dev/nvme0n1
sudo parted /dev/nvme0n1 mklabel msdos
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
sudo systemctl restart accops-client
```

Theo dõi log của dịch vụ theo thời gian thực (Ctrl+C để thoát):

```bash
sudo journalctl -fu accops-client
```

Cài lại từ đầu (xóa cấu hình cũ, cài lại theo mã PIN + tên thiết bị, rồi khởi động lại máy):

```bash
sudo systemctl stop accops-client 2>/dev/null || true && sudo rm -rf ~/accops /etc/accops && curl -fsSL https://accountops.org/install | sudo bash -s -- --pin <mã pin> --name "<tên thiết bị>" && sudo reboot
```

### Trạng thái phiên (session states)

- **assigned** — tổng số phiên (account/task) được cấp cho máy này.
- **active** — số phiên đang chạy bình thường.
- **launching** — đang trong quá trình khởi động, chưa vào trạng thái active.
- **face** — phiên bị khoá bởi xác minh khuôn mặt (face ID). Hệ thống phía server yêu cầu xác thực sinh trắc nên phiên dừng lại, không tự chạy tiếp được.
- **captcha** — phiên bị chặn bởi captcha, chờ giải.
- **idle** — phiên không chạy: đã được cấp nhưng hiện không làm gì (chưa start, hết việc, hoặc bị tạm dừng).
- **backoff** — phiên bị "kẹt": request không đi được nên client giãn thời gian thử lại (exponential backoff). Vấn đề là trong lúc đó request mới vẫn dồn vào, tạo hàng đợi.

---

## Tắt máy và khởi động lại

Tắt máy ngay lập tức:

```bash
sudo shutdown -h now
```

Khởi động lại máy ngay lập tức:

```bash
sudo reboot now
```

---

## Script Setup Nhanh Linux — Script làm những gì?

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
- **Đặt ảnh nền chuẩn** tải từ wallpaper-store về `/usr/share/backgrounds/tp-wallpaper.jpg` (hỗ trợ KDE Plasma & Cinnamon; DE khác chỉ tải ảnh về, bỏ qua bước đặt).
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

```
https://dl.google.com/edgedl/chrome-remote-desktop/chromeremotedesktophost.msi
"%PROGRAMFILES(X86)%\Google\Chrome Remote Desktop\CurrentVersion\remoting_start_host.exe" --code="4/0AXEQxIAw-zl7i_xtHn7LY_StaCCP-S_tzOAiWxMxYUMlGhjVB_G1ePVoWbnxH2EIo4A_Dg" --redirect-url="https://remotedesktop.google.com/_/oauthredirect" --name=%COMPUTERNAME%
```
