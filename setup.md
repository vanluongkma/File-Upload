# 🛡️ Cyberrange 1 - Vinh Long - Hướng Dẫn Cài Đặt

---

## 📐 Sơ đồ mạng - Sophos Firewall Interfaces

| Card | Tên Zone         | Loại         | Địa chỉ IP / Subnet     |
|------|------------------|--------------|--------------------------|
| 1    | MNGT             | LAN Segment  | 10.10.10.254             |
| 2    | WAN              | DHCP         | (DHCP từ ISP)            |
| 3    | LAN              | LAN Segment  | 192.168.10.0/24          |
| 4    | DMZ              | LAN Segment  | 192.168.20.0/24          |
| 5    | Internal-Server  | LAN Segment  | 192.168.30.0/24          |
| 6    | SOC_SOAR         | LAN Segment  | 192.168.40.0/24          |

### Danh sách máy chủ

| Zone             | Máy chủ          | IP             |
|------------------|-------------------|----------------|
| SOC_SOAR         | Zabbix Server     | 192.168.40.10  |
| SOC_SOAR         | Wazuh Server      | 192.168.40.15  |
| DMZ              | Web-Server        | 192.168.20.15  |
| Internal-Server  | Database-Server   | 192.168.30.15  |
| WAN              | Kali (Attacker)   | DHCP           |

### Kịch bản tấn công

> Kali (Vùng WAN) → Tấn công vào Web-Server (DMZ)

---

## 📋 Danh sách cài đặt

- [x] Auditd (Audit Log) trên Web & DB
- [x] Nginx Reverse Proxy cho React2Shell (Web-Server)
- [ ] FIM (File Integrity Monitoring) qua Wazuh
- [ ] Zabbix Agent 2 trên Web & DB
- [ ] Wazuh Agent → Group assignment (DMZ_Servers / Internal_Servers)

### 🚀 Script tự động

Thay vì thực hiện thủ công, chạy script:

```bash
# Trên Web-Server (192.168.20.15):
sudo bash setup-web.sh

# Trên Database-Server (192.168.30.15):
sudo bash setup-db.sh
```

> Sau khi chạy script, vẫn cần cấu hình thủ công trên **Wazuh GUI** (FIM + Log group) và **Zabbix Web** (thêm host + template + macros). Xem chi tiết ở các mục bên dưới.

---

## 1️⃣ Cài đặt Auditd (Audit Log) - Trên Web-Server & Database-Server

> **Thực hiện trên cả 2 máy**: Web-Server (192.168.20.15) và Database-Server (192.168.30.15)

### 1.1 Cài đặt auditd

```bash
sudo apt update
sudo apt install auditd audispd-plugins -y
```

### 1.2 Khởi động và kích hoạt dịch vụ

```bash
sudo systemctl enable auditd
sudo systemctl start auditd
sudo systemctl status auditd
```

### 1.3 Cấu hình Audit Rules

Tạo file rules tùy chỉnh:

```bash
sudo nano /etc/audit/rules.d/custom.rules
```

Thêm các rules giám sát quan trọng:

```bash
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

# Giám sát thực thi lệnh đáng ngờ
-a always,exit -F arch=b64 -S execve -F euid=0 -k rootcmd
```

### 1.4 Áp dụng rules

```bash
sudo augenrules --load
sudo auditctl -l    # Kiểm tra rules đã load
```

### 1.5 Cấu hình auditd gửi log tới Wazuh

Chỉnh file cấu hình audit:

```bash
sudo nano /etc/audit/auditd.conf
```

Đảm bảo các dòng sau:

```ini
log_file = /var/log/audit/audit.log
log_format = ENRICHED
max_log_file = 50
max_log_file_action = ROTATE
num_logs = 10
```

Restart auditd:

```bash
sudo systemctl restart auditd
```

---

## 1.5 Cấu hình Nginx Reverse Proxy - React2Shell (Trên Web-Server)

> **Thực hiện trên Web-Server (192.168.20.15)**
> App React2Shell (Next.js) chạy trên port 3000, Nginx proxy qua port 80
> **Không hardcode IP** — dùng `server_name _` để nhận request theo Host header thực tế

### Cài đặt Nginx

