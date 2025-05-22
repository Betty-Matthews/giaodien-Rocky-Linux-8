#!/bin/bash

# Tên script: rocky_linux_auto_setup.sh
# Mô tả: Script tự động cài đặt và cấu hình Rocky Linux 8 với GUI (GNOME), 7zip và VNC Server.
# Phiên bản: 5.0 (Tự động tạo người dùng VNC nếu chưa tồn tại)

# --- Khởi tạo và Kiểm tra Quyền ---
if [[ $EUID -ne 0 ]]; then
   echo "Lỗi: Script này yêu cầu quyền root để chạy. Vui lòng sử dụng lệnh 'sudo ./rocky_linux_auto_setup.sh'."
   exit 1
fi

echo "Bắt đầu quá trình cài đặt và cấu hình Rocky Linux 8..."

# --- Cấu hình Biến Môi Trường ---
# Đặt mật khẩu VNC mặc định.
# CẢNH BÁO: Mật khẩu được mã hóa cứng trong script là không an toàn cho môi trường sản xuất.
# Để tăng tính linh hoạt, script sẽ hỏi người dùng nhập mật khẩu VNC.
# Nếu người dùng không nhập gì, mật khẩu mặc định "369369" sẽ được sử dụng.
read -p "Nhập mật khẩu VNC (mặc định: 369369): " VNC_PASSWORD
VNC_PASSWORD=${VNC_PASSWORD:-"369369"} # Nếu người dùng không nhập, dùng mặc định

# Đặt tên người dùng mà bạn muốn cài đặt VNC Server.
# Script sẽ tự động tạo người dùng này nếu họ chưa tồn tại.
VNC_USER="dockaka" # Bạn có thể thay đổi tên này nếu muốn


# --- BƯỚC 0: Cài đặt EPEL Repository và Gói 'expect' ---
echo -e "\n--- BƯỚC 0: Cài đặt EPEL repository và gói 'expect' ---"
echo "Đảm bảo các repository cần thiết được kích hoạt và DNF cache được làm mới."

# Cài đặt EPEL release và expect. Thử lại tối đa 3 lần.
for i in {1..3}; do
    if dnf install -y epel-release expect > /dev/null 2>&1; then # Chuyển hướng output để gọn hơn
        echo "Thành công: EPEL repository và gói 'expect' đã được cài đặt."
        break
    else
        echo "Cảnh báo: Không thể cài đặt EPEL repository hoặc gói 'expect'. Thử lại sau 5 giây... ($i/3)"
        sleep 5
    fi
    if [ $i -eq 3 ]; then
        echo "Lỗi nghiêm trọng: Không thể cài đặt EPEL repository hoặc gói 'expect' sau nhiều lần thử. Vui lòng kiểm tra kết nối mạng và repository."
        exit 1
    fi
done

# Làm sạch và làm mới cache DNF sau khi thêm EPEL. Thử lại nhiều lần để đảm bảo metadata cập nhật.
echo "Làm sạch và làm mới DNF cache để nhận diện các gói từ EPEL..."
for i in {1..3}; do
    dnf clean all > /dev/null 2>&1 # Làm sạch cache, ẩn output
    dnf makecache --timer > /dev/null 2>&1 # Tạo lại cache, ẩn output
    if [ $? -eq 0 ]; then
        echo "Thành công: DNF cache đã được làm mới hoàn toàn. ($i/3)"
        break
    else
        echo "Cảnh báo: Lỗi làm mới DNF cache. Thử lại sau 5 giây... ($i/3)"
        sleep 5
    fi
    if [ $i -eq 3 ]; then
        echo "Lỗi nghiêm trọng: Không thể làm mới DNF cache sau nhiều lần thử. Các cài đặt gói có thể thất bại."
        # Không thoát ở đây để các bước sau có thể tự kiểm tra, nhưng thông báo rõ ràng.
    fi
done


# --- BƯỚC 1: Cập nhật Phần Mềm Hệ Thống ---
echo -e "\n--- BƯỚC 1: Cập nhật phần mềm hệ thống ---"
if dnf update -y; then
    echo "Thành công: Hệ thống đã được cập nhật."
else
    echo "Lỗi: Không thể cập nhật phần mềm hệ thống. Vui lòng kiểm tra kết nối mạng hoặc các repository."
    exit 1
fi

# --- BƯỚC 2: Cài đặt 7zip và các Plugin ---
echo -e "\n--- BƯỚC 2: Cài đặt 7zip và các plugin ---"
# Các gói này thường có trong EPEL, việc cài EPEL trước đó là rất quan trọng.
echo "Đang thử cài đặt p7zip và p7zip-plugins..."
if dnf install -y p7zip p7zip-plugins; then
    echo "Thành công: 7zip và các plugin đã được cài đặt."
else
    echo "Lỗi: Không thể cài đặt 7zip và các plugin."
    echo "Các nguyên nhân có thể: Gói không có sẵn trong các repository đã kích hoạt (bao gồm EPEL), hoặc lỗi kết nối mirror."
    echo "Vui lòng kiểm tra thủ công bằng lệnh: 'sudo dnf repolist epel' và 'sudo dnf search p7zip'."
    exit 1
