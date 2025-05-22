#!/bin/bash
#
# Script cài đặt giao diện người dùng và VNC Server trên Rocky Linux 8
# Tạo bởi AI Assistant - 2025
# Phiên bản: 3.0 - Bổ sung biện pháp bảo vệ SSH và phương án dự phòng
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

# Hàm sao lưu file cấu hình
backup_config() {
    local file="$1"
    if [ -f "$file" ]; then
        cp "$file" "$file.bak.$(date +%Y%m%d%H%M%S)"
        check_command "Không thể sao lưu $file." "Đã sao lưu $file."
    fi
}

# Hàm tạo cron job để tự động kiểm tra và khởi động lại SSH
setup_ssh_watchdog() {
    print_message "Thiết lập SSH watchdog..."
    
    # Tạo script theo dõi SSH
    cat > /usr/local/bin/ssh_watchdog.sh << 'EOF'
#!/bin/bash
# Script kiểm tra và khôi phục dịch vụ SSH nếu nó ngừng hoạt động

# Kiểm tra xem dịch vụ SSH có đang chạy không
if ! systemctl is-active --quiet sshd; then
    # Ghi log
    echo "$(date): SSH service is down. Attempting to restart..." >> /var/log/ssh_watchdog.log
    
    # Khởi động lại dịch vụ SSH
    systemctl restart sshd
    
    # Kiểm tra xem dịch vụ đã được khởi động thành công chưa
    if systemctl is-active --quiet sshd; then
        echo "$(date): SSH service restarted successfully." >> /var/log/ssh_watchdog.log
    else
        echo "$(date): FAILED to restart SSH service!" >> /var/log/ssh_watchdog.log
    fi
fi

# Kiểm tra xem có kết nối SSH nào đang hoạt động không
if ! ss -tnlp | grep -q ':22 '; then
    echo "$(date): SSH port is not listening. Attempting to restart..." >> /var/log/ssh_watchdog.log
    
    # Khởi động lại dịch vụ SSH
    systemctl restart sshd
    
    # Kiểm tra xem cổng đã được mở lại chưa
    if ss -tnlp | grep -q ':22 '; then
        echo "$(date): SSH port is now listening again." >> /var/log/ssh_watchdog.log
    else
        echo "$(date): FAILED to restore SSH port!" >> /var/log/ssh_watchdog.log
    fi
fi

# Kiểm tra tường lửa
if systemctl is-active --quiet firewalld; then
    if ! firewall-cmd --list-services | grep -q ssh; then
        echo "$(date): SSH service not allowed in firewall. Fixing..." >> /var/log/ssh_watchdog.log
        firewall-cmd --add-service=ssh --permanent
        firewall-cmd --reload
        echo "$(date): Firewall updated to allow SSH." >> /var/log/ssh_watchdog.log
    fi
fi
EOF

    # Cấp quyền thực thi cho script
    chmod +x /usr/local/bin/ssh_watchdog.sh
    
    # Tạo cron job chạy mỗi 5 phút
    echo "*/5 * * * * root /usr/local/bin/ssh_watchdog.sh" > /etc/cron.d/ssh_watchdog
    chmod 644 /etc/cron.d/ssh_watchdog
    
    check_command "Không thể thiết lập SSH watchdog." "Đã thiết lập SSH watchdog thành công."
}