```bash
sudo apt update
sudo apt install nginx -y
sudo systemctl enable nginx
```

### 1.5.1 Tạo reverse proxy config cho React2Shell

```bash
sudo nano /etc/nginx/sites-available/react2shell
```

Dán nội dung:

```nginx
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
```

> **Tại sao dùng `server_name _` và `$http_host`?**
> - `server_name _` → Nginx nhận request bằng IP hoặc domain bất kỳ (không phụ thuộc 1 IP cố định)
> - `$http_host` → giữ nguyên Host header từ browser (bao gồm port nếu có)
> - Fix lỗi **Next.js Server Actions**: Origin và X-Forwarded-Host phải khớp
>
> Flow: `Client → Nginx :80 → Next.js 127.0.0.1:3000`

### 1.5.2 Cấu hình Zabbix Nginx Monitoring (stub_status)

Tạo file riêng cho Zabbix monitor Nginx (chạy local, không expose ra ngoài):

```bash
sudo nano /etc/nginx/conf.d/zabbix_nginx_status.conf
```

```nginx
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
```

### 1.5.3 Bật site và reload

```bash
# Bật site (dùng -sf để overwrite nếu đã có)
sudo ln -sf /etc/nginx/sites-available/react2shell /etc/nginx/sites-enabled/react2shell

# Tắt default site để tránh đụng
sudo rm -f /etc/nginx/sites-enabled/default

# Test cấu hình
sudo nginx -t

# Reload Nginx
sudo systemctl reload nginx
```

### 1.5.4 Test truy cập

```bash
# Test app React2Shell
curl -I http://127.0.0.1
curl -I http://192.168.20.15

# Test Zabbix Nginx status (local only)
curl http://127.0.0.1:8080/basic_status
```

> Truy cập ứng dụng qua địa chỉ IP hoặc domain được NAT/proxy tới webserver:
> - `http://<IP-webserver>`
> - `http://<IP-firewall>` (nếu có DNAT)
> - `http://<domain-lab>`
>
> **Không** truy cập trực tiếp port 3000 — port này chỉ để Next.js chạy nội bộ.

---

## 2️⃣ Cấu hình FIM + Thu thập Log - Qua Wazuh GUI (Group Configuration)

> **Phương pháp**: Cấu hình tập trung qua Wazuh Dashboard → Groups → Edit group configuration
> Không cần SSH vào từng agent để sửa `ossec.conf`
> FIM (`<syscheck>`) và Log collection (`<localfile>`) được đẩy tự động qua group agent.conf

### 2.1 Truy cập Wazuh Dashboard

1. Mở trình duyệt: `https://192.168.40.15`
2. Đăng nhập bằng tài khoản admin

### 2.2 Tạo Groups & Gán Agent

1. Vào **Server management** → **Endpoints Summary**
2. Chọn agent **Web-Server** → **Actions** → **Edit groups** → Thêm group `DMZ_Servers`
3. Chọn agent **Database-Server** → **Actions** → **Edit groups** → Thêm group `Internal_Servers`

> Nếu group chưa tồn tại, tạo mới tại **Server management** → **Groups** → **Add new group**

### 2.3 Cấu hình Group DMZ_Servers (Web-Server)

1. Vào **Server management** → **Groups** → chọn **DMZ_Servers**
2. Click **Files** → chọn **agent.conf** → **Edit**
3. Dán nội dung sau:

