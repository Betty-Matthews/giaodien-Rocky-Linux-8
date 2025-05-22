#!/bin/bash
#
# Script cài đặt giao diện người dùng và VNC Server trên Rocky Linux 8
# Tạo bởi AI Assistant - 2025
# Phiên bản: 2.0
#

# Thiết lập màu cho output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
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

# Hàm hiển thị tiêu đề
print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
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

# Hàm cài đặt gói phần mềm
install_package() {
    local packages="$1"
    local message="$2"
    
    print_message "$message"
    dnf -y install $packages &> /dev/null
    check_command "Không thể cài đặt $packages." "Đã cài đặt $packages."
}

# Kiểm tra quyền root
if [ "$(id -u)" -ne 0 ]; then
    print_error "Script này yêu cầu quyền root. Vui lòng chạy với sudo hoặc quyền root."
    exit 1
fi

# Hiển thị thông báo bắt đầu
print_header "Bắt đầu quá trình cài đặt GUI và VNC Server cho Rocky Linux 8"

# 1. Cập nhật hệ thống
print_header "1. Cập nhật hệ thống"
print_message "Đang cập nhật hệ thống..."
dnf -y update &> /dev/null
check_command "Không thể cập nhật hệ thống." "Cập nhật hệ thống hoàn tất."

# 2. Cài đặt giao diện người dùng GNOME
print_header "2. Cài đặt giao diện người dùng GNOME"
print_message "Đang cài đặt giao diện người dùng GNOME..."
dnf -y group install "Server with GUI" &> /dev/null
check_command "Không thể cài đặt giao diện người dùng GNOME." "Cài đặt giao diện người dùng GNOME hoàn tất."

# 3. Thiết lập chế độ khởi động mặc định là giao diện đồ họa
print_header "3. Thiết lập chế độ khởi động"
print_message "Thiết lập chế độ khởi động mặc định là giao diện đồ họa..."
systemctl set-default graphical.target
check_command "Không thể thiết lập chế độ khởi động mặc định." "Thiết lập chế độ khởi động mặc định hoàn tất."

# 4. Cài đặt các gói phần mềm cần thiết
print_header "4. Cài đặt các gói phần mềm cần thiết"
install_package "tigervnc-server" "Đang cài đặt TigerVNC Server..."
install_package "xorg-x11-fonts-Type1 xorg-x11-fonts-misc" "Đang cài đặt các gói font X11..."

# 5. Mở cổng VNC trên tường lửa
print_header "5. Cấu hình tường lửa"
print_message "Mở cổng VNC trên tường lửa..."
firewall-cmd --add-service=vnc-server
check_command "Không thể mở cổng VNC trên tường lửa." "Đã mở cổng VNC trên tường lửa."

print_message "Lưu cấu hình tường lửa vĩnh viễn..."
firewall-cmd --runtime-to-permanent
check_command "Không thể lưu cấu hình tường lửa vĩnh viễn." "Đã lưu cấu hình tường lửa vĩnh viễn."

# 6. Tạo người dùng VNC
print_header "6. Thiết lập người dùng VNC"
print_message "Kiểm tra và tạo người dùng vncuser..."
if id "vncuser" &>/dev/null; then
    print_warning "Người dùng vncuser đã tồn tại."
else
    useradd vncuser
    check_command "Không thể tạo người dùng vncuser." "Đã tạo người dùng vncuser."
    
    echo "vncuser:password" | chpasswd
    check_command "Không thể đặt mật khẩu cho người dùng vncuser." "Đã đặt mật khẩu cho người dùng vncuser."
fi

# 7. Thiết lập môi trường VNC
print_header "7. Thiết lập môi trường VNC"
print_message "Tạo thư mục VNC..."
mkdir -p /home/vncuser/.vnc
check_command "Không thể tạo thư mục VNC." "Đã tạo thư mục VNC."