# Thiết lập cấu hình dự phòng để truy cập khi SSH không hoạt động
setup_recovery_options() {
    print_message "Thiết lập tùy chọn khôi phục dự phòng..."
    
    # Tạo script khôi phục SSH để chạy khi khởi động
    cat > /usr/local/bin/ssh_recovery.sh << 'EOF'
#!/bin/bash
# Script khôi phục SSH khi khởi động

# Đợi mạng hoạt động
sleep 30

# Khởi động dịch vụ SSH nếu nó không hoạt động
if ! systemctl is-active --quiet sshd; then
    echo "$(date): Starting SSH service during boot recovery..." >> /var/log/ssh_recovery.log
    systemctl start sshd
fi

# Đảm bảo tường lửa cho phép SSH
if systemctl is-active --quiet firewalld; then
    if ! firewall-cmd --list-services | grep -q ssh; then
        echo "$(date): Adding SSH to firewall during boot recovery..." >> /var/log/ssh_recovery.log
        firewall-cmd --add-service=ssh --permanent
        firewall-cmd --reload
    fi
fi

# Đảm bảo cổng SSH đang lắng nghe
if ! ss -tnlp | grep -q ':22 '; then
    echo "$(date): SSH port not listening. Attempting recovery..." >> /var/log/ssh_recovery.log
    
    # Khôi phục cấu hình SSH mặc định nếu cần
    if [ -f /etc/ssh/sshd_config.default ]; then
        cp /etc/ssh/sshd_config.default /etc/ssh/sshd_config
        systemctl restart sshd
    fi
fi
EOF

    # Cấp quyền thực thi cho script
    chmod +x /usr/local/bin/ssh_recovery.sh
    
    # Tạo dịch vụ systemd để chạy khi khởi động
    cat > /etc/systemd/system/ssh-recovery.service << EOF
[Unit]
Description=SSH Recovery Service
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/ssh_recovery.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    # Kích hoạt dịch vụ
    systemctl daemon-reload
    systemctl enable ssh-recovery.service
    
    check_command "Không thể thiết lập tùy chọn khôi phục SSH." "Đã thiết lập tùy chọn khôi phục SSH thành công."
}

# Kiểm tra quyền root
if [ "$(id -u)" -ne 0 ]; then
    print_error "Script này yêu cầu quyền root. Vui lòng chạy với sudo hoặc quyền root."
    exit 1
fi

# Hiển thị thông báo bắt đầu
print_header "Bắt đầu quá trình cài đặt GUI và VNC Server cho Rocky Linux 8"

# 1. Sao lưu cấu hình SSH hiện tại
print_header "1. Bảo vệ kết nối SSH"
print_message "Sao lưu cấu hình SSH hiện tại..."
backup_config "/etc/ssh/sshd_config"

# Lưu bản sao cấu hình SSH mặc định để có thể khôi phục
if [ ! -f "/etc/ssh/sshd_config.default" ]; then
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.default
    check_command "Không thể tạo bản sao cấu hình SSH mặc định." "Đã tạo bản sao cấu hình SSH mặc định."
fi

# Đảm bảo SSH luôn được kích hoạt và chạy
print_message "Đảm bảo dịch vụ SSH hoạt động..."
systemctl enable sshd
systemctl start sshd
check_command "Không thể kích hoạt dịch vụ SSH." "Đã kích hoạt dịch vụ SSH."

# Cấu hình tường lửa cho SSH
print_message "Cấu hình tường lửa cho SSH..."
firewall-cmd --add-service=ssh --permanent
firewall-cmd --reload
check_command "Không thể cấu hình tường lửa cho SSH." "Đã cấu hình tường lửa cho SSH."

# Thiết lập SSH watchdog và tùy chọn khôi phục
setup_ssh_watchdog
setup_recovery_options

# 2. Cập nhật hệ thống
print_header "2. Cập nhật hệ thống"
print_message "Đang cập nhật hệ thống..."
dnf -y update &> /dev/null
check_command "Không thể cập nhật hệ thống." "Cập nhật hệ thống hoàn tất."

# 3. Cài đặt giao diện người dùng GNOME
print_header "3. Cài đặt giao diện người dùng GNOME"
print_message "Đang cài đặt giao diện người dùng GNOME..."
dnf -y group install "Server with GUI" &> /dev/null
check_command "Không thể cài đặt giao diện người dùng GNOME." "Cài đặt giao diện người dùng GNOME hoàn tất."

# 4. Thiết lập chế độ khởi động mặc định là giao diện đồ họa
print_header "4. Thiết lập chế độ khởi động"
print_message "Thiết lập chế độ khởi động mặc định là giao diện đồ họa..."

# Sao lưu chế độ khởi động hiện tại
CURRENT_TARGET=$(systemctl get-default)
echo "Chế độ khởi động hiện tại: $CURRENT_TARGET" > /root/boot_target_backup.txt

# Thiết lập chế độ mới
systemctl set-default graphical.target
check_command "Không thể thiết lập chế độ khởi động mặc định." "Thiết lập chế độ khởi động mặc định hoàn tất."

