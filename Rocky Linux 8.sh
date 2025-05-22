#!/bin/bash

# Tên script: rocky_linux_auto_setup.sh
# Mô tả: Script tự động cài đặt và cấu hình Rocky Linux 8 với GUI, 7zip và VNC Server.

# Kiểm tra quyền root
if [[ $EUID -ne 0 ]]; then
   echo "Lỗi: Script này yêu cầu quyền root để chạy. Vui lòng sử dụng lệnh 'sudo ./rocky_linux_auto_setup.sh'."
   exit 1
fi

echo "Bắt đầu quá trình cài đặt và cấu hình Rocky Linux 8..."

# --- Cấu hình biến môi trường ---
# Đặt mật khẩu VNC mặc định. LƯU Ý: Không an toàn khi sử dụng trong môi trường sản xuất.
VNC_PASSWORD="369369"
# Đặt tên người dùng mà bạn muốn cài đặt VNC Server. RẤT QUAN TRỌNG: Thay thế 'your_existing_username' bằng tên người dùng thực tế.
VNC_USER="your_existing_username" 

# --- 1. Cập nhật phần mềm hệ thống ---
echo -e "\n--- BƯỚC 1: Cập nhật phần mềm hệ thống ---"
if dnf update -y; then
    echo "Thành công: Hệ thống đã được cập nhật."
else
    echo "Lỗi: Không thể cập nhật phần mềm hệ thống. Vui lòng kiểm tra kết nối mạng hoặc các repository."
    exit 1
fi

# --- 2. Cài đặt 7zip và các plugin ---
echo -e "\n--- BƯỚC 2: Cài đặt 7zip và các plugin ---"
if dnf install -y p7zip p7zip-plugins; then
    echo "Thành công: 7zip và các plugin đã được cài đặt."
else
    echo "Lỗi: Không thể cài đặt 7zip và các plugin."
    exit 1
fi

# --- 3. Cài đặt giao diện người dùng (GUI - GNOME Desktop) ---
echo -e "\n--- BƯỚC 3: Cài đặt giao diện người dùng (GNOME Desktop) ---"
# Cài đặt EPEL repository (thường cần cho các gói và phụ thuộc bổ sung)
if dnf install -y epel-release expect; then
    echo "Thành công: EPEL repository và gói 'expect' đã được cài đặt."
else
    echo "Lỗi: Không thể cài đặt EPEL repository hoặc gói 'expect'."
    exit 1
fi

if dnf groupinstall -y "Server with GUI"; then
    echo "Thành công: Giao diện người dùng (GNOME Desktop) đã được cài đặt."
    echo "Thiết lập GNOME làm môi trường mặc định sau khi khởi động."
    systemctl set-default graphical.target
else
    echo "Lỗi: Không thể cài đặt giao diện người dùng. Vui lòng kiểm tra lại."
    exit 1
fi

# --- 4. Cài đặt và cấu hình VNC Server để điều khiển từ xa ---
echo -e "\n--- BƯỚC 4: Cài đặt và cấu hình VNC Server ---"
if dnf install -y tigervnc-server; then
    echo "Thành công: TigerVNC Server đã được cài đặt."
else
    echo "Lỗi: Không thể cài đặt TigerVNC Server."
    exit 1
fi

# Kiểm tra sự tồn tại của người dùng VNC_USER
echo "Kiểm tra người dùng VNC: '$VNC_USER'..."
if ! id -u "$VNC_USER" >/dev/null 2>&1; then
    echo "Lỗi: Người dùng '$VNC_USER' không tồn tại trên hệ thống."
    echo "Vui lòng THAY THẾ biến 'VNC_USER' trong script bằng tên người dùng hiện có hoặc tạo người dùng mới trước khi chạy lại script."
    exit 1
fi

