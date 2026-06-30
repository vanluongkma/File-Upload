# ============================================================
# 99-Clear-AllLogs.ps1
# CyberRange 2 — Cleanup Script
#
# Script này được dùng để xóa toàn bộ Event Logs, Command History
# và các file tạm sau khi cài đặt xong môi trường Lab.
# Giúp bài Lab sạch sẽ trước khi tạo Snapshot.
# ============================================================

$ErrorActionPreference = "SilentlyContinue"

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " CYBERRANGE 2 - SYSTEM CLEANUP & LOG CLEARING" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# 1. Clear Windows Event Logs
Write-Host "[+] Clearing all Windows Event Logs (This may take a minute)..." -ForegroundColor Yellow
$logs = wevtutil el
$clearedCount = 0
foreach ($log in $logs) {
    # Attempt to clear the log
    $result = wevtutil cl $log
    if ($?) {
        $clearedCount++
    }
}
Write-Host "    -> Cleared $clearedCount event logs." -ForegroundColor Green

# 2. Clear PowerShell History
Write-Host "[+] Clearing PowerShell Command History..." -ForegroundColor Yellow
Remove-Item (Get-PSReadLineOption).HistorySavePath -Force
Clear-History
Write-Host "    -> History cleared." -ForegroundColor Green

# 3. Clear Temp Files (Optional but recommended)
Write-Host "[+] Cleaning up Temp directories..." -ForegroundColor Yellow
$TempFolders = @(
    "C:\Windows\Temp\*",
    "C:\Users\*\AppData\Local\Temp\*",
    "C:\Temp\*"
)
foreach ($folder in $TempFolders) {
    Remove-Item -Path $folder -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host "    -> Temp files deleted." -ForegroundColor Green

# 4. Flush DNS
Write-Host "[+] Flushing DNS Cache..." -ForegroundColor Yellow
ipconfig /flushdns | Out-Null
Write-Host "    -> DNS flushed." -ForegroundColor Green

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "[+] CLEANUP COMPLETED! System is ready for Snapshot." -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan
