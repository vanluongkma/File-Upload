#!/bin/bash
#===============================================================================
# Cyberrange 1 - Vinh Long
# Script: Xóa toàn bộ log - Reset máy về trạng thái trắng
#
# Chạy trên CẢ 2 máy trước khi học viên bắt đầu diễn tập:
#   sudo bash clear-logs.sh
#
# Script tự detect Web-Server hoặc Database-Server và xóa log phù hợp.
#===============================================================================

set -euo pipefail

# ======================== MÀU SẮC ========================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

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

# Xóa file log an toàn (truncate, không xóa file)
clear_log() {
    if [ -f "$1" ]; then
        truncate -s 0 "$1"
        print_ok "Cleared: $1"
    fi
}

# Xóa tất cả file trong thư mục (*.log, *.gz, *.1, etc.)
clear_log_dir() {
    if [ -d "$1" ]; then
        find "$1" -type f \( -name "*.log" -o -name "*.log.*" -o -name "*.gz" -o -name "*.old" -o -name "*.1" -o -name "*.2" -o -name "*.3" -o -name "*.4" \) -exec truncate -s 0 {} \; 2>/dev/null
        print_ok "Cleared directory: $1"
    fi
}

# ======================== KIỂM TRA ROOT ========================
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[ERROR]${NC} Script phải chạy với quyền root. Dùng: sudo bash $0"
    exit 1
fi

echo ""
echo -e "${RED}╔══════════════════════════════════════════════╗${NC}"
echo -e "${RED}║  ⚠️  CLEAR ALL LOGS - RESET MÁY TRẮNG       ║${NC}"
echo -e "${RED}║  Cyberrange 1 - Vinh Long                   ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Script sẽ xóa TOÀN BỘ log trên máy này.${NC}"
echo -e "${YELLOW}Các dịch vụ sẽ được restart sau khi xóa.${NC}"
echo ""
read -p "Bạn chắc chắn muốn tiếp tục? (y/N): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Đã hủy."
    exit 0
fi

# ======================== 1. SYSTEM LOGS ========================
print_header "1. Xóa System Logs"

# Syslog & messages
clear_log /var/log/syslog
clear_log /var/log/messages
clear_log /var/log/kern.log
clear_log /var/log/daemon.log
clear_log /var/log/debug
clear_log /var/log/dmesg
clear_log /var/log/dpkg.log
clear_log /var/log/alternatives.log
clear_log /var/log/bootstrap.log
clear_log /var/log/cloud-init.log
clear_log /var/log/cloud-init-output.log
clear_log /var/log/ubuntu-advantage.log
clear_log /var/log/unattended-upgrades/unattended-upgrades.log
clear_log /var/log/unattended-upgrades/unattended-upgrades-dpkg.log
clear_log /var/log/apt/history.log
clear_log /var/log/apt/term.log

# Xóa rotated logs
find /var/log -type f -name "*.gz" -delete 2>/dev/null || true
find /var/log -type f -name "*.old" -delete 2>/dev/null || true
find /var/log -type f -regex ".*\.[0-9]+$" -delete 2>/dev/null || true
print_ok "Đã xóa rotated logs (*.gz, *.old, *.1, *.2...)"

# ======================== 2. AUTH & LOGIN LOGS ========================
print_header "2. Xóa Auth & Login Logs"

clear_log /var/log/auth.log
clear_log /var/log/faillog

# Xóa login records
truncate -s 0 /var/log/wtmp 2>/dev/null && print_ok "Cleared: /var/log/wtmp (login history)" || true
truncate -s 0 /var/log/btmp 2>/dev/null && print_ok "Cleared: /var/log/btmp (failed logins)" || true
truncate -s 0 /var/log/lastlog 2>/dev/null && print_ok "Cleared: /var/log/lastlog" || true

# ======================== 3. AUDIT LOGS ========================
print_header "3. Xóa Audit Logs"

if systemctl is-active --quiet auditd 2>/dev/null; then
    # Dùng lệnh chính thức để rotate và xóa
    service auditd rotate 2>/dev/null || true
    clear_log /var/log/audit/audit.log
    find /var/log/audit -type f -name "audit.log.*" -delete 2>/dev/null || true
    systemctl restart auditd
    print_ok "Audit logs cleared & auditd restarted"
else
    print_warn "auditd không chạy, bỏ qua"
fi

# ======================== 4. NGINX LOGS (Web-Server) ========================
print_header "4. Xóa Nginx Logs"

if systemctl is-active --quiet nginx 2>/dev/null; then
    clear_log_dir /var/log/nginx
    # Reopen log files
    nginx -s reopen 2>/dev/null || systemctl reload nginx
    print_ok "Nginx logs cleared & reopened"
else
    print_warn "nginx không chạy, bỏ qua"
fi