# Tạo thư mục .vnc nếu chưa có và gán quyền sở hữu
echo "Tạo thư mục .vnc cho người dùng '$VNC_USER'..."
mkdir -p /home/$VNC_USER/.vnc
chown $VNC_USER:$VNC_USER /home/$VNC_USER/.vnc

# Sử dụng 'expect' để tự động đặt mật khẩu VNC
echo "Tự động thiết lập mật khẩu VNC cho người dùng '$VNC_USER' (Mật khẩu: '$VNC_PASSWORD')..."
expect -c "
    spawn su - $VNC_USER -c \"vncpasswd\"
    expect \"Password:\"
    send \"$VNC_PASSWORD\r\"
    expect \"Verify:\"
    send \"$VNC_PASSWORD\r\"
    expect eof
"
if [ $? -eq 0 ]; then
    echo "Thành công: Mật khẩu VNC đã được thiết lập."
else
    echo "Lỗi: Không thể thiết lập mật khẩu VNC tự động."
    echo "Vui lòng thiết lập thủ công bằng lệnh 'su - $VNC_USER -c \"vncpasswd\"' sau khi script hoàn tất."
fi

# Tạo và cấu hình dịch vụ Systemd cho VNC Server (màn hình :1, cổng 5901)
echo "Cấu hình dịch vụ Systemd cho VNC Server (màn hình :1, cổng 5901) cho người dùng '$VNC_USER'..."
cp /lib/systemd/system/vncserver@.service /etc/systemd/system/vncserver@:1.service
sed -i "s/User=%I/User=$VNC_USER/" /etc/systemd/system/vncserver@:1.service
sed -i "s/PIDFile=\/run\/vncserver-%I.pid/PIDFile=\/run\/vncserver-$VNC_USER@%i.pid/" /etc/systemd/system/vncserver@:1.service

systemctl daemon-reload
if systemctl enable vncserver@:1.service && systemctl start vncserver@:1.service; then
    echo "Thành công: Dịch vụ VNC Server cho '$VNC_USER' đã được kích hoạt và khởi động."
else
    echo "Lỗi: Không thể kích hoạt hoặc khởi động dịch vụ VNC Server."
fi

# Cấu hình Firewall để cho phép cổng 5900 (mặc định) và 5901 (cho người dùng)
echo "Cấu hình Firewall để cho phép kết nối VNC (cổng 5900/tcp và 5901/tcp)..."
firewall-cmd --permanent --add-port=5900/tcp
firewall-cmd --permanent --add-port=5901/tcp
if firewall-cmd --reload; then
    echo "Thành công: Các cổng VNC đã được mở trên Firewall."
else
    echo "Lỗi: Không thể cấu hình Firewall. Vui lòng kiểm tra trạng thái của firewalld."
fi

echo -e "\n--- QUÁ TRÌNH CÀI ĐẶT VÀ CẤU HÌNH HOÀN TẤT ---"
echo "Tất cả các yêu cầu tự động đã được thực hiện."
echo "VNC Server đã được cấu hình cho người dùng '$VNC_USER' với mật khẩu mặc định '$VNC_PASSWORD' trên cổng 5901."
echo "Để áp dụng đầy đủ các thay đổi, đặc biệt là giao diện người dùng, bạn cần **khởi động lại hệ thống**."
echo "Sử dụng lệnh: \`sudo reboot\`"

echo -e "\n--- LƯU Ý QUAN TRỌNG VỀ BẢO MẬT ---"
echo "Mật khẩu VNC đã được tự động đặt trong script. Đây là một rủi ro bảo mật đáng kể."
echo "Sau khi khởi động lại và đăng nhập vào môi trường VNC, bạn **NÊN thay đổi mật khẩu VNC** ngay lập tức bằng lệnh:"
echo "  \`su - $VNC_USER -c \"vncpasswd\"\`"
echo "Ngoài ra, hãy cân nhắc sử dụng SSH tunneling để mã hóa và tăng cường bảo mật cho kết nối VNC của bạn."