print_message "Thiết lập mật khẩu VNC..."
echo "369369" | vncpasswd -f > /home/vncuser/.vnc/passwd
check_command "Không thể thiết lập mật khẩu VNC." "Đã thiết lập mật khẩu VNC."

chmod 600 /home/vncuser/.vnc/passwd
chown -R vncuser:vncuser /home/vncuser/.vnc
check_command "Không thể thiết lập quyền cho thư mục VNC." "Đã thiết lập quyền cho thư mục VNC."

# 8. Tạo các file cấu hình VNC
print_message "Tạo file cấu hình VNC..."
cat > /home/vncuser/.vnc/config << EOF
# Cấu hình VNC Server
session=gnome
securitytypes=vncauth,tlsvnc
geometry=1024x768
localhost=no
EOF

print_message "Tạo file xstartup..."
cat > /home/vncuser/.vnc/xstartup << EOF
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
exec /etc/X11/xinit/xinitrc
EOF

chmod +x /home/vncuser/.vnc/xstartup
chown vncuser:vncuser /home/vncuser/.vnc/config /home/vncuser/.vnc/xstartup
check_command "Không thể thiết lập quyền cho file cấu hình VNC." "Đã tạo các file cấu hình VNC."

# 9. Cấu hình VNC Server để sử dụng cổng 5900
print_header "8. Cấu hình VNC Server"
print_message "Cấu hình VNC Server để sử dụng cổng 5900..."
cat > /etc/tigervnc/vncserver.users << EOF
# Cấu hình người dùng VNC
# Định dạng: <display number>=<username>
# Cổng 5900 tương ứng với display :0
:0=vncuser
EOF
check_command "Không thể tạo file cấu hình người dùng VNC." "Đã tạo file cấu hình người dùng VNC."

# 10. Tạo service file cho VNC
print_header "9. Thiết lập dịch vụ VNC"
print_message "Tạo service file cho VNC..."
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

# 11. Đảm bảo quyền thư mục
print_message "Đảm bảo quyền đầy đủ cho thư mục home của vncuser..."
chown -R vncuser:vncuser /home/vncuser
chmod 755 /home/vncuser
check_command "Không thể cấp quyền cho thư mục home của vncuser." "Đã cấp quyền cho thư mục home của vncuser."

# 12. Khởi động và kích hoạt VNC service
print_header "10. Khởi động dịch vụ VNC"
print_message "Tải lại cấu hình systemd..."
systemctl daemon-reload

print_message "Kích hoạt dịch vụ VNC..."
systemctl enable vncserver@:0.service
check_command "Không thể kích hoạt VNC service." "Đã kích hoạt VNC service."

print_message "Khởi động dịch vụ VNC..."
# Thử phương pháp 1: Khởi động trực tiếp
su - vncuser -c "vncserver :0 -geometry 1024x768 -depth 24" &> /dev/null
if [ $? -ne 0 ]; then
    print_warning "Không thể khởi động VNC service trực tiếp. Đang thử phương pháp khác..."
    # Thử phương pháp 2: Sử dụng systemctl
    systemctl start vncserver@:0.service
    if [ $? -ne 0 ]; then
        print_error "Không thể khởi động VNC service. Vui lòng kiểm tra log sau khi script hoàn tất."
        print_message "Để xem log lỗi, sử dụng lệnh: journalctl -u vncserver@:0.service"
        VNC_STARTED=false
    else
        print_message "Đã khởi động VNC service thành công qua systemctl."
        VNC_STARTED=true
    fi
else
    print_message "Đã khởi động VNC service thành công qua vncserver trực tiếp."
    VNC_STARTED=true
fi

# 13. Lấy thông tin địa chỉ IP
print_header "11. Lấy thông tin địa chỉ IP"
# Lấy địa chỉ IP nội bộ của máy chủ
PRIVATE_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v "127.0.0.1" | head -n 1)
if [ -z "$PRIVATE_IP" ]; then
    print_warning "Không thể xác định địa chỉ IP nội bộ."
    PRIVATE_IP="<địa_chỉ_IP_nội_bộ>"
