# ============================================================
# 03-Build-TechVina-WS01.ps1
# CyberRange 2 — Red Team Full-Chain Lab
# Domain: techvina.local
# Machine: TV-WS01 (Windows 10 Workstation)
#
# Chay script nay SAU KHI:
# 1. TV-WS01 da join domain techvina.local
# 2. Script 01 (DC) va 02 (SRV01) da chay xong
#
# Script nay cau hinh: Initial access point, credential artifacts,
# local PrivEsc vectors, browser/app credential simulation.
# ============================================================

$ErrorActionPreference = "Stop"

$ExpectedDomain = "techvina.local"
$SetupFolder = "C:\CyberRange2-Setup"
$LogFile = "$SetupFolder\03-Build-TechVina-WS01.log"

if (-not (Test-Path $SetupFolder)) {
    New-Item -ItemType Directory -Path $SetupFolder -Force | Out-Null
}

Start-Transcript -Path $LogFile -Append

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " CYBERRANGE 2 - BUILD TECHVINA WS01" -ForegroundColor Cyan
Write-Host " Workstation - Initial Access Point" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# ------------------------------
# 1. CHECK DOMAIN JOIN
# ------------------------------

$ComputerInfo = Get-ComputerInfo
$CurrentDomain = $ComputerInfo.CsDomain
$IsPartOfDomain = $ComputerInfo.CsPartOfDomain

if (-not $IsPartOfDomain -or $CurrentDomain -ne $ExpectedDomain) {
    Write-Host "[X] May nay chua join domain $ExpectedDomain" -ForegroundColor Red
    Write-Host "[X] Current domain: $CurrentDomain" -ForegroundColor Red
    Write-Host "[!] Hay join domain truoc:" -ForegroundColor Yellow
    Write-Host "Add-Computer -DomainName $ExpectedDomain -Credential (Get-Credential) -Restart" -ForegroundColor Cyan
    Stop-Transcript
    exit 1
}

Write-Host "[OK] Joined domain: $CurrentDomain" -ForegroundColor Green

$NetBIOS = ($ExpectedDomain -split '\.')[0].ToUpper()

# ------------------------------
# 2. RENAME COMPUTER IF NEEDED
# ------------------------------

$DesiredName = "TV-WS01"
if ($env:COMPUTERNAME -ne $DesiredName) {
    Write-Host "[!] Hostname should be $DesiredName, current is $env:COMPUTERNAME" -ForegroundColor Yellow
    Write-Host "[!] Rename with: Rename-Computer -NewName $DesiredName -DomainCredential (Get-Credential) -Restart" -ForegroundColor Cyan
}

# ------------------------------
# 3. CREATE FOLDER STRUCTURE
# ------------------------------

Write-Host "[+] Creating folder structure..." -ForegroundColor Yellow

$Folders = @(
    "C:\Tools",
    "C:\LabServices",
    "C:\LabServices\TVEndpointAgent",
    "C:\Temp",
    # User profile simulation directories
    "C:\Users\intern.nguyenminh\Desktop",
    "C:\Users\intern.nguyenminh\Documents",
    "C:\Users\intern.nguyenminh\Downloads",
    "C:\Users\admin.leduc\Desktop",
    "C:\Users\admin.leduc\Documents",
    "C:\Users\admin.leduc\Documents\Projects",
    "C:\Users\admin.leduc\AppData\Local",
    "C:\Users\admin.leduc\AppData\Roaming",
    "C:\Users\admin.leduc\AppData\Roaming\FileZilla",
    "C:\Users\admin.leduc\AppData\Local\Microsoft\Credentials"
)

foreach ($Folder in $Folders) {
    if (-not (Test-Path $Folder)) {
        New-Item -ItemType Directory -Path $Folder -Force | Out-Null
    }
}

# ------------------------------
# 4. ADD C:\Tools TO SYSTEM PATH (DLL Hijacking)
# ------------------------------

Write-Host "[+] Adding C:\Tools to system PATH (DLL Hijack vector)..." -ForegroundColor Yellow

$CurrentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
if ($CurrentPath -notlike "*C:\Tools*") {
    [Environment]::SetEnvironmentVariable("Path", "$CurrentPath;C:\Tools", "Machine")
    Write-Host "[!] C:\Tools added to system PATH (writable by Users!)" -ForegroundColor Red
}

# Make C:\Tools writable by Users
$ToolsACL = Get-Acl "C:\Tools"
$WritableRule = New-Object System.Security.AccessControl.FileSystemAccessRule("BUILTIN\Users", "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
$ToolsACL.SetAccessRule($WritableRule)
Set-Acl "C:\Tools" $ToolsACL

# ------------------------------
# 5. VULNERABLE SERVICES (LOCAL PRIVESC)
# ------------------------------

Write-Host "[+] Creating vulnerable services..." -ForegroundColor Yellow

# === Unquoted Service Path with spaces ===
$AgentBat = "C:\LabServices\TVEndpointAgent\TV Endpoint Agent.bat"
@"
@echo off
echo TechVina Endpoint Agent Running - %DATE% %TIME%
timeout /t 600 > nul
"@ | Out-File $AgentBat -Encoding ASCII

$existingSvc = Get-Service -Name "TVEndpointAgent" -ErrorAction SilentlyContinue
if (-not $existingSvc) {
    # Unquoted path with space in "TV Endpoint Agent.bat"
    sc.exe create "TVEndpointAgent" binPath= "C:\Windows\System32\cmd.exe /c C:\LabServices\TVEndpointAgent\TV Endpoint Agent.bat" start= auto DisplayName= "TechVina Endpoint Agent" | Out-Null
    Write-Host "[+] Created service: TVEndpointAgent (unquoted path)" -ForegroundColor Red
}

# Make LabServices writable
$LabSvcACL = Get-Acl "C:\LabServices\TVEndpointAgent"
$LabSvcRule = New-Object System.Security.AccessControl.FileSystemAccessRule("BUILTIN\Users", "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
$LabSvcACL.SetAccessRule($LabSvcRule)
Set-Acl "C:\LabServices\TVEndpointAgent" $LabSvcACL
Write-Host "[!] C:\LabServices\TVEndpointAgent writable by Users" -ForegroundColor Red

# ------------------------------
# 6. SCHEDULED TASK (PRIVESC VIA WRITABLE SCRIPT)
# ------------------------------

Write-Host "[+] Creating scheduled task for privilege escalation..." -ForegroundColor Yellow

# Create a script in a writable location that runs as admin.leduc
$TaskScript = "C:\Temp\maintenance.ps1"
@"
# TechVina Daily Maintenance Script
# Runs every 10 minutes under admin.leduc context
# Checks system health and reports

`$Hostname = `$env:COMPUTERNAME
`$Date = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
`$FreeSpace = (Get-PSDrive C).Free / 1GB

Write-Output "`$Date - `$Hostname - Free space: `$([math]::Round(`$FreeSpace,2)) GB" | `
    Out-File "C:\Temp\maintenance_log.txt" -Append
"@ | Out-File $TaskScript -Encoding UTF8

# Make C:\Temp writable by Users
$TempACL = Get-Acl "C:\Temp"
$TempRule = New-Object System.Security.AccessControl.FileSystemAccessRule("BUILTIN\Users", "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
$TempACL.SetAccessRule($TempRule)
Set-Acl "C:\Temp" $TempACL

# Register task running as admin.leduc (Domain Admin!)
$TaskAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File C:\Temp\maintenance.ps1"
$TaskTrigger = New-ScheduledTaskTrigger -RepetitionInterval (New-TimeSpan -Minutes 10) -Once -At (Get-Date)
$TaskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

try {
    $existingTask = Get-ScheduledTask -TaskName "TechVinaMaintenanceWS" -ErrorAction SilentlyContinue
    if (-not $existingTask) {
        Register-ScheduledTask -TaskName "TechVinaMaintenanceWS" -Action $TaskAction -Trigger $TaskTrigger `
            -Settings $TaskSettings -User "$NetBIOS\admin.leduc" -Password "P@ssw0rd2026!" -RunLevel Highest
        Write-Host "[+] Created: TechVinaMaintenanceWS (runs as admin.leduc, script writable!)"
        Write-Host "[!] PrivEsc: Replace C:\Temp\maintenance.ps1 -> runs as Domain Admin" -ForegroundColor Red
    }
} catch {
    Write-Host "[!] Could not create TechVinaMaintenanceWS task." -ForegroundColor Yellow
    Write-Host $_.Exception.Message -ForegroundColor Yellow
}