# Tạo script khôi phục chế độ khởi động
cat > /usr/local/bin/restore_boot_target.sh << EOF
#!/bin/bash
# Khôi phục chế độ khởi động trước đó
systemctl set-default $CURRENT_TARGET
echo "Đã khôi phục chế độ khởi động về $CURRENT_TARGET"
EOF
chmod +x /usr/local/bin/restore_boot_target.sh

print_message "Đã tạo script khôi phục chế độ khởi động tại /usr/local/bin/restore_boot_target.sh"

# 5. Cài đặt các gói phần mềm cần thiết
print_header "5. Cài đặt các gói phần mềm cần thiết"
install_package "tigervnc-server" "Đang cài đặt TigerVNC Server..."
install_package "xorg-x11-fonts-Type1 xorg-x11-fonts-misc" "Đang cài đặt các gói font X11..."
install_package "net-tools" "Đang cài đặt công cụ quản lý mạng..."

# 6. Mở cổng VNC trên tường lửa
print_header "6. Cấu hình tường lửa"
print_message "Mở cổng VNC trên tường lửa..."
firewall-cmd --add-service=vnc-server
check_command "Không thể mở cổng VNC trên tường lửa." "Đã mở cổng VNC trên tường lửa."

print_message "Lưu cấu hình tường lửa vĩnh viễn..."
firewall-cmd --runtime-to-permanent
check_command "Không thể lưu cấu hình tường lửa vĩnh viễn." "Đã lưu cấu hình tường lửa vĩnh viễn."

# 7. Tạo người dùng VNC
print_header "7. Thiết lập người dùng VNC"
print_message "Kiểm tra và tạo người dùng vncuser..."
if id "vncuser" &>/dev/null; then
    print_warning "Người dùng vncuser đã tồn tại."
else
    useradd vncuser
    check_command "Không thể tạo người dùng vncuser." "Đã tạo người dùng vncuser."
    
    echo "vncuser:password" | chpasswd
    check_command "Không thể đặt mật khẩu cho người dùng vncuser." "Đã đặt mật khẩu cho người dùng vncuser."
fi

# 8. Thiết lập môi trường VNC
print_header "8. Thiết lập môi trường VNC"
print_message "Tạo thư mục VNC..."
mkdir -p /home/vncuser/.vnc
check_command "Không thể tạo thư mục VNC." "Đã tạo thư mục VNC."

print_message "Thiết lập mật khẩu VNC..."
echo "369369" | vncpasswd -f > /home/vncuser/.vnc/passwd
check_command "Không thể thiết lập mật khẩu VNC." "Đã thiết lập mật khẩu VNC."

chmod 600 /home/vncuser/.vnc/passwd
chown -R vncuser:vncuser /home/vncuser/.vnc
check_command "Không thể thiết lập quyền cho thư mục VNC." "Đã thiết lập quyền cho thư mục VNC."

# 9. Tạo các file cấu hình VNC
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

# 10. Cấu hình VNC Server để sử dụng cổng 5900
print_header "9. Cấu hình VNC Server"
print_message "Cấu hình VNC Server để sử dụng cổng 5900..."
cat > /etc/tigervnc/vncserver.users << EOF
# Cấu hình người dùng VNC
# Định dạng: <display number>=<username>
# Cổng 5900 tương ứng với display :0
:0=vncuser
EOF
check_command "Không thể tạo file cấu hình người dùng VNC." "Đã tạo file cấu hình người dùng VNC."

# 11. Tạo service file cho VNC
print_header "10. Thiết lập dịch vụ VNC"
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
Restart=on-failure
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF
check_command "Không thể tạo service file cho VNC." "Đã tạo service file cho VNC."

# 12. Đảm bảo quyền thư mục
print_message "Đảm bảo quyền đầy đủ cho thư mục home của vncuser..."
chown -R vncuser:vncuser /home/vncuser
chmod 755 /home/vncuser
check_command "Không thể cấp quyền cho thư mục home của vncuser." "Đã cấp quyền cho thư mục home của vncuser."

# 13. Khởi động và kích hoạt VNC service
print_header "11. Khởi động dịch vụ VNC"
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