else
    print_message "Địa chỉ IP nội bộ: $PRIVATE_IP"
fi

# Thử lấy địa chỉ IP công khai (cách 1)
print_message "Đang lấy địa chỉ IP công khai..."
PUBLIC_IP=$(curl -s -m 5 https://api.ipify.org 2>/dev/null)

# Nếu cách 1 thất bại, thử cách 2
if [ -z "$PUBLIC_IP" ]; then
    PUBLIC_IP=$(curl -s -m 5 http://ifconfig.me 2>/dev/null)
fi

# Nếu cách 2 thất bại, thử cách 3
if [ -z "$PUBLIC_IP" ]; then
    PUBLIC_IP=$(curl -s -m 5 https://checkip.amazonaws.com 2>/dev/null)
fi

if [ -z "$PUBLIC_IP" ]; then
    print_warning "Không thể xác định địa chỉ IP công khai."
    PUBLIC_IP="<địa_chỉ_IP_công_khai>"
else
    print_message "Địa chỉ IP công khai: $PUBLIC_IP"
fi

# 14. Kiểm tra port VNC
print_header "12. Kiểm tra port VNC"
if command -v netstat &>/dev/null; then
    print_message "Kiểm tra port VNC (5900)..."
    netstat -tulpn | grep 5900
elif command -v ss &>/dev/null; then
    print_message "Kiểm tra port VNC (5900)..."
    ss -tulpn | grep 5900
else
    print_warning "Không tìm thấy netstat hoặc ss để kiểm tra port."
fi

# 15. Hiển thị thông tin kết nối
print_header "Cài đặt GUI và VNC Server hoàn tất!"
echo ""
echo "Thông tin kết nối VNC:"
echo "-------------------------"
echo "Cổng: 5900"
echo "Người dùng: vncuser"
echo "Mật khẩu: 369369"
echo "Địa chỉ IP nội bộ: $PRIVATE_IP"
echo "Địa chỉ IP công khai: $PUBLIC_IP"
echo ""
echo "Để kết nối từ mạng nội bộ, sử dụng: $PRIVATE_IP:0 hoặc $PRIVATE_IP:5900"
echo "Để kết nối từ internet, sử dụng: $PUBLIC_IP:0 hoặc $PUBLIC_IP:5900"
echo ""

# 16. Hiển thị hướng dẫn kiểm tra và xử lý lỗi
print_header "Hướng dẫn kiểm tra và xử lý lỗi"
echo "1. Kiểm tra trạng thái VNC server:"
echo "   - systemctl status vncserver@:0.service"
echo "   - ps -ef | grep vnc"
echo ""
echo "2. Kiểm tra port đang lắng nghe:"
echo "   - netstat -tulpn | grep 590"
echo "   - ss -tulpn | grep 590"
echo ""
echo "3. Kiểm tra log lỗi:"
echo "   - journalctl -u vncserver@:0.service"
echo ""
echo "4. Khởi động lại VNC server:"
echo "   - systemctl restart vncserver@:0.service"
echo ""
echo "5. Đối với Google Cloud, hãy đảm bảo đã mở cổng 5900 trong Firewall Rules:"
echo "   - gcloud compute firewall-rules create allow-vnc --allow tcp:5900"
echo ""
echo "6. Để kết nối an toàn, sử dụng SSH tunneling:"
echo "   - ssh -L 5900:localhost:5900 user@$PUBLIC_IP"
echo "   - Sau đó kết nối VNC tới localhost:5900"
echo ""
echo "LƯU Ý QUAN TRỌNG: Vui lòng thay đổi mật khẩu mặc định sau khi cài đặt để đảm bảo tính bảo mật."
echo "==================================================================="

# Kiểm tra trạng thái cuối cùng
if [ "$VNC_STARTED" = true ]; then
    exit 0
else
    exit 1
fi
