#!/bin/bash
#===============================================================================
# Cyberrange 1 - Vinh Long
# Setup Script: Database-Server (192.168.30.10)
#
# Cài đặt:
#   1. Auditd + Audit Rules
#   2. PostgreSQL - User zbx_monitor + pg_hba.conf
#   3. Zabbix Agent 2 v7.4 (Ubuntu 24.04) + PostgreSQL Plugin
#
# Chạy: sudo bash setup-db.sh
#===============================================================================

set -euo pipefail

# ======================== CẤU HÌNH ========================
ZABBIX_SERVER="192.168.40.20"
HOSTNAME="Database-Server"
DB_SERVER_IP="192.168.30.10"
PG_MONITOR_USER="zbx_monitor"
PG_MONITOR_PASS="zabbix_monitor_password"
PG_VERSION="16"  # Thay đổi nếu dùng version khác

# pg_hba.conf - cho phép rộng trong lab
PG_HBA_ENTRIES=(
    "host    all     all     0.0.0.0/0       scram-sha-256"
)

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
echo -e "${GREEN}║  Setup Database-Server                       ║${NC}"
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

# ======================== 2. POSTGRESQL - ZABBIX USER ========================
print_header "2. Cấu hình PostgreSQL cho Zabbix Monitoring"

# Kiểm tra PostgreSQL đang chạy
if ! systemctl is-active --quiet postgresql; then
    print_err "PostgreSQL không chạy! Kiểm tra trước khi tiếp tục."
    exit 1
fi
print_ok "PostgreSQL đang chạy"

# Tự detect PG version nếu cần
if [ ! -d "/etc/postgresql/${PG_VERSION}" ]; then
    PG_VERSION=$(ls /etc/postgresql/ 2>/dev/null | sort -rn | head -1)
    if [ -z "$PG_VERSION" ]; then
        print_err "Không tìm thấy thư mục PostgreSQL config!"
        exit 1
    fi
    print_warn "Tự detect PostgreSQL version: ${PG_VERSION}"
fi

PG_HBA_FILE="/etc/postgresql/${PG_VERSION}/main/pg_hba.conf"

# Tạo/cập nhật user zbx_monitor
print_ok "Tạo/cập nhật user ${PG_MONITOR_USER}..."
sudo -u postgres psql -c "
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${PG_MONITOR_USER}') THEN
        CREATE USER ${PG_MONITOR_USER} WITH PASSWORD '${PG_MONITOR_PASS}' INHERIT;
        RAISE NOTICE 'User ${PG_MONITOR_USER} created.';
    ELSE
        ALTER USER ${PG_MONITOR_USER} WITH PASSWORD '${PG_MONITOR_PASS}' INHERIT;
        RAISE NOTICE 'User ${PG_MONITOR_USER} already exists, password updated.';
    END IF;
END
\$\$;
" 2>&1 | grep -i "notice" || true

# Grant quyền
sudo -u postgres psql -c "GRANT pg_monitor TO ${PG_MONITOR_USER};" 2>/dev/null
sudo -u postgres psql -c "GRANT CONNECT ON DATABASE postgres TO ${PG_MONITOR_USER};" 2>/dev/null

# Grant elearning nếu database tồn tại
if sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "elearning"; then
    sudo -u postgres psql -c "GRANT CONNECT ON DATABASE elearning TO ${PG_MONITOR_USER};" 2>/dev/null
    print_ok "Đã grant CONNECT trên database elearning"
else
    print_warn "Database 'elearning' chưa tồn tại, bỏ qua GRANT"
fi
print_ok "User ${PG_MONITOR_USER} đã sẵn sàng"

# Cấu hình pg_hba.conf
print_ok "Cấu hình ${PG_HBA_FILE}..."

# Backup
cp "${PG_HBA_FILE}" "${PG_HBA_FILE}.bak.$(date +%Y%m%d%H%M%S)"
print_ok "Đã backup pg_hba.conf"

# Thêm entries nếu chưa có
for entry in "${PG_HBA_ENTRIES[@]}"; do
    # Lấy keyword chính để check trùng (user + address)
    user_field=$(echo "$entry" | awk '{print $3}')
    addr_field=$(echo "$entry" | awk '{print $4}')

    if grep -q "${user_field}.*${addr_field}" "${PG_HBA_FILE}" 2>/dev/null; then
        print_warn "Entry đã tồn tại: ${user_field} @ ${addr_field}"
    else
        echo "$entry" >> "${PG_HBA_FILE}"
        print_ok "Đã thêm: ${user_field} @ ${addr_field}"
    fi
done

# Reload PostgreSQL
systemctl reload postgresql
print_ok "PostgreSQL đã reload"

# Verify
echo ""
echo "--- pg_hba_file_rules ---"
sudo -u postgres psql -c "SELECT line_number, type, database, user_name, address, auth_method FROM pg_hba_file_rules WHERE error IS NULL ORDER BY line_number;" 2>/dev/null || true

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
    print_ok "Đã cài Zabbix Agent 2 + plugins"
fi

# Cấu hình agent
sed -i "s/^Server=.*/Server=${ZABBIX_SERVER}/" /etc/zabbix/zabbix_agent2.conf
sed -i "s/^ServerActive=.*/ServerActive=${ZABBIX_SERVER}/" /etc/zabbix/zabbix_agent2.conf
sed -i "s/^Hostname=.*/Hostname=${HOSTNAME}/" /etc/zabbix/zabbix_agent2.conf
print_ok "Đã cấu hình: Server=${ZABBIX_SERVER}, Hostname=${HOSTNAME}"