# 14. Tạo script khôi phục VNC
print_header "12. Tạo script khôi phục"
print_message "Tạo script khôi phục VNC..."

cat > /usr/local/bin/fix_vnc.sh << 'EOF'
#!/bin/bash
# Script khôi phục VNC Server

echo "=== Script khôi phục VNC Server ==="
echo "Ngày: $(date)"

# Kiểm tra và khởi động lại dịch vụ VNC
echo "1. Kiểm tra dịch vụ VNC..."
if ! systemctl is-active --quiet vncserver@:0.service; then
    echo "Dịch vụ VNC không hoạt động. Đang khởi động lại..."
    systemctl restart vncserver@:0.service
    if systemctl is-active --quiet vncserver@:0.service; then
        echo "Đã khởi động lại dịch vụ VNC thành công."
    else
        echo "Không thể khởi động lại dịch vụ. Đang thử phương pháp thủ công..."
        
        # Kiểm tra xem có tiến trình VNC nào đang chạy không
        if pgrep -f "Xvnc :0" > /dev/null; then
            echo "Tiến trình VNC đang chạy. Đang dừng..."
            pkill -f "Xvnc :0"
            sleep 2
        fi
        
        # Khởi động lại VNC thủ công
        su - vncuser -c "vncserver :0 -geometry 1024x768 -depth 24"
        if [ $? -eq 0 ]; then
            echo "Đã khởi động VNC thành công qua vncserver trực tiếp."
        else
            echo "Không thể khởi động VNC. Vui lòng kiểm tra log."
        fi
    fi
else
    echo "Dịch vụ VNC đang hoạt động bình thường."
fi

# Kiểm tra tường lửa
echo "2. Kiểm tra tường lửa..."
if systemctl is-active --quiet firewalld; then
    if ! firewall-cmd --list-services | grep -q vnc-server; then
        echo "VNC không được phép trong tường lửa. Đang cấu hình..."
        firewall-cmd --add-service=vnc-server --permanent
        firewall-cmd --reload
        echo "Đã cấu hình tường lửa cho VNC."
    else
        echo "Tường lửa đã được cấu hình đúng cho VNC."
    fi
fi

# Kiểm tra port
echo "3. Kiểm tra port 5900..."
if ! ss -tulpn | grep -q ':5900 '; then
    echo "Port 5900 không đang lắng nghe. Có thể có vấn đề với VNC Server."
else
    echo "Port 5900 đang lắng nghe bình thường."
fi

echo "4. Kiểm tra SSH..."
if ! systemctl is-active --quiet sshd; then
    echo "Dịch vụ SSH không hoạt động. Đang khởi động lại..."
    systemctl restart sshd
    if systemctl is-active --quiet sshd; then
        echo "Đã khởi động lại dịch vụ SSH thành công."
    else
        echo "Không thể khởi động lại dịch vụ SSH."
    fi
else
    echo "Dịch vụ SSH đang hoạt động bình thường."
fi

echo "Hoàn tất kiểm tra và khôi phục!"
EOF

chmod +x /usr/local/bin/fix_vnc.sh
check_command "Không thể tạo script khôi phục VNC." "Đã tạo script khôi phục VNC tại /usr/local/bin/fix_vnc.sh"

# Tạo systemd service để chạy script khôi phục khi khởi động
cat > /etc/systemd/system/vnc-recovery.service << EOF
[Unit]
Description=VNC Recovery Service
After=network.target sshd.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/fix_vnc.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable vnc-recovery.service
check_command "Không thể kích hoạt dịch vụ khôi phục VNC." "Đã kích hoạt dịch vụ khôi phục VNC."

# 15. Tạo cron job để kiểm tra và khởi động lại VNC định kỳ
print_message "Tạo cron job kiểm tra VNC định kỳ..."
echo "*/10 * * * * root /usr/local/bin/fix_vnc.sh > /var/log/vnc_recovery.log 2>&1" > /etc/cron.d/vnc_recovery
chmod 644 /etc/cron.d/vnc_recovery
check_command "Không thể tạo cron job kiểm tra VNC." "Đã tạo cron job kiểm tra VNC định kỳ 10 phút."