```xml
<agent_config>
  <syscheck>
    <disabled>no</disabled>
    <frequency>180</frequency>
    <directories realtime="yes" check_all="yes" report_changes="yes">/</directories>
    <ignore>/proc</ignore>
    <ignore>/sys</ignore>
    <ignore>/dev</ignore>
    <ignore>/run</ignore>
    <ignore>/snap</ignore>
    <ignore>/var/log</ignore>
    <ignore>/tmp</ignore>
    <ignore>/var/tmp</ignore>
    <ignore>/var/cache</ignore>
    <ignore>/var/lib/dpkg</ignore>
    <ignore>/var/lib/apt</ignore>
    <ignore>/var/ossec/queue</ignore>
    <ignore>/var/ossec/var</ignore>
    <ignore>/var/ossec/logs</ignore>
    <ignore>/var/ossec/tmp</ignore>
    <ignore>/var/ossec/etc/shared</ignore>
    <ignore>/var/run/zabbix</ignore>
    <ignore type="sregex">\.next/cache</ignore>
    <ignore type="sregex">node_modules</ignore>
    <ignore type="sregex">\.git/objects</ignore>
    <ignore type="sregex">\.git/logs</ignore>
    <ignore>/etc/mtab</ignore>
    <ignore>/etc/hosts.deny</ignore>
    <ignore>/etc/mail/statistics</ignore>
    <ignore>/etc/random-seed</ignore>
    <ignore>/etc/adjtime</ignore>
    <ignore>/etc/prelink.cache</ignore>
    <ignore>/etc/resolv.conf</ignore>
    <ignore>/etc/ld.so.cache</ignore>
    
    <skip_nfs>yes</skip_nfs>
    <skip_dev>yes</skip_dev>
    <skip_proc>yes</skip_proc>
    <skip_sys>yes</skip_sys>
  </syscheck>

  <localfile>
    <log_format>audit</log_format>
    <location>/var/log/audit/audit.log</location>
  </localfile>
  
  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/nginx/react2shell_access.log</location>
  </localfile>

  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/nginx/react2shell_error.log</location>
  </localfile>
  
  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/nginx/access.log</location>
  </localfile>
  
  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/nginx/error.log</location>
  </localfile>
  
  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/auth.log</location>
  </localfile>
  
  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/syslog</location>
  </localfile>
  
  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/dpkg.log</location>
  </localfile>

</agent_config>
```

4. Click **Save**

### 2.4 Cấu hình Group Internal_Servers (Database-Server)

1. Vào **Server management** → **Groups** → chọn **Internal_Servers**
2. Click **Files** → chọn **agent.conf** → **Edit**
3. Dán nội dung sau:

```xml
<agent_config>
  <syscheck>
    <disabled>no</disabled>
    <frequency>180</frequency>
    <directories realtime="yes" check_all="yes" report_changes="yes">/</directories>
  
    <ignore>/proc</ignore>
    <ignore>/sys</ignore>
    <ignore>/dev</ignore>
    <ignore>/run</ignore>
    <ignore>/snap</ignore>

    <ignore>/var/log</ignore>
    
    <ignore>/tmp</ignore>
    <ignore>/var/tmp</ignore>
    <ignore>/var/cache</ignore>
    
    <ignore>/var/lib/dpkg</ignore>
    <ignore>/var/lib/apt</ignore>
    
    <ignore>/var/ossec/queue</ignore>
    <ignore>/var/ossec/var</ignore>
    <ignore>/var/ossec/logs</ignore>
    <ignore>/var/ossec/tmp</ignore>
    <ignore>/var/ossec/etc/shared</ignore>
    <ignore>/var/run/zabbix</ignore>
    <ignore type="sregex">postgresql/.*/main/base</ignore>
    <ignore type="sregex">postgresql/.*/main/global</ignore>
    <ignore type="sregex">postgresql/.*/main/pg_wal</ignore>
    <ignore type="sregex">postgresql/.*/main/pg_stat_tmp</ignore>
    <ignore type="sregex">postgresql/.*/main/pg_logical</ignore>
    <ignore type="sregex">postgresql/.*/main/pg_replslot</ignore>
    <ignore type="sregex">postgresql/.*/main/pg_snapshots</ignore>
    <ignore type="sregex">postgresql/.*/main/pg_serial</ignore>
    <ignore type="sregex">postgresql/.*/main/pg_notify</ignore>
    <ignore type="sregex">postgresql/.*/main/pg_subtrans</ignore>
    <ignore type="sregex">postgresql/.*/main/pg_multixact</ignore>
    <ignore type="sregex">postgresql/.*/main/pg_xact</ignore>
    <ignore type="sregex">postgresql/.*/main/pg_commit_ts</ignore>
    <ignore>/etc/mtab</ignore>
    <ignore>/etc/hosts.deny</ignore>
    <ignore>/etc/random-seed</ignore>
    <ignore>/etc/adjtime</ignore>
    <ignore>/etc/resolv.conf</ignore>
    <ignore>/etc/ld.so.cache</ignore>
    
    <skip_nfs>yes</skip_nfs>
    <skip_dev>yes</skip_dev>
    <skip_proc>yes</skip_proc>
    <skip_sys>yes</skip_sys>
  </syscheck>

  <localfile>
    <log_format>audit</log_format>
    <location>/var/log/audit/audit.log</location>
  </localfile>

  <localfile>
    <log_format>postgresql_log</log_format>
    <location>/var/log/postgresql/postgresql-*-main.log</location>
  </localfile>

  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/auth.log</location>
  </localfile>

  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/syslog</location>
  </localfile>

  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/dpkg.log</location>
  </localfile>

</agent_config>
```

4. Click **Save**

### 2.5 Kiểm tra cấu hình đã đẩy xuống Agent

Sau khi save, Wazuh Manager sẽ tự động đẩy `agent.conf` xuống các agent trong group.
Kiểm tra trên agent (nếu cần):

```bash
# Trên Web-Server hoặc DB-Server
cat /var/ossec/etc/shared/agent.conf
```

### 2.6 Kiểm tra FIM hoạt động

Tạo file test trên Web-Server hoặc DB-Server:

```bash
sudo touch /etc/fim_test_file
# Đợi vài giây rồi xóa
sudo rm /etc/fim_test_file
```

Kiểm tra trên Wazuh Dashboard:
- Vào **Threat intelligence** → **Threat Hunting** → filter `rule.groups: syscheck`
- Hoặc vào agent cụ thể → **Integrity monitoring** tab

---

## 3️⃣ Cài đặt Zabbix Agent 2 - Trên Web-Server & Database-Server

> **Thực hiện trên cả 2 máy**: Web-Server (192.168.20.15) và Database-Server (192.168.30.15)
> Zabbix Server IP: 192.168.40.10

### 3.1 Thêm Zabbix Repository (Ubuntu 24.04)

```bash
sudo -s
wget https://repo.zabbix.com/zabbix/7.4/release/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_7.4+ubuntu24.04_all.deb
dpkg -i zabbix-release_latest_7.4+ubuntu24.04_all.deb
apt update
```

### 3.2 Cài đặt Zabbix Agent 2 + Plugins

```bash
apt install zabbix-agent2 -y
apt install zabbix-agent2-plugin-mongodb zabbix-agent2-plugin-mssql zabbix-agent2-plugin-postgresql -y
```

### 3.3 Cấu hình Zabbix Agent 2

```bash
sudo nano /etc/zabbix/zabbix_agent2.conf
```

#### Trên Web-Server (192.168.20.15):

```ini
Server=192.168.40.10
ServerActive=192.168.40.10
Hostname=Web-Server
# ListenPort=10050 (default)
```

#### Trên Database-Server (192.168.30.15):

```ini
Server=192.168.40.10
ServerActive=192.168.40.10
Hostname=Database-Server
# ListenPort=10050 (default)
```

### 3.4 Khởi động và kích hoạt dịch vụ

```bash
sudo systemctl enable zabbix-agent2
sudo systemctl start zabbix-agent2
sudo systemctl status zabbix-agent2
```

### 3.5 Mở firewall cho Zabbix (nếu dùng ufw)

```bash
sudo ufw allow 10050/tcp comment "Zabbix Agent 2"
sudo ufw reload
```

### 3.6 Kiểm tra kết nối từ Zabbix Server (192.168.40.10)

```bash
# Trên Zabbix Server, test kết nối tới agent
zabbix_get -s 192.168.20.15 -k agent.ping    # Test Web-Server
zabbix_get -s 192.168.30.15 -k agent.ping    # Test Database-Server
```

### 3.7 Thêm Host trên Zabbix Web UI

1. Truy cập Zabbix Web UI: `http://192.168.40.10/zabbix`
2. Vào **Data collection** → **Hosts** → **Create host**

#### Host: Web-Server
- **Host name**: `Web-Server`
- **Groups**: `Linux servers`
- **Interfaces**: Agent → IP: `192.168.20.15`, Port: `10050`
- **Templates**: Gán `Linux by Zabbix agent`, `Nginx by Zabbix agent`
- **Macros** (tab Macros → Add):