# ------------------------------
# 7. INTERN USER PROFILE - DESKTOP FILES
# ------------------------------

Write-Host "[+] Creating intern.nguyenminh profile files..." -ForegroundColor Yellow

$InternDesktop = "C:\Users\intern.nguyenminh\Desktop"
$InternDocs = "C:\Users\intern.nguyenminh\Documents"

@"
Chao ban!

Day la may tinh lam viec cua ban trong thoi gian thuc tap tai TechVina Corp.
Email: intern.nguyenminh@techvina.local
Extension: 3099

Lien he IT support:
- admin.leduc (IT Admin) - ext 3001
- dev.phamhoang (Dev Lead) - ext 3002

Wifi: TechVina-Office / TechVina2024!

Chuc ban lam viec vui ve!
"@ | Out-File "$InternDesktop\Welcome.txt" -Encoding UTF8

@"
THUC TAP SINH - CONG VIEC HANG NGAY

1. Kiem tra email moi sang
2. Cap nhat ticket tren he thong
3. Ho tro test ung dung web (http://TV-SRV01)
4. Bao cao hang tuan cho dev.phamhoang

Tai khoan truy cap:
- Domain: techvina.local
- May ban: TV-WS01
- May server de test: TV-SRV01

Ghi chu:
- Khong duoc cai dat phan mem tu do
- Khong duoc truy cap may chu DC
- Moi van de lien he IT
"@ | Out-File "$InternDocs\CongViec.txt" -Encoding UTF8

# ------------------------------
# 8. ADMIN.LEDUC PROFILE - CREDENTIAL ARTIFACTS
# ------------------------------

Write-Host "[+] Creating admin.leduc profile with credential artifacts..." -ForegroundColor Yellow

$AdminDesktop = "C:\Users\admin.leduc\Desktop"
$AdminDocs = "C:\Users\admin.leduc\Documents"
$AdminProjects = "C:\Users\admin.leduc\Documents\Projects"

# Sticky notes / personal notes
@"
Admin Notes - Le Thanh Duc
==========================

VPN Account:
- vpn.techvina.local
- admin.leduc / P@ssw0rd2026!

Firewall:
- 10.10.10.1 / admin / Fw@dmin2024

Switch Management:
- 10.10.10.2 / admin / Sw1tch!

WiFi Controller:
- wifi.techvina.local / admin / TechVina2024!

DSRM:
- P@ssw0rd!2024

TODO:
- Doi mat khau svc_backup (da qua han)
- Kiem tra lai GPO Deploy
- Setup LAPS cho workstation
"@ | Out-File "$AdminDesktop\Notes.txt" -Encoding UTF8

# KeePass database (dummy but realistic filename)
$KeePassBytes = New-Object byte[] 2048
(New-Object Random).NextBytes($KeePassBytes)
# Add KeePass magic bytes
$KeePassMagic = [byte[]](0x03, 0xD9, 0xA2, 0x9A, 0x67, 0xFB, 0x4B, 0xB5)
[System.Array]::Copy($KeePassMagic, 0, $KeePassBytes, 0, $KeePassMagic.Length)
[System.IO.File]::WriteAllBytes("$AdminDocs\passwords.kdbx", $KeePassBytes)
Write-Host "[+] Created fake KeePass DB: passwords.kdbx (master password: P@ssw0rd2026!)"

# RDP connection files
@"
screen mode id:i:2
use multimon:i:0
session bpp:i:32
full address:s:TV-SRV01
audiomode:i:0
username:s:TECHVINA\admin.leduc
domain:s:TECHVINA
"@ | Out-File "$AdminDesktop\TV-SRV01.rdp" -Encoding UTF8

@"
screen mode id:i:2
full address:s:TV-DC01
username:s:TECHVINA\admin.leduc
domain:s:TECHVINA
"@ | Out-File "$AdminDesktop\TV-DC01.rdp" -Encoding UTF8

# PowerShell history
$PSHistoryDir = "C:\Users\admin.leduc\AppData\Roaming\Microsoft\Windows\PowerShell\PSReadLine"
if (-not (Test-Path $PSHistoryDir)) {
    New-Item -ItemType Directory -Path $PSHistoryDir -Force | Out-Null
}

@"
Get-ADUser -Filter * | Select Name, SamAccountName
Set-ADAccountPassword -Identity svc_backup -Reset -NewPassword (ConvertTo-SecureString "Backup2024" -AsPlainText -Force)
Enter-PSSession -ComputerName TV-SRV01 -Credential (Get-Credential)
Invoke-Command -ComputerName TV-DC01 -ScriptBlock { Get-ADDomain }
net user admin.leduc P@ssw0rd2026! /domain
Get-ADGroupMember "Domain Admins"
Get-ADComputer -Filter * | Select Name, DNSHostName
Test-NetConnection TV-SRV01 -Port 1433
Invoke-WebRequest http://TV-SRV01 -UseBasicParsing
Get-ADUser -Identity svc_monitor -Properties ServicePrincipalName
"@ | Out-File "$PSHistoryDir\ConsoleHost_history.txt" -Encoding UTF8
Write-Host "[!] Created PowerShell history for admin.leduc (contains passwords!)" -ForegroundColor Red

# FileZilla saved credentials
@"
<?xml version="1.0" encoding="UTF-8"?>
<FileZilla3 version="3.60.1" platform="windows">
  <RecentServers>
    <Server>
      <Host>TV-SRV01</Host>
      <Port>22</Port>
      <Protocol>1</Protocol>
      <Type>0</Type>
      <User>admin.leduc</User>
      <Pass encoding="base64">UEBzc3cwcmQ=</Pass>
      <Account/>
    </Server>
    <Server>
      <Host>10.10.10.10</Host>
      <Port>22</Port>
      <Protocol>1</Protocol>
      <Type>0</Type>
      <User>root</User>
      <Pass encoding="base64">dG9vcg==</Pass>
      <Account/>
    </Server>
  </RecentServers>
</FileZilla3>
"@ | Out-File "C:\Users\admin.leduc\AppData\Roaming\FileZilla\recentservers.xml" -Encoding UTF8
Write-Host "[+] Created FileZilla saved sessions for admin.leduc"

# Project files with credentials
@"
# Internal API Development Notes
# Author: admin.leduc
# Date: 2024-02-15

## Database Connection
Server: TV-SRV01
Database: TechVinaDB
User: svc_sql
Password: SqlP@ss2024

## Test Accounts
- admin.leduc / P@ssw0rd2026! (Domain Admin - for testing only!)
- dev.phamhoang / devpass123

## Deployment
Service account: svc_deploy / D3ploy!
Target: TV-SRV01

## ADCS
CA: TECHVINA-CA
Web Enrollment: http://TV-DC01/certsrv
Template: TechVinaWebServer (for web SSL)
"@ | Out-File "$AdminProjects\dev_notes.md" -Encoding UTF8

# ------------------------------
# 9. SIMULATE BROWSER SAVED PASSWORDS
# ------------------------------

Write-Host "[+] Creating simulated browser credential artifacts..." -ForegroundColor Yellow

# Chrome Login Data simulation (just text file with hints, not real SQLite)
$ChromeDir = "C:\Users\admin.leduc\AppData\Local\Google\Chrome\User Data\Default"
if (-not (Test-Path $ChromeDir)) {
    New-Item -ItemType Directory -Path $ChromeDir -Force | Out-Null
}

@"
Browser Password Export (simulated)
===================================
This file simulates exported browser passwords.
In a real scenario, use tools like:
- SharpChrome
- mimikatz dpapi::chrome
- LaZagne

Saved Logins (cleartext for lab):
URL: http://TV-SRV01
Username: admin.leduc
Password: P@ssw0rd2026!

URL: http://TV-DC01/certsrv
Username: admin.leduc
Password: P@ssw0rd2026!

URL: https://vpn.techvina.local
Username: admin.leduc
Password: P@ssw0rd2026!

URL: https://mail.techvina.local
Username: admin.leduc@techvina.local
Password: P@ssw0rd2026!
"@ | Out-File "$ChromeDir\saved_passwords.txt" -Encoding UTF8

# Edge/IE saved passwords in Credential Manager simulation
@"
Windows Credential Manager Export (simulated)
=============================================

Target: TERMSRV/TV-SRV01
Type: Domain Password
User: TECHVINA\admin.leduc
Password: P@ssw0rd2026!

Target: TERMSRV/TV-DC01
Type: Domain Password
User: TECHVINA\admin.leduc
Password: P@ssw0rd2026!

In real scenario, use:
- cmdkey /list
- mimikatz vault::cred
- SharpDPAPI
"@ | Out-File "C:\Users\admin.leduc\AppData\Local\Microsoft\Credentials\credential_export.txt" -Encoding UTF8

# ------------------------------
# 10. WIFI PASSWORD (RETRIEVABLE)
# ------------------------------

Write-Host "[+] Creating WiFi profile..." -ForegroundColor Yellow

try {
    # Create WiFi profile XML
    $WifiXML = @"
<?xml version="1.0"?>
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
    <name>TechVina-Office</name>
    <SSIDConfig>
        <SSID>
            <hex>5465636856696E612D4F6666696365</hex>
            <name>TechVina-Office</name>
        </SSID>
    </SSIDConfig>
    <connectionType>ESS</connectionType>
    <connectionMode>auto</connectionMode>
    <MSM>
        <security>
            <authEncryption>
                <authentication>WPA2PSK</authentication>
                <encryption>AES</encryption>
                <useOneX>false</useOneX>
            </authEncryption>
            <sharedKey>
                <keyType>passPhrase</keyType>
                <protected>false</protected>
                <keyMaterial>TechVina2024!</keyMaterial>
            </sharedKey>
        </security>
    </MSM>
</WLANProfile>
"@

    $WifiXMLPath = "$SetupFolder\wifi_profile.xml"
    $WifiXML | Out-File $WifiXMLPath -Encoding UTF8
    netsh wlan add profile filename="$WifiXMLPath" 2>&1 | Out-Null
    Write-Host "[+] WiFi profile added: TechVina-Office / TechVina2024!"
    Write-Host "[!] Retrievable with: netsh wlan show profiles TechVina-Office key=clear" -ForegroundColor Red
} catch {
    Write-Host "[=] WiFi profile creation skipped (no WLAN adapter)" -ForegroundColor Yellow
}

# ------------------------------
# 11. AUTO-LOGON CREDENTIALS IN REGISTRY
# ------------------------------

Write-Host "[+] Setting auto-logon credentials in registry..." -ForegroundColor Yellow

try {
    $AutoLogonPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
    Set-ItemProperty -Path $AutoLogonPath -Name "AutoAdminLogon" -Value "1"
    Set-ItemProperty -Path $AutoLogonPath -Name "DefaultUserName" -Value "intern.nguyenminh"
    Set-ItemProperty -Path $AutoLogonPath -Name "DefaultPassword" -Value "intern123"
    Set-ItemProperty -Path $AutoLogonPath -Name "DefaultDomainName" -Value $NetBIOS

    Write-Host "[!] Auto-logon configured: intern.nguyenminh / intern123" -ForegroundColor Red
    Write-Host "[!] Password visible in: HKLM\\...\\Winlogon\\DefaultPassword" -ForegroundColor Red
} catch {
    Write-Host "[!] Could not set auto-logon registry keys" -ForegroundColor Yellow
}

# ------------------------------
# 12. SIMULATE CACHED CREDENTIALS (admin.leduc)
# ------------------------------

Write-Host "[+] Simulating cached domain credentials..." -ForegroundColor Yellow

# We need admin.leduc to have logged in at least once
# Create a script to do this
@"
# Run this script ONCE to simulate admin.leduc login on WS01
# This creates cached credentials and DPAPI blobs

`$username = "$NetBIOS\admin.leduc"
`$password = ConvertTo-SecureString "P@ssw0rd2026!" -AsPlainText -Force
`$credential = New-Object System.Management.Automation.PSCredential(`$username, `$password)

# Simulate login via task
`$action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c echo Admin logged in & timeout /t 5"
`$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1)
Register-ScheduledTask -TaskName "SimLogin_AdminLeDuc" -Action `$action -Trigger `$trigger ``
    -User "$NetBIOS\admin.leduc" -Password "P@ssw0rd2026!" -RunLevel Highest

# Also store RDP credential
cmdkey /add:TV-SRV01 /user:$NetBIOS\admin.leduc /pass:P@ssw0rd2026!
cmdkey /add:TV-DC01 /user:$NetBIOS\admin.leduc /pass:P@ssw0rd2026!

Write-Host "[+] admin.leduc credentials cached on WS01"
Write-Host "[+] Run 'cmdkey /list' to verify stored credentials"
Write-Host "[+] DPAPI blobs will be created in admin.leduc's profile"
"@ | Out-File "$SetupFolder\simulate_admin_login.ps1" -Encoding UTF8

Write-Host "[!] Run simulate_admin_login.ps1 to cache admin.leduc credentials" -ForegroundColor Yellow

# Actually store some credentials now via cmdkey (as current user)
try {
    cmdkey /add:TV-SRV01 /user:$NetBIOS\admin.leduc /pass:P@ssw0rd2026! 2>&1 | Out-Null
    cmdkey /add:TV-DC01 /user:$NetBIOS\admin.leduc /pass:P@ssw0rd2026! 2>&1 | Out-Null
    Write-Host "[+] Stored credentials via cmdkey for admin.leduc"
} catch {
    Write-Host "[=] cmdkey credential storage may need interactive session" -ForegroundColor Yellow
}

# Set cached logon count high to ensure creds are cached
try {
    $CachePath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
    Set-ItemProperty -Path $CachePath -Name "CachedLogonsCount" -Value "50"
    Write-Host "[+] CachedLogonsCount set to 50 (ensures domain creds are cached)"
} catch {
    Write-Host "[=] Could not set CachedLogonsCount" -ForegroundColor Yellow
}

# ------------------------------
# 13. DISABLE DEFENDER
# ------------------------------

Write-Host "[+] Disabling Windows Defender..." -ForegroundColor Yellow

try {
    Set-MpPreference -DisableRealtimeMonitoring $true -ErrorAction SilentlyContinue
    Set-MpPreference -DisableBehaviorMonitoring $true -ErrorAction SilentlyContinue
    Set-MpPreference -DisableBlockAtFirstSeen $true -ErrorAction SilentlyContinue
    Set-MpPreference -DisableIOAVProtection $true -ErrorAction SilentlyContinue
    Set-MpPreference -DisableScriptScanning $true -ErrorAction SilentlyContinue

    $DefenderRegPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"
    if (-not (Test-Path $DefenderRegPath)) {
        New-Item -Path $DefenderRegPath -Force | Out-Null
    }
    Set-ItemProperty -Path $DefenderRegPath -Name "DisableAntiSpyware" -Value 1 -Type DWord

    $RTPRegPath = "$DefenderRegPath\Real-Time Protection"
    if (-not (Test-Path $RTPRegPath)) {
        New-Item -Path $RTPRegPath -Force | Out-Null
    }
    Set-ItemProperty -Path $RTPRegPath -Name "DisableRealtimeMonitoring" -Value 1 -Type DWord

    Write-Host "[+] Windows Defender disabled."
} catch {
    Write-Host "[!] Could not fully disable Defender." -ForegroundColor Yellow
}

# ------------------------------
# 14. ENABLE WINRM
# ------------------------------

Write-Host "[+] Enabling WinRM..." -ForegroundColor Yellow

try {
    Enable-PSRemoting -Force -SkipNetworkProfileCheck
    Set-Service WinRM -StartupType Automatic
    Start-Service WinRM
    Write-Host "[+] WinRM enabled."
} catch {
    Write-Host "[!] WinRM may need manual configuration on Windows 10." -ForegroundColor Yellow
}

# ------------------------------
# 15. ENABLE RDP
# ------------------------------

Write-Host "[+] Enabling RDP..." -ForegroundColor Yellow

Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0
Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue

# Allow intern.nguyenminh RDP
try {
    Add-LocalGroupMember -Group "Remote Desktop Users" -Member "$NetBIOS\intern.nguyenminh" -ErrorAction SilentlyContinue
    Write-Host "[+] intern.nguyenminh added to Remote Desktop Users"
} catch {
    Write-Host "[=] intern.nguyenminh may already be in RDP group" -ForegroundColor Yellow
}

# ------------------------------
# 16. FIREWALL - ALLOW ALL FOR LAB
# ------------------------------

Write-Host "[+] Configuring firewall..." -ForegroundColor Yellow

New-NetFirewallRule -DisplayName "CyberRange2-AllowAll" -Direction Inbound -Action Allow -Profile Any -ErrorAction SilentlyContinue | Out-Null

# ------------------------------
# 17. LOCAL SAM - PASSWORD REUSE SCENARIO
# ------------------------------

Write-Host "[+] Setting up local admin password reuse..." -ForegroundColor Yellow

try {
    # Set local Administrator password (same as admin.leduc - password reuse!)
    $LocalAdminPass = ConvertTo-SecureString "P@ssw0rd2026!" -AsPlainText -Force
    Set-LocalUser -Name "Administrator" -Password $LocalAdminPass
    Enable-LocalUser -Name "Administrator"
    Write-Host "[!] Local Administrator password set to P@ssw0rd2026! (reuse with admin.leduc)" -ForegroundColor Red
} catch {
    Write-Host "[!] Could not set local Administrator password." -ForegroundColor Yellow
}

# ------------------------------
# 18. VERIFICATION OUTPUT
# ------------------------------

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " TECHVINA WS01 BUILD SUMMARY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "[+] Hostname: $env:COMPUTERNAME"
Write-Host "[+] Domain: $CurrentDomain"
Write-Host ""
Write-Host "[Initial Access]"
Write-Host "intern.nguyenminh / intern123 (auto-logon)"
Write-Host ""
Write-Host "[Credential Artifacts]"
Write-Host "admin.leduc profile files:"
Write-Host "  - Desktop\Notes.txt (passwords!)"
Write-Host "  - Desktop\TV-SRV01.rdp / TV-DC01.rdp"
Write-Host "  - Documents\passwords.kdbx (KeePass)"
Write-Host "  - Documents\Projects\dev_notes.md (multiple passwords)"
Write-Host "  - AppData\Roaming\FileZilla\recentservers.xml"
Write-Host "  - AppData\...PSReadLine\ConsoleHost_history.txt"
Write-Host "  - AppData\...\saved_passwords.txt (browser sim)"
Write-Host ""
Write-Host "[Local PrivEsc Vectors]"
Write-Host "1. Scheduled Task: TechVinaMaintenanceWS"
Write-Host "   -> Runs as admin.leduc (DA)"
Write-Host "   -> Script: C:\Temp\maintenance.ps1 (WRITABLE!)"
Write-Host "2. Service: TVEndpointAgent (unquoted path)"
Write-Host "   -> C:\LabServices\TVEndpointAgent (writable)"
Write-Host "3. C:\Tools in PATH (DLL hijacking)"
Write-Host "4. Local Admin: P@ssw0rd2026! (password reuse)"
Write-Host ""
Write-Host "[Registry]"
Write-Host "Auto-logon: HKLM\...\Winlogon (cleartext password)"
Write-Host "CachedLogonsCount: 50"
Write-Host ""
Write-Host "[WiFi]"
Write-Host "TechVina-Office / TechVina2024!"
Write-Host ""
Write-Host "[IMPORTANT]"
Write-Host "Run simulate_admin_login.ps1 as admin for cached creds!"
Write-Host "Path: $SetupFolder\simulate_admin_login.ps1"
Write-Host "============================================================" -ForegroundColor Cyan

Write-Host "[+] WS01 Build completed. Take snapshot." -ForegroundColor Green
Write-Host "[+] Lab is ready for Red Team exercise!" -ForegroundColor Green

Stop-Transcript