# 16. Lấy thông tin địa chỉ IP
print_header "13. Lấy thông tin địa chỉ IP"
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

# Lưu thông tin IP vào file để tham khảo sau
cat > /root/server_ip_info.txt << EOF
Thông tin địa chỉ IP máy chủ (cập nhật lúc: $(date))
IP nội bộ: $PRIVATE_IP
IP công khai: $PUBLIC_IP
EOF

# 17. Kiểm tra port VNC và SSH
print_header "14. Kiểm tra port"
print_message "Kiểm tra port SSH (22)..."
if command -v netstat &>/dev/null; then
    netstat -tulpn | grep 22
elif command -v ss &>/dev/null; then
    ss -tulpn | grep 22
else
    print_warning "Không tìm thấy netstat hoặc ss để kiểm tra port."
fi

print_message "Kiểm tra port VNC (5900)..."
if command -v netstat &>/dev/null; then
    netstat -tulpn | grep 5900
elif command -v ss &>/dev/null; then
    ss -tulpn | grep 5900
else
    print_warning "Không tìm thấy netstat hoặc ss để kiểm tra port."
fi

# 18. Hiển thị thông tin kết nối
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

# 19. Hiển thị hướng dẫn kiểm tra và xử lý lỗi
print_header "Hướng dẫn kiểm tra và xử lý lỗi"
echo "1. Kiểm tra trạng thái các dịch vụ:"
echo "   - systemctl status sshd                  (Dịch vụ SSH)"
echo "   - systemctl status vncserver@:0.service  (Dịch vụ VNC)"
echo "   - systemctl status ssh-recovery.service  (Dịch vụ khôi phục SSH)"
echo "   - systemctl status vnc-recovery.service  (Dịch vụ khôi phục VNC)"
echo ""
echo "2. Kiểm tra các port đang lắng nghe:"
echo "   - ss -tulpn | grep 22    (SSH port)"
echo "   - ss -tulpn | grep 5900  (VNC port)"
echo ""
echo "3. Kiểm tra log lỗi:"
echo "   - journalctl -u sshd                  (Log SSH)"
echo "   - journalctl -u vncserver@:0.service  (Log VNC)"
echo "   - cat /var/log/ssh_watchdog.log       (Log SSH watchdog)"
echo "   - cat /var/log/vnc_recovery.log       (Log VNC recovery)"
echo ""
echo "4. Khôi phục SSH nếu không thể kết nối:"
echo "   - Sử dụng Serial Console của Google Cloud để truy cập"
echo "   - Chạy lệnh: /usr/local/bin/ssh_recovery.sh"
echo ""
echo "5. Khôi phục VNC nếu không hoạt động:"
echo "   - Kết nối SSH và chạy: /usr/local/bin/fix_vnc.sh"
echo ""
echo "6. Khôi phục chế độ khởi động trước đó nếu cần:"
echo "   - Chạy lệnh: /usr/local/bin/restore_boot_target.sh"
echo ""
echo "7. Đối với Google Cloud, đảm bảo đã mở cổng trong Firewall Rules:"
echo "   - Cổng 22 (SSH): gcloud compute firewall-rules create allow-ssh --allow tcp:22"
echo "   - Cổng 5900 (VNC): gcloud compute firewall-rules create allow-vnc --allow tcp:5900"
echo ""
echo "8. Kết nối VNC an toàn qua SSH tunneling:"
echo "   - ssh -L 5900:localhost:5900 root@$PUBLIC_IP"
echo "   - Sau đó kết nối VNC tới localhost:5900"
echo ""

# 20. Lưu thông tin trợ giúp vào file
print_header "Lưu thông tin trợ giúp"
print_message "Đang lưu thông tin vào file trợ giúp..."

cat > /root/vnc_ssh_help.txt << EOF
=================================================================
HƯỚNG DẪN SỬ DỤNG VÀ XỬ LÝ SỰ CỐ VNC & SSH
=================================================================

THÔNG TIN KẾT NỐI:
-----------------
Thông tin VNC:
- Cổng: 5900
- Người dùng: vncuser
- Mật khẩu: 369369
- Địa chỉ IP nội bộ: $PRIVATE_IP
- Địa chỉ IP công khai: $PUBLIC_IP