| Macro | Value |
|-------|-------|
| `{$NGINX.STUB_STATUS.HOST}` | `127.0.0.1` |
| `{$NGINX.STUB_STATUS.PORT}` | `8080` |
| `{$NGINX.STUB_STATUS.PATH}` | `basic_status` |
| `{$NGINX.PROCESS_NAME}` | `nginx` |

#### Host: Database-Server
- **Host name**: `Database-Server`
- **Groups**: `Linux servers`
- **Interfaces**: Agent → IP: `192.168.30.15`, Port: `10050`
- **Templates**: Gán `Linux by Zabbix agent`, `PostgreSQL by Zabbix agent 2 active`
- **Macros** (tab Macros → Add):

| Macro | Value |
|-------|-------|
| `{$PG.CONNSTRING.AGENT2}` | `tcp://192.168.30.15:5432` |
| `{$PG.DATABASE}` | `postgres` |
| `{$PG.USER}` | `zbx_monitor` |
| `{$PG.PASSWORD}` | `zabbix_monitor_password` |

> ⚠️ **Lưu ý**: Dùng `tcp://192.168.30.15:5432` thay vì `tcp://localhost:5432` vì PostgreSQL listen trên IP `192.168.30.15`.

> ℹ️ **Replication discovery**: Nếu không dùng replication, vào **Discovery rules** → **PostgreSQL: Replication discovery** → **Disable**

---

### 3.8 Cấu hình Zabbix Agent 2 monitor PostgreSQL (Trên Database-Server)

> Database-Server sử dụng **PostgreSQL** → cần cấu hình thêm Zabbix Agent 2 để monitor

#### Bước 1: Tạo/Sửa user monitoring trên PostgreSQL

```bash
sudo -u postgres psql
```

```sql
-- Tạo user mới (bỏ qua nếu đã tồn tại)
CREATE USER zbx_monitor WITH PASSWORD 'zabbix_monitor_password' INHERIT;

-- Hoặc nếu user đã tồn tại, sửa password và grant quyền:
ALTER USER zbx_monitor WITH PASSWORD 'zabbix_monitor_password' INHERIT;
GRANT pg_monitor TO zbx_monitor;
GRANT CONNECT ON DATABASE postgres TO zbx_monitor;
GRANT CONNECT ON DATABASE elearning TO zbx_monitor;
\q
```

#### Bước 2: Cấu hình `pg_hba.conf`

```bash
sudo nano /etc/postgresql/16/main/pg_hba.conf
```

Cấu hình cho lab (cho phép rộng):

```
# Cho phép rộng trong lab
host    all     all     0.0.0.0/0       scram-sha-256
```

Reload và kiểm tra:

```bash
sudo systemctl reload postgresql

# Kiểm tra rules đã load
sudo -u postgres psql -c "SELECT line_number,type,database,user_name,address,auth_method,error FROM pg_hba_file_rules ORDER BY line_number;"
```

#### Bước 3: Cấu hình Zabbix Agent 2 plugin PostgreSQL

Tạo file cấu hình plugin:

```bash
sudo nano /etc/zabbix/zabbix_agent2.d/plugins.d/postgresql.conf
```

```ini
Plugins.PostgreSQL.Sessions.dbname.Uri=tcp://192.168.30.15:5432
Plugins.PostgreSQL.Sessions.dbname.User=zbx_monitor
Plugins.PostgreSQL.Sessions.dbname.Password=zabbix_monitor_password
Plugins.PostgreSQL.Sessions.dbname.Database=postgres
```

> **Lưu ý**: Dùng `tcp://192.168.30.15:5432` (IP thật) thay vì `tcp://127.0.0.1:5432`

Restart Zabbix Agent 2:

```bash
sudo systemctl restart zabbix-agent2
```

#### Bước 4: Kiểm tra PostgreSQL monitoring

