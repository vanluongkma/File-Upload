# ============================================================
# 04-Build-TechVina-Foothold.ps1
# CyberRange 2 — Foothold Setup
#
# Script này cài đặt môi trường Initial Access trên WS01:
# - Cài đặt Python 3, LibreOffice
# - Tạo Fake HR Service (HTTP + SMTP) chạy ẩn
# ============================================================

$ErrorActionPreference = "Stop"
$LogFile = "C:\CyberRange2-Setup\04-Build-TechVina-Foothold.log"
if (-not (Test-Path "C:\CyberRange2-Setup")) { New-Item -ItemType Directory -Path "C:\CyberRange2-Setup" | Out-Null }
Start-Transcript -Path $LogFile -Append

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " CYBERRANGE 2 - SETUP FOOTHOLD ON WS01" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$HRWebDir = "C:\LabServices\HRWeb"
if (-not (Test-Path $HRWebDir)) {
    New-Item -ItemType Directory -Path $HRWebDir -Force | Out-Null
}
if (-not (Test-Path "C:\Temp")) {
    New-Item -ItemType Directory -Path "C:\Temp" -Force | Out-Null
}

$WebClient = New-Object System.Net.WebClient

# 1. Download and Install Python
Write-Host "[+] Downloading and Installing Python 3..."
$PythonInstaller = "C:\Temp\python-installer.exe"
if (-not (Test-Path $PythonInstaller)) {
    try {
        $WebClient.DownloadFile("https://www.python.org/ftp/python/3.10.11/python-3.10.11-amd64.exe", $PythonInstaller)
    } catch {
        Write-Host "[!] Failed to download Python: $_" -ForegroundColor Red
        Write-Host "[!] Please place installer at $PythonInstaller manually." -ForegroundColor Red
    }
}
if (Test-Path $PythonInstaller) {
    Start-Process -FilePath $PythonInstaller -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1" -Wait
}

# 2. Download and Install LibreOffice
Write-Host "[+] Downloading and Installing LibreOffice (This may take a few minutes)..."
$LOInstaller = "C:\Temp\LibreOffice_7.6.7.2_Win_x86-64.msi"
if (-not (Test-Path $LOInstaller)) {
    try {
        $WebClient.DownloadFile("https://downloadarchive.documentfoundation.org/libreoffice/old/7.6.7.2/win/x86_64/LibreOffice_7.6.7.2_Win_x86-64.msi", $LOInstaller)
    } catch {
        Write-Host "[!] Failed to download LibreOffice: $_" -ForegroundColor Red
        Write-Host "[!] Please place installer at $LOInstaller manually." -ForegroundColor Red
    }
}
if (Test-Path $LOInstaller) {
    Start-Process -FilePath "msiexec.exe" -ArgumentList "/i $LOInstaller /qn" -Wait
}

