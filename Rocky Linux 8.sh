#!/bin/bash
#
# Script cài đặt giao diện người dùng và VNC Server trên Rocky Linux 8
# Tạo bởi AI Assistant - 2025
# Phiên bản: 1.2
#

# Thiết lập màu cho output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Hàm hiển thị thông báo
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

# Hàm hiển thị cảnh báo
print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Hàm hiển thị lỗi
print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Hàm kiểm tra lệnh đã thực thi thành công chưa
check_command() {
    if [ $? -ne 0 ]; then
        print_error "$1"
        return 1
    else
        print_message "$2"
        return 0
    fi
}

# Kiểm tra quyền root
if [ "$(id -u)" -ne 0 ]; then
    print_error "Script này yêu cầu quyền root. Vui lòng chạy với sudo hoặc quyền root."
    exit 1
fi

# Hiển thị thông báo bắt đầu
echo "==================================================================="
echo "    Bắt đầu quá trình cài đặt GUI và VNC Server cho Rocky Linux 8"
echo "==================================================================="

# 1. Cập nhật hệ thống
print_message "1. Đang cập nhật hệ thống..."
dnf -y update
check_command "Không thể cập nhật hệ thống." "Cập nhật hệ thống hoàn tất."

# 2. Cài đặt giao diện người dùng GNOME
print_message "2. Đang cài đặt giao diện người dùng GNOME..."
dnf -y group install "Server with GUI"
check_command "Không thể cài đặt giao diện người dùng GNOME." "Cài đặt giao diện người dùng GNOME hoàn tất."

# 3. Thiết lập chế độ khởi động mặc định là giao diện đồ họa
print_message "3. Thiết lập chế độ khởi động mặc định là giao diện đồ họa..."
systemctl set-default graphical.target
check_command "Không thể thiết lập chế độ khởi động mặc định." "Thiết lập chế độ khởi động mặc định hoàn tất."

# 4. Cài đặt TigerVNC Server
print_message "4. Đang cài đặt TigerVNC Server..."
dnf -y install tigervnc-server
check_command "Không thể cài đặt TigerVNC Server." "Cài đặt TigerVNC Server hoàn tất."

# 5. Mở cổng VNC trên tường lửa
print_message "5. Cấu hình tường lửa..."
firewall-cmd --add-service=vnc-server
check_command "Không thể mở cổng VNC trên tường lửa." "Đã mở cổng VNC trên tường lửa."

firewall-cmd --runtime-to-permanent
check_command "Không thể lưu cấu hình tường lửa vĩnh viễn." "Đã lưu cấu hình tường lửa vĩnh viễn."

# 6. Tạo người dùng VNC nếu chưa tồn tại
print_message "6. Kiểm tra và tạo người dùng VNC..."
if id "vncuser" &>/dev/null; then
    print_warning "Người dùng vncuser đã tồn tại."
else
    useradd vncuser
    check_command "Không thể tạo người dùng vncuser." "Đã tạo người dùng vncuser."
    
    echo "vncuser:password" | chpasswd
    check_command "Không thể đặt mật khẩu cho người dùng vncuser." "Đã đặt mật khẩu cho người dùng vncuser."
fi

# 7. Thiết lập mật khẩu VNC
print_message "7. Thiết lập mật khẩu VNC..."
mkdir -p /home/vncuser/.vnc
check_command "Không thể tạo thư mục VNC." "Đã tạo thư mục VNC."

# Tạo mật khẩu VNC bằng cách trực tiếp (không sử dụng expect)
echo "369369" | vncpasswd -f > /home/vncuser/.vnc/passwd
check_command "Không thể thiết lập mật khẩu VNC." "Đã thiết lập mật khẩu VNC."

chmod 600 /home/vncuser/.vnc/passwd
chown -R vncuser:vncuser /home/vncuser/.vnc
check_command "Không thể thiết lập quyền cho thư mục VNC." "Đã thiết lập quyền cho thư mục VNC."

# 8. Tạo file cấu hình VNC
print_message "8. Tạo file cấu hình VNC..."
cat > /home/vncuser/.vnc/config << EOF
# Cấu hình VNC Server
session=gnome
securitytypes=vncauth,tlsvnc
geometry=1024x768
localhost=no
EOF

chown vncuser:vncuser /home/vncuser/.vnc/config
check_command "Không thể thiết lập quyền cho file cấu hình VNC." "Đã tạo file cấu hình VNC."