# Cấu hình PostgreSQL plugin
mkdir -p /etc/zabbix/zabbix_agent2.d/plugins.d
cat > /etc/zabbix/zabbix_agent2.d/plugins.d/postgresql.conf << EOF
Plugins.PostgreSQL.Sessions.dbname.Uri=tcp://${DB_SERVER_IP}:5432
Plugins.PostgreSQL.Sessions.dbname.User=${PG_MONITOR_USER}
Plugins.PostgreSQL.Sessions.dbname.Password=${PG_MONITOR_PASS}
Plugins.PostgreSQL.Sessions.dbname.Database=postgres
EOF
print_ok "Đã cấu hình PostgreSQL plugin (tcp://${DB_SERVER_IP}:5432)"

# Khởi động
systemctl enable zabbix-agent2
systemctl restart zabbix-agent2
print_ok "Zabbix Agent 2 đang chạy"

# ======================== 4. FIREWALL (UFW) ========================
print_header "4. Cấu hình Firewall (UFW)"

if command -v ufw &>/dev/null; then
    ufw allow 10050/tcp comment "Zabbix Agent passive" 2>/dev/null || true
    ufw allow 5432/tcp comment "PostgreSQL" 2>/dev/null || true
    print_ok "Đã mở port 10050 (Zabbix) và 5432 (PostgreSQL)"
else
    print_warn "UFW không có sẵn. Bỏ qua."
fi

# ======================== 5. KIỂM TRA ========================
print_header "5. Kiểm tra tổng thể"

echo ""
echo "--- Dịch vụ ---"
for svc in postgresql auditd zabbix-agent2; do
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
echo "--- PostgreSQL ---"
sudo -u postgres psql -c "SELECT 1 AS test;" -t 2>/dev/null && print_ok "PostgreSQL query OK" || print_err "PostgreSQL query FAIL"

echo ""
echo "--- Zabbix PostgreSQL Monitoring ---"
echo "  Testing pgsql.ping..."
PING_RESULT=$(zabbix_agent2 -t "pgsql.ping[\"tcp://${DB_SERVER_IP}:5432\",\"${PG_MONITOR_USER}\",\"${PG_MONITOR_PASS}\",\"postgres\"]" 2>/dev/null || echo "FAILED")
if echo "$PING_RESULT" | grep -q "1"; then
    print_ok "pgsql.ping = OK"
else
    print_warn "pgsql.ping chưa hoạt động (có thể cần restart agent2)"
    echo "  Output: $PING_RESULT"
fi

echo ""
echo "  Testing pgsql.db.discovery..."
DISC_RESULT=$(zabbix_agent2 -t "pgsql.db.discovery[\"tcp://${DB_SERVER_IP}:5432\",\"${PG_MONITOR_USER}\",\"${PG_MONITOR_PASS}\",\"postgres\"]" 2>/dev/null || echo "FAILED")
if echo "$DISC_RESULT" | grep -q "DBNAME"; then
    print_ok "pgsql.db.discovery = OK"
    echo "  $DISC_RESULT" | grep -o '"[^"]*"' | head -10
else
    print_warn "pgsql.db.discovery chưa hoạt động"
fi

echo ""
echo "--- Zabbix Active Check Port 10051 ---"
if nc -z -w3 "${ZABBIX_SERVER}" 10051 2>/dev/null; then
    print_ok "Kết nối tới ${ZABBIX_SERVER}:10051 OK"
else
    print_warn "Không kết nối được tới ${ZABBIX_SERVER}:10051 - Kiểm tra firewall Sophos"
fi

echo ""
echo "--- Zabbix Agent 2 Config ---"
echo "  Hostname: $(grep '^Hostname=' /etc/zabbix/zabbix_agent2.conf)"
echo "  Server:   $(grep '^Server=' /etc/zabbix/zabbix_agent2.conf | head -1)"
echo "  PG URI:   tcp://${DB_SERVER_IP}:5432"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅ Setup Database-Server hoàn tất!          ║${NC}"
echo -e "${GREEN}║                                              ║${NC}"
echo -e "${GREEN}║  Bước tiếp theo (Wazuh GUI):                 ║${NC}"
echo -e "${GREEN}║  1. Gán agent vào group Internal_Servers      ║${NC}"
echo -e "${GREEN}║  2. Cấu hình FIM + Log trong agent.conf      ║${NC}"
echo -e "${GREEN}║                                              ║${NC}"
echo -e "${GREEN}║  Bước tiếp theo (Zabbix Web):                ║${NC}"
echo -e "${GREEN}║  1. Thêm host Database-Server                ║${NC}"
echo -e "${GREEN}║  2. Template: Linux by Zabbix agent           ║${NC}"
echo -e "${GREEN}║  3. Template: PostgreSQL by Zabbix agent 2    ║${NC}"
echo -e "${GREEN}║     active                                    ║${NC}"
echo -e "${GREEN}║  4. Set macros PG.*                           ║${NC}"
echo -e "${GREEN}║  5. Disable Replication discovery (nếu không  ║${NC}"
echo -e "${GREEN}║     dùng replication)                         ║${NC}"
echo -e "${GREEN}║                                              ║${NC}"
echo -e "${GREEN}║  Kiểm tra firewall Sophos:                   ║${NC}"
echo -e "${GREEN}║  - Port 10051 (active check) → Zabbix Server ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
