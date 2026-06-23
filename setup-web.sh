#!/bin/bash
#===============================================================================
# Cyberrange 1 - Vinh Long
# Setup Script: Web-Server (192.168.20.15)
#
# Cài đặt:
#   1. Auditd + Audit Rules
#   2. Nginx Reverse Proxy (React2Shell - Next.js port 3000)
#   3. Zabbix Nginx Monitoring (stub_status local)
#   4. Zabbix Agent 2 v7.4 (Ubuntu 24.04)
#
# Chạy: sudo bash setup-web.sh
#===============================================================================

set -euo pipefail

# ======================== CẤU HÌNH ========================
ZABBIX_SERVER="192.168.40.10"
HOSTNAME="Web-Server"
REACT_APP_PORT="3000"
NGINX_STATUS_PORT="8080"

# ======================== MÀU SẮC ========================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo ""
    echo -e "${BLUE}======================================${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}======================================${NC}"
}

print_ok() {
    echo -e "${GREEN}[OK]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_err() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ======================== KIỂM TRA ROOT ========================
if [[ $EUID -ne 0 ]]; then
    print_err "Script phải chạy với quyền root. Dùng: sudo bash $0"
    exit 1
fi

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Cyberrange 1 - Vinh Long                   ║${NC}"
echo -e "${GREEN}║  Setup Web-Server                            ║${NC}"
echo -e "${GREEN}║  Zabbix Server: ${ZABBIX_SERVER}                  ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"

# ======================== 1. AUDITD ========================
print_header "1. Cài đặt Auditd"

apt-get update -qq
apt-get install -y auditd audispd-plugins
print_ok "Đã cài auditd"

# Tạo audit rules
cat > /etc/audit/rules.d/custom.rules << 'EOF'
# Giám sát thay đổi file passwd, shadow, group
-w /etc/passwd -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/gshadow -p wa -k identity

# Giám sát SSH config
-w /etc/ssh/sshd_config -p wa -k sshd_config

# Giám sát sudo
-w /etc/sudoers -p wa -k sudoers
-w /etc/sudoers.d/ -p wa -k sudoers

# Giám sát login/logout
-w /var/log/auth.log -p wa -k auth_log
-w /var/log/faillog -p wa -k login_failures
-w /var/log/lastlog -p wa -k login_records

# Giám sát cron
-w /etc/crontab -p wa -k cron
-w /etc/cron.d/ -p wa -k cron
-w /var/spool/cron/ -p wa -k cron

# Giám sát thay đổi network config
-w /etc/hosts -p wa -k network_config
-w /etc/network/ -p wa -k network_config
-w /etc/netplan/ -p wa -k network_config

# Giám sát thực thi lệnh root
-a always,exit -F arch=b64 -S execve -F euid=0 -k rootcmd
EOF
print_ok "Đã tạo audit rules"

# Cấu hình auditd.conf
sed -i 's/^log_format = .*/log_format = ENRICHED/' /etc/audit/auditd.conf 2>/dev/null || true
sed -i 's/^max_log_file = .*/max_log_file = 50/' /etc/audit/auditd.conf 2>/dev/null || true
sed -i 's/^max_log_file_action = .*/max_log_file_action = ROTATE/' /etc/audit/auditd.conf 2>/dev/null || true
sed -i 's/^num_logs = .*/num_logs = 10/' /etc/audit/auditd.conf 2>/dev/null || true

augenrules --load
systemctl enable auditd
systemctl restart auditd
print_ok "Auditd đang chạy với $(auditctl -l | wc -l) rules"

# ======================== 2. NGINX REVERSE PROXY ========================
print_header "2. Cài đặt Nginx Reverse Proxy (React2Shell)"

apt-get install -y nginx
print_ok "Đã cài nginx"

# Tạo reverse proxy config cho React2Shell
cat > /etc/nginx/sites-available/react2shell << 'EOF'
server {
    listen 80 default_server;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:3000;

        proxy_http_version 1.1;

        proxy_set_header Host $http_host;
        proxy_set_header X-Forwarded-Host $http_host;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Port $server_port;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF
print_ok "Đã tạo config reverse proxy (server_name _, không hardcode IP)"

# Tạo Zabbix Nginx status endpoint (local only)
cat > /etc/nginx/conf.d/zabbix_nginx_status.conf << 'EOF'
server {
    listen 127.0.0.1:8080;
    server_name 127.0.0.1 localhost;

    location = /basic_status {
        stub_status;
        access_log off;

        allow 127.0.0.1;
        allow ::1;
        deny all;
    }
}
EOF
print_ok "Đã tạo config Zabbix Nginx monitoring (127.0.0.1:${NGINX_STATUS_PORT})"

# Bật site
ln -sf /etc/nginx/sites-available/react2shell /etc/nginx/sites-enabled/react2shell
rm -f /etc/nginx/sites-enabled/default

# Test và reload
if nginx -t 2>/dev/null; then
    systemctl enable nginx
    systemctl reload nginx
    print_ok "Nginx config OK, đã reload"
else
    print_err "Nginx config lỗi! Kiểm tra lại config."
    nginx -t
    exit 1
fi

# ======================== 3. ZABBIX AGENT 2 ========================
print_header "3. Cài đặt Zabbix Agent 2 v7.4"

# Kiểm tra nếu đã cài
if dpkg -l | grep -q zabbix-agent2; then
    print_warn "Zabbix Agent 2 đã được cài. Bỏ qua cài đặt, chỉ cấu hình."
else
    # Tải và cài repo
    cd /tmp
    wget -q https://repo.zabbix.com/zabbix/7.4/release/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_7.4+ubuntu24.04_all.deb
    dpkg -i zabbix-release_latest_7.4+ubuntu24.04_all.deb
    apt-get update -qq

    # Cài agent + plugins
    apt-get install -y zabbix-agent2
    apt-get install -y zabbix-agent2-plugin-mongodb zabbix-agent2-plugin-mssql zabbix-agent2-plugin-postgresql 2>/dev/null || true
    print_ok "Đã cài Zabbix Agent 2"
fi

# Cấu hình
sed -i "s/^Server=.*/Server=${ZABBIX_SERVER}/" /etc/zabbix/zabbix_agent2.conf
sed -i "s/^ServerActive=.*/ServerActive=${ZABBIX_SERVER}/" /etc/zabbix/zabbix_agent2.conf
sed -i "s/^Hostname=.*/Hostname=${HOSTNAME}/" /etc/zabbix/zabbix_agent2.conf
print_ok "Đã cấu hình: Server=${ZABBIX_SERVER}, Hostname=${HOSTNAME}"

# Khởi động
systemctl enable zabbix-agent2
systemctl restart zabbix-agent2
print_ok "Zabbix Agent 2 đang chạy"

# ======================== 4. FIREWALL (UFW) ========================
print_header "4. Cấu hình Firewall (UFW)"

if command -v ufw &>/dev/null; then
    ufw allow 10050/tcp comment "Zabbix Agent passive" 2>/dev/null || true
    ufw allow 80/tcp comment "HTTP Nginx" 2>/dev/null || true
    print_ok "Đã mở port 10050 (Zabbix) và 80 (HTTP)"
else
    print_warn "UFW không có sẵn. Bỏ qua."
fi

# ======================== 5. KIỂM TRA ========================
print_header "5. Kiểm tra tổng thể"

echo ""
echo "--- Dịch vụ ---"
for svc in nginx auditd zabbix-agent2; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        print_ok "$svc đang chạy"
    else
        print_err "$svc KHÔNG chạy!"
    fi
done

echo ""
echo "--- Wazuh Agent ---"
if systemctl is-active --quiet wazuh-agent 2>/dev/null; then
    print_ok "wazuh-agent đang chạy"
else
    print_warn "wazuh-agent chưa cài hoặc không chạy (cài riêng)"
fi

echo ""
echo "--- Audit Rules ---"
echo "  Số rules: $(auditctl -l 2>/dev/null | wc -l)"

echo ""
echo "--- Nginx Test ---"
if curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:${NGINX_STATUS_PORT}/basic_status | grep -q "200"; then
    print_ok "Nginx stub_status OK (127.0.0.1:${NGINX_STATUS_PORT})"
else
    print_warn "Nginx stub_status chưa phản hồi (port ${NGINX_STATUS_PORT})"
fi

echo ""
echo "--- Zabbix Agent 2 ---"
echo "  Hostname: $(grep '^Hostname=' /etc/zabbix/zabbix_agent2.conf)"
echo "  Server:   $(grep '^Server=' /etc/zabbix/zabbix_agent2.conf | head -1)"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅ Setup Web-Server hoàn tất!               ║${NC}"
echo -e "${GREEN}║                                              ║${NC}"
echo -e "${GREEN}║  Bước tiếp theo (Wazuh GUI):                 ║${NC}"
echo -e "${GREEN}║  1. Gán agent vào group DMZ_Servers           ║${NC}"
echo -e "${GREEN}║  2. Cấu hình FIM + Log trong agent.conf      ║${NC}"
echo -e "${GREEN}║                                              ║${NC}"
echo -e "${GREEN}║  Bước tiếp theo (Zabbix Web):                ║${NC}"
echo -e "${GREEN}║  1. Thêm host Web-Server                     ║${NC}"
echo -e "${GREEN}║  2. Gán template: Linux by Zabbix agent       ║${NC}"
echo -e "${GREEN}║  3. Gán template: Nginx by Zabbix agent       ║${NC}"
echo -e "${GREEN}║  4. Set macros NGINX.STUB_STATUS.*            ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