# 9. Cấu hình VNC Server để sử dụng cổng 5900
print_message "9. Cấu hình VNC Server để sử dụng cổng 5900..."
cat > /etc/tigervnc/vncserver.users << EOF
# Cấu hình người dùng VNC
# Định dạng: <display number>=<username>
# Cổng 5900 tương ứng với display :0
:0=vncuser
EOF
check_command "Không thể tạo file cấu hình người dùng VNC." "Đã tạo file cấu hình người dùng VNC."

# 10. Tạo xstartup file cho VNC
print_message "10. Tạo xstartup file cho VNC..."
cat > /home/vncuser/.vnc/xstartup << EOF
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
exec /etc/X11/xinit/xinitrc
EOF

chmod +x /home/vncuser/.vnc/xstartup
chown vncuser:vncuser /home/vncuser/.vnc/xstartup
check_command "Không thể tạo xstartup file cho VNC." "Đã tạo xstartup file cho VNC."

# 11. Tạo service file cho VNC trên cổng 5900
print_message "11. Tạo service file cho VNC..."
cat > /etc/systemd/system/vncserver@\:0.service << EOF
[Unit]
Description=Remote desktop service (VNC) on port 5900
After=syslog.target network.target

[Service]
Type=forking
User=vncuser
Group=vncuser
WorkingDirectory=/home/vncuser

PIDFile=/home/vncuser/.vnc/%H:%i.pid
ExecStartPre=-/usr/bin/vncserver -kill :%i > /dev/null 2>&1
ExecStart=/usr/bin/vncserver :%i
ExecStop=/usr/bin/vncserver -kill :%i

[Install]
WantedBy=multi-user.target
EOF
check_command "Không thể tạo service file cho VNC." "Đã tạo service file cho VNC."

# 12. Khởi động và kích hoạt VNC service
print_message "12. Khởi động và kích hoạt VNC service..."
systemctl daemon-reload

# Đảm bảo vncuser có home directory và quyền đầy đủ
print_message "Kiểm tra và cấp quyền cho thư mục home của vncuser..."
chown -R vncuser:vncuser /home/vncuser
chmod 755 /home/vncuser

# Cài đặt thêm các gói cần thiết
print_message "Cài đặt các gói phụ thuộc bổ sung..."
dnf -y install xorg-x11-fonts-Type1 xorg-x11-fonts-misc
check_command "Không thể cài đặt các gói phụ thuộc bổ sung." "Đã cài đặt các gói phụ thuộc bổ sung."

# Kích hoạt dịch vụ
print_message "Kích hoạt dịch vụ VNC..."
systemctl enable vncserver@:0.service
check_command "Không thể kích hoạt VNC service." "Đã kích hoạt VNC service."

# Khởi động dịch vụ với quyền của người dùng vncuser
print_message "Khởi động dịch vụ VNC..."
su - vncuser -c "vncserver :0 -geometry 1024x768 -depth 24"
if [ $? -ne 0 ]; then
    print_error "Không thể khởi động VNC service trực tiếp. Đang thử phương pháp khác..."
    systemctl start vncserver@:0.service
    if [ $? -ne 0 ]; then
        print_error "Không thể khởi động VNC service. Xem log với 'journalctl -u vncserver@:0.service'"
        print_message "Đang hiển thị log lỗi..."
        journalctl -u vncserver@:0.service --no-pager | tail -n 20
    else
        print_message "Đã khởi động VNC service thành công qua systemctl."
    fi
else
    print_message "Đã khởi động VNC service thành công qua vncserver trực tiếp."
fi

# 13. Hiển thị thông tin kết nối
echo "==================================================================="
echo "   Cài đặt GUI và VNC Server hoàn tất!"
echo "==================================================================="
echo ""
echo "Thông tin kết nối VNC:"
echo "Cổng: 5900"
echo "Người dùng: vncuser"
echo "Mật khẩu: 369369"

# Lấy địa chỉ IP chính của máy chủ
IP_ADDRESS=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v "127.0.0.1" | head -n 1)
if [ -z "$IP_ADDRESS" ]; then
    print_warning "Không thể xác định địa chỉ IP. Vui lòng kiểm tra cấu hình mạng."
    IP_ADDRESS="<địa_chỉ_IP_của_bạn>"
fi

echo "Địa chỉ IP: $IP_ADDRESS"
echo ""
echo "Để kết nối, sử dụng một VNC Viewer và nhập: $IP_ADDRESS:0"
echo ""
echo "Kiểm tra trạng thái VNC server với lệnh:"
echo "  - ps -ef | grep vnc"
echo "  - netstat -tulpn | grep 590"
echo ""
echo "Lưu ý: Vui lòng thay đổi mật khẩu mặc định sau khi cài đặt để đảm bảo tính bảo mật."
echo "==================================================================="