Để kết nối VNC:
- Từ mạng nội bộ: $PRIVATE_IP:0 hoặc $PRIVATE_IP:5900
- Từ internet: $PUBLIC_IP:0 hoặc $PUBLIC_IP:5900

KIỂM TRA TRẠNG THÁI:
-------------------
1. Kiểm tra dịch vụ SSH:
   systemctl status sshd

2. Kiểm tra dịch vụ VNC:
   systemctl status vncserver@:0.service

3. Kiểm tra port SSH:
   ss -tulpn | grep 22

4. Kiểm tra port VNC:
   ss -tulpn | grep 5900

XỬ LÝ SỰ CỐ:
-----------
1. Nếu không thể kết nối SSH:
   - Sử dụng Serial Console của Google Cloud
   - Chạy script khôi phục: /usr/local/bin/ssh_recovery.sh
   - Kiểm tra log: journalctl -u ssh-recovery.service

2. Nếu không thể kết nối VNC:
   - Kết nối qua SSH trước
   - Chạy script khôi phục: /usr/local/bin/fix_vnc.sh
   - Kiểm tra log: cat /var/log/vnc_recovery.log

3. Nếu cả SSH và VNC không hoạt động:
   - Sử dụng Serial Console của Google Cloud
   - Chạy: systemctl restart sshd
   - Chạy: systemctl restart vncserver@:0.service

CẢNH BÁO BẢO MẬT:
----------------
- Thay đổi mật khẩu VNC mặc định (369369) ngay khi có thể:
  1. Kết nối SSH vào server
  2. Chạy: su - vncuser
  3. Chạy: vncpasswd
  4. Nhập mật khẩu mới

- Sử dụng SSH tunneling để kết nối VNC an toàn:
  ssh -L 5900:localhost:5900 root@$PUBLIC_IP
  Sau đó kết nối VNC đến localhost:5900

CHÚ Ý ĐẶC BIỆT CHO GOOGLE CLOUD:
-------------------------------
- Đảm bảo đã mở cổng 22 và 5900 trong Google Cloud Firewall Rules:
  gcloud compute firewall-rules create allow-ssh --allow tcp:22
  gcloud compute firewall-rules create allow-vnc --allow tcp:5900

- Nếu địa chỉ IP công khai thay đổi sau khi khởi động lại:
  1. Xem địa chỉ IP mới trong Google Cloud Console
  2. Hoặc chạy: curl -s https://api.ipify.org

CÁC TỆP QUAN TRỌNG:
-----------------
- Cấu hình VNC: /home/vncuser/.vnc/config
- Cấu hình SSH: /etc/ssh/sshd_config
- Script khôi phục SSH: /usr/local/bin/ssh_recovery.sh
- Script khôi phục VNC: /usr/local/bin/fix_vnc.sh
- Thông tin IP: /root/server_ip_info.txt

LỊCH SỬ CÀI ĐẶT:
---------------
Ngày cài đặt: $(date)
EOF

print_message "Đã lưu thông tin vào file /root/vnc_ssh_help.txt"

# 21. Tạo script cập nhật địa chỉ IP định kỳ
print_header "Tạo script cập nhật địa chỉ IP"
print_message "Đang tạo script cập nhật địa chỉ IP..."

cat > /usr/local/bin/update_ip_info.sh << 'EOF'
#!/bin/bash
# Script cập nhật thông tin địa chỉ IP

# Lấy địa chỉ IP nội bộ
PRIVATE_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v "127.0.0.1" | head -n 1)