# 3. Create index.html
$IndexHTML = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>TechVina Corporation | Careers</title>
    <style>
        :root {
            --primary: #2563eb;
            --primary-dark: #1d4ed8;
            --secondary: #0f172a;
            --accent: #38bdf8;
            --danger: #ef4444;
            --bg-color: #f8fafc;
            --surface: #ffffff;
            --text-main: #334155;
            --text-muted: #64748b;
        }
        
        * { box-sizing: border-box; margin: 0; padding: 0; }

        body { 
            font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            background: linear-gradient(135deg, #f8fafc 0%, #e2e8f0 100%);
            color: var(--text-main);
            min-height: 100vh;
            line-height: 1.6;
        }

        header { 
            background: linear-gradient(90deg, var(--secondary) 0%, #1e293b 100%);
            color: white; 
            padding: 4rem 1rem; 
            text-align: center; 
            box-shadow: 0 4px 20px rgba(0,0,0,0.1);
            position: relative;
            overflow: hidden;
        }

        header::before {
            content: '';
            position: absolute;
            top: -50%; left: -10%;
            width: 50%; height: 200%;
            background: radial-gradient(circle, rgba(56,189,248,0.1) 0%, transparent 70%);
            transform: rotate(30deg);
        }

        h1 { 
            font-size: 3rem;
            font-weight: 800;
            letter-spacing: -1px;
            margin-bottom: 0.5rem;
            background: linear-gradient(to right, #fff, var(--accent));
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }
        
        header p {
            font-size: 1.25rem;
            color: #94a3b8;
            font-weight: 300;
            letter-spacing: 2px;
            text-transform: uppercase;
        }

        .container { 
            max-width: 900px; 
            margin: -3rem auto 3rem; 
            background: rgba(255, 255, 255, 0.95); 
            padding: 3rem; 
            border-radius: 16px; 
            box-shadow: 0 20px 40px rgba(0,0,0,0.08); 
            backdrop-filter: blur(10px);
            border: 1px solid rgba(255,255,255,0.5);
            position: relative;
            z-index: 10;
        }

        h2 {
            color: var(--secondary);
            font-size: 2rem;
            margin-bottom: 1rem;
            border-bottom: 2px solid #e2e8f0;
            padding-bottom: 1rem;
        }

        .intro {
            font-size: 1.1rem;
            color: var(--text-muted);
            margin-bottom: 2.5rem;
        }

        .job-listing { 
            background: var(--surface);
            border: 1px solid #e2e8f0;
            border-left: 5px solid var(--primary); 
            padding: 1.5rem; 
            margin-bottom: 1.5rem; 
            border-radius: 8px;
            transition: all 0.3s ease;
            box-shadow: 0 2px 5px rgba(0,0,0,0.02);
        }

        .job-listing:hover {
            transform: translateY(-3px);
            box-shadow: 0 10px 20px rgba(0,0,0,0.05);
            border-left-color: var(--accent);
        }

        .job-title { 
            font-size: 1.4rem; 
            font-weight: 700; 
            color: var(--secondary);
            margin-bottom: 0.5rem;
            display: flex;
            align-items: center;
            justify-content: space-between;
        }
        
        .badge {
            font-size: 0.8rem;
            background: #dbeafe;
            color: var(--primary-dark);
            padding: 0.2rem 0.8rem;
            border-radius: 99px;
            font-weight: 600;
            text-transform: uppercase;
        }

        .apply-box { 
            background: linear-gradient(to right bottom, #f0f9ff, #e0f2fe);
            border: 1px solid #bae6fd; 
            padding: 2.5rem; 
            border-radius: 12px; 
            margin-top: 3.5rem; 
            text-align: center;
            box-shadow: inset 0 2px 10px rgba(255,255,255,0.5);
        }

        .apply-box h3 {
            color: var(--primary-dark);
            font-size: 1.8rem;
            margin-bottom: 1rem;
        }

        .email-link {
            display: inline-block;
            background: var(--primary);
            color: white;
            font-size: 1.2rem;
            font-weight: bold;
            text-decoration: none;
            padding: 1rem 2.5rem;
            border-radius: 50px;
            margin: 1.5rem 0;
            transition: all 0.3s ease;
            box-shadow: 0 4px 15px rgba(37, 99, 235, 0.3);
            animation: pulse 2s infinite;
        }

        .email-link:hover {
            background: var(--primary-dark);
            transform: scale(1.05);
            box-shadow: 0 6px 20px rgba(37, 99, 235, 0.4);
            animation: none;
        }

        @keyframes pulse {
            0% { box-shadow: 0 0 0 0 rgba(37, 99, 235, 0.4); }
            70% { box-shadow: 0 0 0 15px rgba(37, 99, 235, 0); }
            100% { box-shadow: 0 0 0 0 rgba(37, 99, 235, 0); }
        }

        .warning-box {
            background: #fef2f2;
            border-left: 4px solid var(--danger);
            padding: 1.5rem;
            border-radius: 0 8px 8px 0;
            margin-top: 2rem;
            text-align: left;
        }

        .warning-title { 
            color: var(--danger); 
            font-weight: 800; 
            display: flex;
            align-items: center;
            gap: 8px;
            margin-bottom: 0.5rem;
        }

        .warning-text {
            color: #991b1b;
            font-size: 0.95rem;
        }
        
        .footer {
            text-align: center;
            color: var(--text-muted);
            font-size: 0.9rem;
            margin-top: 4rem;
            padding-bottom: 2rem;
        }
    </style>
</head>
<body>
    <header>
        <h1>TechVina Corporation</h1>
        <p>Innovating the Future</p>
    </header>
    
    <div class="container">
        <h2>Open Positions</h2>
        <p class="intro">Join our dynamic team and help build cutting-edge enterprise solutions. We are constantly looking for talented individuals to drive our vision forward.</p>
        
        <div class="job-listing">
            <div class="job-title">
                Senior Software Engineer
                <span class="badge">Full-time</span>
            </div>
            <p><strong>Requirements:</strong> 5+ years of experience in .NET, C#, and enterprise architecture. Deep understanding of Active Directory integration is a plus.</p>
        </div>
        
        <div class="job-listing">
            <div class="job-title">
                IT Support Intern
                <span class="badge">Internship</span>
            </div>
            <p><strong>Requirements:</strong> Basic knowledge of Windows Server, Active Directory, and networking. Passionate about cybersecurity and system administration.</p>
        </div>
        
        <div class="apply-box">
            <h3>Ready to Join Us?</h3>
            <p>Send your resume directly to our HR Recruitment team:</p>
            
            <a href="mailto:hr@techvina.local" class="email-link">hr@techvina.local</a>
            
            <div class="warning-box">
                <div class="warning-title">
                    ⚠️ IMPORTANT NOTICE
                </div>
                <div class="warning-text">
                    As part of our internal security policy and transition to open-source software, we <strong>ONLY accept resumes in LibreOffice format (.odt)</strong>. <br><br>
                    <em>Note: Standard formats like .doc, .docx, or .pdf will be automatically dropped by our mail filter.</em>
                </div>
            </div>
        </div>
    </div>
    
    <div class="footer">
        &copy; 2024-2025 TechVina Corporation. All rights reserved.
    </div>
</body>
</html>
"@
$IndexHTML | Out-File "$HRWebDir\index.html" -Encoding UTF8

# 4. Create hr_bot.py
$HRBotPy = @"
import socket, threading, email, os, subprocess, time
from email import policy

HTTP_PORT = 80
SMTP_PORT = 25
CV_DIR = r"C:\Temp\CVs"

if not os.path.exists(CV_DIR):
    os.makedirs(CV_DIR)

def handle_http(client_socket):
    try:
        request = client_socket.recv(1024).decode('utf-8', errors='ignore')
        if request:
            with open(r"C:\LabServices\HRWeb\index.html", "r", encoding="utf-8") as f:
                html = f.read()
            response = f"HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: {len(html)}\r\n\r\n{html}"
            client_socket.sendall(response.encode('utf-8'))
    except Exception as e:
        pass
    finally:
        client_socket.close()

def http_server():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.bind(("0.0.0.0", HTTP_PORT))
    server.listen(5)
    while True:
        client, _ = server.accept()
        threading.Thread(target=handle_http, args=(client,)).start()

def process_email(raw_email):
    msg = email.message_from_bytes(raw_email, policy=policy.default)
    for part in msg.walk():
        if part.get_content_maintype() == 'multipart' or part.get('Content-Disposition') is None:
            continue
        filename = part.get_filename()
        if filename and filename.endswith('.odt'):
            filepath = os.path.join(CV_DIR, filename)
            with open(filepath, 'wb') as f:
                f.write(part.get_payload(decode=True))
            
            try:
                subprocess.run(["taskkill", "/F", "/IM", "soffice.exe"], capture_output=True)
                subprocess.run(["taskkill", "/F", "/IM", "soffice.bin"], capture_output=True)
                time.sleep(1)
                
                lo_path = r"C:\Program Files\LibreOffice\program\soffice.exe"
                if os.path.exists(lo_path):
                    # Add --norestore to prevent the recovery popup from blocking macro execution
                    subprocess.Popen([lo_path, "--norestore", "--nologo", filepath])
                    def cleanup():
                        time.sleep(30)
                        subprocess.run(["taskkill", "/F", "/IM", "soffice.exe"], capture_output=True)
                        subprocess.run(["taskkill", "/F", "/IM", "soffice.bin"], capture_output=True)
                    threading.Thread(target=cleanup).start()
            except:
                pass

def handle_smtp(client_socket):
    try:
        client_socket.sendall(b"220 techvina.local ESMTP Postfix\r\n")
        data = b""
        receiving_data = False
        email_data = b""
        while True:
            chunk = client_socket.recv(1024)
            if not chunk: break
            data += chunk
            if receiving_data:
                email_data += chunk
                if b"\r\n.\r\n" in email_data:
                    client_socket.sendall(b"250 Ok: queued as 12345\r\n")
                    receiving_data = False
                    process_email(email_data)
                    email_data = b""
            else:
                if b"\r\n" in data:
                    lines = data.split(b"\r\n")
                    for i in range(len(lines) - 1):
                        line = lines[i].decode('utf-8', errors='ignore').strip()
                        if line.upper().startswith("HELO") or line.upper().startswith("EHLO"):
                            client_socket.sendall(b"250 techvina.local\r\n")
                        elif line.upper().startswith("MAIL FROM:") or line.upper().startswith("RCPT TO:"):
                            client_socket.sendall(b"250 Ok\r\n")
                        elif line.upper() == "DATA":
                            client_socket.sendall(b"354 End data with <CR><LF>.<CR><LF>\r\n")
                            receiving_data = True
                        elif line.upper() == "QUIT":
                            client_socket.sendall(b"221 Bye\r\n")
                            return
                    data = lines[-1]
    except Exception as e:
        pass
    finally:
        client_socket.close()

def smtp_server():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.bind(("0.0.0.0", SMTP_PORT))
    server.listen(5)
    while True:
        client, _ = server.accept()
        threading.Thread(target=handle_smtp, args=(client,)).start()

if __name__ == "__main__":
    threading.Thread(target=http_server, daemon=True).start()
    threading.Thread(target=smtp_server, daemon=True).start()
    while True: time.sleep(60)
"@
$HRBotPy | Out-File "$HRWebDir\hr_bot.py" -Encoding UTF8

# 5. Configure LibreOffice Macro Security for new users (via Default profile)
Write-Host "[+] Configuring LibreOffice Macro Security..."
$LODir = "C:\Users\Default\AppData\Roaming\LibreOffice\4\user"
if (-not (Test-Path $LODir)) {
    New-Item -Path $LODir -ItemType Directory -Force | Out-Null
}
$MacroConfig = @"
<?xml version="1.0" encoding="UTF-8"?>
<oor:items xmlns:oor="http://openoffice.org/2001/registry" xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
<item oor:path="/org.openoffice.Office.Common/Security/Scripting"><prop oor:name="MacroSecurityLevel" oor:op="fuse"><value>0</value></prop></item>
</oor:items>
"@
$MacroConfig | Out-File "$LODir\registrymodifications.xcu" -Encoding UTF8

# 6. Create VBS wrapper to run hidden at startup (All Users)
Write-Host "[+] Setting up HR Bot to run at startup..."
$StartupFolder = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp"
if (-not (Test-Path $StartupFolder)) {
    New-Item -Path $StartupFolder -ItemType Directory -Force | Out-Null
}
$VBScript = @"
Set WshShell = CreateObject("WScript.Shell")
Do
    WshShell.Run """C:\Program Files\Python310\python.exe"" ""C:\LabServices\HRWeb\hr_bot.py""", 0, True
    WScript.Sleep 5000
Loop
"@
$VBScript | Out-File "$StartupFolder\start_hr_bot.vbs" -Encoding ASCII

# 7. Add Firewall rules
Write-Host "[+] Adding Firewall Rules..."
New-NetFirewallRule -DisplayName "CyberRange2-HRBot" -Direction Inbound -LocalPort 80,25 -Protocol TCP -Action Allow -Profile Any -ErrorAction SilentlyContinue | Out-Null

Write-Host "[+] Foothold setup completed successfully!" -ForegroundColor Green

Stop-Transcript