fi

# --- BƯỚC 3: Cài đặt Giao Diện Người Dùng (GUI - GNOME Desktop) ---
echo -e "\n--- BƯỚC 3: Cài đặt giao diện người dùng (GNOME Desktop) ---"
if dnf groupinstall -y "Server with GUI"; then
    echo "Thành công: Giao diện người dùng (GNOME Desktop) đã được cài đặt."
    echo "Thiết lập GNOME làm môi trường mặc định sau khi khởi động."
    systemctl set-default graphical.target
else
    echo "Lỗi: Không thể cài đặt giao diện người dùng. Vui lòng kiểm tra lại."
    exit 1
fi

# --- BƯỚC 4: Cài đặt và Cấu Hình VNC Server để điều khiển từ xa ---
echo -e "\n--- BƯỚC 4: Cài đặt và cấu hình VNC Server ---"
if dnf install -y tigervnc-server; then
    echo "Thành công: TigerVNC Server đã được cài đặt."
else
    echo "Lỗi: Không thể cài đặt TigerVNC Server."
    exit 1
fi

# --- Kiểm tra và Tạo Người Dùng VNC ---
echo "Kiểm tra người dùng VNC: '$VNC_USER'..."
if ! id -u "$VNC_USER" >/dev/null 2>&1; then
    echo "Cảnh báo: Người dùng '$VNC_USER' không tồn tại. Đang tự động tạo người dùng này..."
    if adduser "$VNC_USER"; then
        echo "Thành công: Người dùng '$VNC_USER' đã được tạo."
        # Đặt mật khẩu cho người dùng mới một cách an toàn
        echo "$VNC_USER:$VNC_PASSWORD" | chpasswd
        echo "Thành công: Đặt mật khẩu cho người dùng '$VNC_USER'."
    else
        echo "Lỗi: Không thể tạo người dùng '$VNC_USER'. Vui lòng tạo thủ công và thử lại script."
        exit 1
    fi
else
    echo "Người dùng '$VNC_USER' đã tồn tại."
fi

# Tạo thư mục .vnc nếu chưa có và gán quyền sở hữu
echo "Tạo thư mục .vnc cho người dùng '$VNC_USER'..."
mkdir -p /home/$VNC_USER/.vnc
chown $VNC_USER:$VNC_USER /home/$VNC_USER/.vnc

# Sử dụng 'expect' để tự động đặt mật khẩu VNC (dù đã đặt ở trên, VNC cũng cần file riêng)
echo "Tự động thiết lập mật khẩu VNC (thêm vào file cấu hình VNC) cho người dùng '$VNC_USER'..."
expect -c "
    set timeout 10
    spawn su - $VNC_USER -c \"vncpasswd\"
    expect {
        \"Password:\" { send \"$VNC_PASSWORD\\r\"; exp_continue }
        \"Verify:\" { send \"$VNC_PASSWORD\\r\"; exp_continue }
        \"Would you like to enter a view-only password (y/n)?\" { send \"n\\r\"; exp_continue }
        timeout { puts \"Timeout while setting VNC password for VNC config file. User might be locked or vncpasswd issue.\"; exit 1 }
        eof { }
    }
"
if [ $? -eq 0 ]; then
    echo "Thành công: Mật khẩu VNC đã được thiết lập trong file cấu hình VNC."
else
    echo "Lỗi: Không thể thiết lập mật khẩu VNC tự động trong file cấu hình VNC."
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
    echo "Bạn có thể kiểm tra trạng thái dịch vụ bằng: 'sudo systemctl status vncserver@:1.service'"
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

# --- Hoàn Tất Quá Trình ---
echo -e "\n--- QUÁ TRÌNH CÀI ĐẶT VÀ CẤU HÌNH HOÀN TẤT ---"
echo "Tất cả các yêu cầu tự động đã được thực hiện."
echo "Người dùng VNC **'$VNC_USER'** (nếu chưa tồn tại) đã được tạo với mật khẩu **'$VNC_PASSWORD'**."
echo "VNC Server đã được cấu hình cho người dùng '$VNC_USER' trên cổng **5901**."
echo "Để áp dụng đầy đủ các thay đổi, đặc biệt là giao diện người dùng, bạn cần **khởi động lại hệ thống**."
echo "Sử dụng lệnh: \`sudo reboot\`"

echo -e "\n--- LƯU Ý QUAN TRỌNG VỀ BẢO MẬT ---"
echo "Mật khẩu VNC đã được tự động đặt trong script. Đây là một rủi ro bảo mật đáng kể."
echo "Sau khi khởi động lại và đăng nhập vào môi trường VNC, bạn **NÊN thay đổi mật khẩu VNC** ngay lập tức bằng lệnh:"
echo "  \`su - $VNC_USER -c \"vncpasswd\"\`"
echo "Ngoài ra, hãy cân nhắc sử dụng SSH tunneling để mã hóa và tăng cường bảo mật cho kết nối VNC của bạn."