# ======================== 5. POSTGRESQL LOGS (Database-Server) ========================
print_header "5. Xóa PostgreSQL Logs"

if systemctl is-active --quiet postgresql 2>/dev/null; then
    clear_log_dir /var/log/postgresql
    systemctl reload postgresql
    print_ok "PostgreSQL logs cleared"
else
    print_warn "postgresql không chạy, bỏ qua"
fi

# ======================== 6. WAZUH AGENT LOGS ========================
print_header "6. Xóa Wazuh Agent Logs"

if [ -d "/var/ossec" ]; then
    # Agent logs
    clear_log /var/ossec/logs/ossec.log
    clear_log /var/ossec/logs/active-responses.log

    # Xóa alerts & archives trên agent
    find /var/ossec/logs -type f -name "*.log" -exec truncate -s 0 {} \; 2>/dev/null || true
    find /var/ossec/logs -type f -name "*.json" -exec truncate -s 0 {} \; 2>/dev/null || true
    find /var/ossec/logs -type f -name "*.gz" -delete 2>/dev/null || true

    # Xóa FIM database (syscheck) để bắt đầu quét mới
    rm -f /var/ossec/queue/fim/db/*.db 2>/dev/null || true
    rm -f /var/ossec/queue/fim/db/*.db-journal 2>/dev/null || true
    print_ok "Đã xóa FIM database (sẽ quét lại baseline)"

    # Restart wazuh-agent
    if systemctl is-active --quiet wazuh-agent 2>/dev/null; then
        systemctl restart wazuh-agent
        print_ok "Wazuh agent logs cleared & restarted"
    fi
else
    print_warn "Wazuh agent chưa cài, bỏ qua"
fi

# ======================== 7. ZABBIX AGENT LOGS ========================
print_header "7. Xóa Zabbix Agent Logs"

if systemctl is-active --quiet zabbix-agent2 2>/dev/null; then
    clear_log /var/log/zabbix/zabbix_agent2.log
    clear_log_dir /var/log/zabbix
    systemctl restart zabbix-agent2
    print_ok "Zabbix agent logs cleared & restarted"
else
    print_warn "zabbix-agent2 không chạy, bỏ qua"
fi

# ======================== 8. JOURNAL LOGS ========================
print_header "8. Xóa Journal Logs (systemd)"

journalctl --rotate 2>/dev/null || true
journalctl --vacuum-time=1s 2>/dev/null || true
print_ok "Systemd journal cleared"

# ======================== 9. SHELL HISTORY ========================
print_header "9. Xóa Shell History"

# Xóa history cho tất cả users
for user_home in /root /home/*; do
    if [ -d "$user_home" ]; then
        username=$(basename "$user_home")
        # Bash history
        truncate -s 0 "${user_home}/.bash_history" 2>/dev/null || true
        # Zsh history
        truncate -s 0 "${user_home}/.zsh_history" 2>/dev/null || true
        # Python history
        rm -f "${user_home}/.python_history" 2>/dev/null || true
        # Less history
        rm -f "${user_home}/.lesshst" 2>/dev/null || true
        # Vim info
        rm -f "${user_home}/.viminfo" 2>/dev/null || true
        # Nano search history
        rm -f "${user_home}/.nano/search_history" 2>/dev/null || true
    fi
done
# Clear current session history
history -c 2>/dev/null || true
print_ok "Shell history cleared cho tất cả users"

# ======================== 10. TMP FILES ========================
print_header "10. Dọn dẹp tmp"

rm -rf /tmp/* 2>/dev/null || true
rm -rf /var/tmp/* 2>/dev/null || true
print_ok "Đã dọn /tmp và /var/tmp"

# ======================== KIỂM TRA CUỐI ========================
print_header "Kiểm tra sau khi xóa"

echo ""
echo "--- Kích thước log còn lại ---"
du -sh /var/log/ 2>/dev/null || true
echo ""

echo "--- Dịch vụ đang chạy ---"
for svc in auditd wazuh-agent zabbix-agent2 nginx postgresql; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        print_ok "$svc đang chạy"
    fi
done

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅ ĐÃ XÓA TOÀN BỘ LOG!                    ║${NC}"
echo -e "${GREEN}║  Máy đã sẵn sàng cho diễn tập.              ║${NC}"
echo -e "${GREEN}║                                              ║${NC}"
echo -e "${GREEN}║  Lưu ý:                                     ║${NC}"
echo -e "${GREEN}║  - FIM sẽ quét lại baseline mới              ║${NC}"
echo -e "${GREEN}║  - Wazuh cần vài phút để sync lại            ║${NC}"
echo -e "${GREEN}║  - Audit rules vẫn giữ nguyên                ║${NC}"
echo -e "${GREEN}║  - Tất cả cấu hình KHÔNG bị thay đổi         ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