```bash
# Test ping
zabbix_agent2 -t 'pgsql.ping["tcp://192.168.30.15:5432","zbx_monitor","zabbix_monitor_password","postgres"]'
# Kết quả mong đợi: [s|1.000000]

# Test database discovery
zabbix_agent2 -t 'pgsql.db.discovery["tcp://192.168.30.15:5432","zbx_monitor","zabbix_monitor_password","postgres"]'
# Kết quả mong đợi: {"data" : [{"{#DBNAME}" : "postgres"}, {"{#DBNAME}" : "elearning"}]}

# Test kết nối từ psql
PGPASSWORD='zabbix_monitor_password' psql -h 192.168.30.15 -U zbx_monitor -d postgres -c "select version();"
```

### 3.9 Mở port 10051 cho Zabbix Active Check

> Template `PostgreSQL by Zabbix agent 2 active` yêu cầu agent chủ động gửi data về Zabbix Server qua port **10051**

```bash
# Test kết nối từ DB-Server đến Zabbix Server
nc -vz 192.168.40.10 10051
```

Nếu timeout, mở firewall trên Sophos:

| Source | Destination | Port | Action |
|--------|------------|------|--------|
| `192.168.30.15` | `192.168.40.10` | TCP 10051 | Pass |
| `192.168.20.15` | `192.168.40.10` | TCP 10051 | Pass |

Sau khi mở port, reload Zabbix Server cache:

```bash
# Trên Zabbix Server (192.168.40.10)
sudo zabbix_server -R config_cache_reload
```

Trên Zabbix Web: **Data collection** → **Hosts** → **Database-Server** → **Discovery rules** → **PostgreSQL: Database discovery** → **Execute now**

---

## 4️⃣ Tổng hợp: Cấu hình FIM + Log + Group đã thực hiện ở Mục 2

> ✅ Việc tạo group, gán agent, cấu hình FIM và thu thập log **đã thực hiện hoàn toàn qua Wazuh GUI** ở **Mục 2** phía trên.
> Không cần SSH vào Wazuh Manager để cấu hình thủ công.

### 4.6 Xác nhận Group Assignment

```bash
# Kiểm tra agent thuộc group nào
sudo /var/ossec/bin/agent_groups -l

# Kiểm tra chi tiết agent
sudo /var/ossec/bin/agent_groups -l -g DMZ_Servers
sudo /var/ossec/bin/agent_groups -l -g Internal_Servers
```

### 4.7 Restart Wazuh Manager

```bash
sudo systemctl restart wazuh-manager
```

---

## 5️⃣ Cấu hình Sophos Firewall - Cho phép traffic giữa các Zone

### 5.1 Firewall Rules cần thiết

| #  | Source Zone      | Dest Zone    | Source          | Dest              | Service              | Action |
|----|------------------|--------------|-----------------|-------------------|----------------------|--------|
| 1  | DMZ              | SOC_SOAR     | Web-Server      | Zabbix (40.20)    | TCP 10050, 10051     | Allow  |
| 2  | DMZ              | SOC_SOAR     | Web-Server      | Wazuh (40.10)     | TCP 1514, 1515       | Allow  |
| 3  | Internal-Server  | SOC_SOAR     | DB-Server       | Zabbix (40.20)    | TCP 10050, 10051     | Allow  |
| 4  | Internal-Server  | SOC_SOAR     | DB-Server       | Wazuh (40.10)     | TCP 1514, 1515       | Allow  |
| 5  | SOC_SOAR         | DMZ          | Zabbix (40.20)  | Web-Server        | TCP 10050            | Allow  |
| 6  | SOC_SOAR         | Internal     | Zabbix (40.20)  | DB-Server         | TCP 10050            | Allow  |
| 7  | WAN              | DMZ          | Any             | Web-Server        | TCP 80, 443          | Allow  |
| 8  | DMZ              | Internal     | Web-Server      | DB-Server         | TCP 5432             | Allow  |
| 9  | Internal-Server  | SOC_SOAR     | DB-Server       | Zabbix (40.20)    | TCP 10051 (active)   | Allow  |
| 10 | DMZ              | SOC_SOAR     | Web-Server      | Zabbix (40.20)    | TCP 10051 (active)   | Allow  |

> ⚠️ **Rule 9-10**: Cần thiết cho **Zabbix Active Check** — agent chủ động gửi data về Zabbix Server qua port 10051

### 5.2 Port Summary