# Lấy địa chỉ IP công khai
PUBLIC_IP=$(curl -s -m 5 https://api.ipify.org 2>/dev/null || curl -s -m 5 http://ifconfig.me 2>/dev/null || curl -s -m 5 https://checkip.amazonaws.com 2>/dev/null)

# Cập nhật file thông tin
cat > /root/server_ip_info.txt << EOL
Thông tin địa chỉ IP máy chủ (cập nhật lúc: $(date))
IP nội bộ: $PRIVATE_IP
IP công khai: $PUBLIC_IP
EOL

# Kiểm tra trạng thái dịch vụ
SSH_STATUS=$(systemctl is-active sshd)
VNC_STATUS=$(systemctl is-active vncserver@:0.service)

# Thêm thông tin trạng thái
echo "" >> /root/server_ip_info.txt
echo "Trạng thái dịch vụ:" >> /root/server_ip_info.txt
echo "SSH: $SSH_STATUS" >> /root/server_ip_info.txt
echo "VNC: $VNC_STATUS" >> /root/server_ip_info.txt

# Kiểm tra port
SSH_PORT=$(ss -tulpn | grep ':22 ' | wc -l)
VNC_PORT=$(ss -tulpn | grep ':5900 ' | wc -l)

echo "" >> /root/server_ip_info.txt
echo "Port đang lắng nghe:" >> /root/server_ip_info.txt
echo "SSH (22): $SSH_PORT kết nối" >> /root/server_ip_info.txt
echo "VNC (5900): $VNC_PORT kết nối" >> /root/server_ip_info.txt

# Ghi log
echo "$(date): Đã cập nhật thông tin IP - Nội bộ: $PRIVATE_IP, Công khai: $PUBLIC_IP" >> /var/log/ip_updates.log
EOF

chmod +x /usr/local/bin/update_ip_info.sh
check_command "Không thể tạo script cập nhật địa chỉ IP." "Đã tạo script cập nhật địa chỉ IP."

# Tạo cron job cập nhật IP
echo "*/30 * * * * root /usr/local/bin/update_ip_info.sh > /dev/null 2>&1" > /etc/cron.d/update_ip_info
chmod 644 /etc/cron.d/update_ip_info
check_command "Không thể tạo cron job cập nhật IP." "Đã tạo cron job cập nhật IP định kỳ 30 phút."

# 22. Tạo script kiểm tra toàn diện
print_header "Tạo script kiểm tra hệ thống"
print_message "Đang tạo script kiểm tra hệ thống..."

cat > /usr/local/bin/system_check.sh << 'EOF'
#!/bin/bash
# Script kiểm tra toàn diện hệ thống

echo "===== KIỂM TRA HỆ THỐNG ====="
echo "Thời gian: $(date)"
echo ""

echo "1. Thông tin hệ thống:"
echo "-----------------------"
echo "Hostname: $(hostname)"
echo "Kernel: $(uname -r)"
echo "Uptime: $(uptime -p)"
echo ""

echo "2. Thông tin CPU và RAM:"
echo "------------------------"
echo "CPU Load: $(uptime | awk -F'load average:' '{print $2}')"
echo "Số lượng CPU: $(nproc)"
echo "RAM đã sử dụng: $(free -h | awk '/^Mem/ {print $3"/"$2}')"
echo ""

echo "3. Thông tin ổ đĩa:"
echo "------------------"
df -h | grep -v "tmpfs"
echo ""

echo "4. Trạng thái dịch vụ quan trọng:"
echo "--------------------------------"
echo "SSH: $(systemctl is-active sshd)"
echo "VNC: $(systemctl is-active vncserver@:0.service)"
echo "SSH Recovery: $(systemctl is-active ssh-recovery.service)"
echo "VNC Recovery: $(systemctl is-active vnc-recovery.service)"
echo ""

echo "5. Kiểm tra port đang lắng nghe:"
echo "------------------------------"
ss -tulpn | grep -E ':(22|5900) '
echo ""

echo "6. Kiểm tra tiến trình VNC:"
echo "-------------------------"
ps aux | grep vnc | grep -v grep
echo ""

echo "7. Thông tin địa chỉ IP:"
echo "-----------------------"
echo "IP nội bộ: $(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v "127.0.0.1" | head -n 1)"
echo "IP công khai: $(curl -s -m 5 https://api.ipify.org 2>/dev/null || curl -s -m 5 http://ifconfig.me 2>/dev/null || curl -s -m 5 https://checkip.amazonaws.com 2>/dev/null)"
echo ""

echo "8. Kiểm tra tường lửa:"
echo "---------------------"
echo "Dịch vụ tường lửa: $(systemctl is-active firewalld)"
if systemctl is-active --quiet firewalld; then
    echo "Các dịch vụ được phép: $(firewall-cmd --list-services)"
fi
echo ""

echo "9. Kiểm tra log gần đây:"
echo "----------------------"
echo "SSH log:"
journalctl -u sshd --since "30 minutes ago" | tail -n 10
echo ""
echo "VNC log:"
journalctl -u vncserver@:0.service --since "30 minutes ago" | tail -n 10
echo ""

echo "===== KẾT THÚC KIỂM TRA ====="
EOF

chmod +x /usr/local/bin/system_check.sh
check_command "Không thể tạo script kiểm tra hệ thống." "Đã tạo script kiểm tra hệ thống tại /usr/local/bin/system_check.sh"

# 23. Thực hiện kiểm tra cuối cùng
print_header "Kiểm tra cuối cùng"
print_message "Đang thực hiện kiểm tra cuối cùng..."

# Kiểm tra SSH
SSH_STATUS=$(systemctl is-active sshd)
if [ "$SSH_STATUS" != "active" ]; then
    print_error "Dịch vụ SSH không hoạt động! Đang khởi động lại..."
    systemctl restart sshd
else
    print_message "Dịch vụ SSH đang hoạt động bình thường."
fi

# Kiểm tra VNC
VNC_STATUS=$(systemctl is-active vncserver@:0.service 2>/dev/null)
if [ "$VNC_STATUS" != "active" ]; then
    print_warning "Dịch vụ VNC có thể không hoạt động qua systemd. Kiểm tra tiến trình..."
    if pgrep -f "Xvnc :0" > /dev/null; then
        print_message "Tiến trình VNC đang chạy bình thường."
        VNC_RUNNING=true
    else
        print_error "Không tìm thấy tiến trình VNC! Đang khởi động lại..."
        su - vncuser -c "vncserver :0 -geometry 1024x768 -depth 24" &> /dev/null
        if [ $? -eq 0 ]; then
            print_message "Đã khởi động lại VNC thành công."
            VNC_RUNNING=true
        else
            print_error "Không thể khởi động lại VNC. Vui lòng kiểm tra log."
            VNC_RUNNING=false
        fi
    fi
else
    print_message "Dịch vụ VNC đang hoạt động bình thường qua systemd."
    VNC_RUNNING=true
fi

# 24. Hiển thị thông báo kết thúc
print_header "Cài đặt hoàn tất!"
echo ""
echo "Đã hoàn tất cài đặt GUI và VNC Server trên Rocky Linux 8."
echo ""
echo "=== THÔNG TIN QUAN TRỌNG ==="
echo "- Dịch vụ SSH: $SSH_STATUS"
if [ "$VNC_RUNNING" = true ]; then
    echo "- Dịch vụ VNC: Đang chạy"
else
    echo "- Dịch vụ VNC: Không chạy (cần kiểm tra)"
fi
echo "- Địa chỉ IP nội bộ: $PRIVATE_IP"
echo "- Địa chỉ IP công khai: $PUBLIC_IP"
echo ""
echo "=== THÔNG TIN KẾT NỐI VNC ==="
echo "- Người dùng: vncuser"
echo "- Mật khẩu: 369369"
echo "- Kết nối: $PUBLIC_IP:0 hoặc $PUBLIC_IP:5900"
echo ""
echo "=== TÀI LIỆU HƯỚNG DẪN ==="
echo "- Hướng dẫn sử dụng: /root/vnc_ssh_help.txt"
echo "- Thông tin IP: /root/server_ip_info.txt"
echo ""
echo "=== CÔNG CỤ KHẮC PHỤC SỰ CỐ ==="
echo "- Khôi phục SSH: /usr/local/bin/ssh_recovery.sh"
echo "- Khôi phục VNC: /usr/local/bin/fix_vnc.sh"
echo "- Kiểm tra hệ thống: /usr/local/bin/system_check.sh"
echo ""
echo "LƯU Ý QUAN TRỌNG: Vui lòng thay đổi mật khẩu VNC mặc định sau khi cài đặt để đảm bảo tính bảo mật."
echo "==================================================================="

# Kết thúc với mã trạng thái phù hợp
if [ "$SSH_STATUS" = "active" ] && [ "$VNC_RUNNING" = true ]; then
    exit 0
else
    exit 1
fi