| Service                | Port(s)             | Protocol | Ghi chú |
|------------------------|---------------------|----------|--------|
| Zabbix Agent (passive) | 10050               | TCP      | Server → Agent |
| Zabbix Trapper (active)| 10051               | TCP      | Agent → Server |
| Wazuh Agent            | 1514                | TCP/UDP  | Agent → Manager |
| Wazuh Register         | 1515                | TCP      | Agent → Manager |
| HTTP                   | 80                  | TCP      | |
| HTTPS                  | 443                 | TCP      | |
| PostgreSQL             | 5432                | TCP      | |
| Wazuh API              | 55000               | TCP      | |

---

## 6️⃣ Kiểm tra tổng thể

### Checklist trên Web-Server (192.168.20.15)

```bash
# Dịch vụ
sudo systemctl status nginx
sudo systemctl status auditd
sudo systemctl status wazuh-agent
sudo systemctl status zabbix-agent2

# Audit rules
sudo auditctl -l

# FIM config từ Wazuh group
cat /var/ossec/etc/shared/agent.conf

# Nginx test
sudo nginx -t
curl http://127.0.0.1:8080/basic_status

# Zabbix Nginx monitoring
zabbix_agent2 -t 'web.page.get["127.0.0.1","basic_status","8080"]'
zabbix_agent2 -t 'net.tcp.service[http,"127.0.0.1","8080"]'
```

### Checklist trên Database-Server (192.168.30.15)

```bash
# Dịch vụ
sudo systemctl status auditd
sudo systemctl status wazuh-agent
sudo systemctl status zabbix-agent2
sudo systemctl status postgresql@16-main  # Kiểm tra service con thay vì service quản lý chung

# Audit rules
sudo auditctl -l

# FIM config từ Wazuh group
cat /var/ossec/etc/shared/agent.conf

# PostgreSQL
sudo -u postgres psql -c "SELECT 1;"
sudo -u postgres psql -c "SELECT line_number,type,database,user_name,address,auth_method,error FROM pg_hba_file_rules ORDER BY line_number;"

# Zabbix PostgreSQL monitoring
zabbix_agent2 -t 'pgsql.ping["tcp://192.168.30.15:5432","zbx_monitor","zabbix_monitor_password","postgres"]'
zabbix_agent2 -t 'pgsql.db.discovery["tcp://192.168.30.15:5432","zbx_monitor","zabbix_monitor_password","postgres"]'

# Active check connectivity
nc -vz 192.168.40.10 10051
```

### Checklist trên Wazuh Manager (192.168.40.15)

```bash
sudo /var/ossec/bin/agent_groups -l -g DMZ_Servers
sudo /var/ossec/bin/agent_groups -l -g Internal_Servers
```

### Checklist trên Zabbix Server (192.168.40.10)

```bash
# Test passive agent
zabbix_get -s 192.168.20.15 -k agent.ping   # → 1
zabbix_get -s 192.168.30.15 -k agent.ping   # → 1

# Reload config cache (sau khi thêm/sửa host)
sudo zabbix_server -R config_cache_reload
```

### Kiểm tra trên Dashboard

- **Wazuh Dashboard** (`https://192.168.40.15`): Agents online, FIM alerts, audit logs
- **Zabbix Web** (`http://192.168.40.10/zabbix`):
  - **Monitoring** → **Latest data** → filter `PostgreSQL` hoặc `Nginx`
  - **Data collection** → **Hosts** → kiểm tra icon availability xanh
  - Database-Server → **Discovery rules** → **PostgreSQL: Database discovery** → **Execute now**

---

## 📝 Ghi chú

- **Không hardcode IP public** trong Nginx — dùng `server_name _` và `$http_host`
- PostgreSQL và Zabbix dùng **IP nội bộ đúng vai trò**: `192.168.30.15` cho DB, `192.168.40.10` cho Zabbix Server
- FIM và log collection quản lý tập trung qua **Wazuh GUI** → không cần SSH vào agent
- Thay đổi password `zbx_monitor` cho môi trường production
- **Zabbix Active Check** cần mở port **10051** trên firewall (agent → server)
- Nếu không dùng PostgreSQL replication, disable **Replication discovery** trên Zabbix
- Lỗi `system.sw.os` là trigger Linux chưa đủ data, chỉ cần chờ hoặc bấm **Check now**