@echo off
setlocal EnableExtensions
chcp 65001 >nul
title Network Latency Optimizer

echo ==============================================================
echo    NETWORK LATENCY OPTIMIZER  -  Windows 10/11 gaming ping fix
echo    Sources: ChrisTitusTech/winutil, Sophia Script, net tweaks
echo ==============================================================
echo.

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [i] Administrator rights required. Relaunching elevated...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
echo [OK] Administrator rights confirmed
echo.

echo [..] Creating system restore point...
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' -Name SystemRestorePointCreationFrequency -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue; Enable-ComputerRestore -Drive $env:SystemDrive -ErrorAction Stop; Checkpoint-Computer -Description 'Network Latency Optimizer' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop; exit 0 } catch { Write-Host ('[!] Restore point failed: ' + $_.Exception.Message) -ForegroundColor Yellow; exit 1 }"
if %errorlevel%==0 (echo [OK] Restore point created) else (echo [!] Restore point NOT created - check that System Restore is enabled)
echo.

echo [..] Saving original network settings to script folder...
if exist "%~dp0net_state.txt" goto :backup_exists
reg export "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces" "%~dp0net_backup_interfaces.reg" /y >nul 2>&1
reg export "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" "%~dp0net_backup_systemprofile.reg" /y >nul 2>&1
reg export "HKLM\SOFTWARE\Policies\Microsoft\Windows\Psched" "%~dp0net_backup_psched.reg" /y >nul 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -Command "$out = @(); $ups = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up'; foreach ($x in $ups) { $p = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\{' + $x.InterfaceGuid + '}'; foreach ($n in 'TcpAckFrequency','TCPNoDelay') { $e = $null -ne (Get-ItemProperty -LiteralPath $p -Name $n -ErrorAction SilentlyContinue); $out += ('Reg;' + $p + ';' + $n + ';' + [int]$e) }; $pw = (Get-NetAdapterPowerManagement -Name $x.Name -ErrorAction SilentlyContinue).AllowComputerToTurnOffDevice; $out += ('Pwr;' + $x.Name + ';' + $pw) }; $pp = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Psched'; $e = $null -ne (Get-ItemProperty -LiteralPath $pp -Name 'NonBestEffortLimit' -ErrorAction SilentlyContinue); $out += ('Reg;' + $pp + ';NonBestEffortLimit;' + [int]$e); Set-Content -LiteralPath '%~dp0net_state.txt' -Value $out -Encoding UTF8"
echo [OK] Saved: net_state.txt and net_backup_*.reg
goto :backup_done
:backup_exists
echo [!] Original settings were already saved by an earlier run - keeping them, so undo returns the true originals.
echo [!] Run undo.bat first if you want a fresh snapshot.
:backup_done
echo.

echo [1/6] Disabling Nagle algorithm - TcpAckFrequency=1, TCPNoDelay=1...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$a = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up'; if ($a) { foreach ($x in $a) { $p = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\{' + $x.InterfaceGuid + '}'; New-ItemProperty -Path $p -Name 'TcpAckFrequency' -Value 1 -PropertyType DWord -Force | Out-Null; New-ItemProperty -Path $p -Name 'TCPNoDelay' -Value 1 -PropertyType DWord -Force | Out-Null; Write-Host ('[OK] Nagle disabled: ' + $x.Name + ' [' + $x.InterfaceGuid + ']') -ForegroundColor Green } } else { Write-Host '[!] No active network adapters found' -ForegroundColor Yellow }"
echo.

echo [2/6] Disabling network throttling - NetworkThrottlingIndex=0xffffffff...
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v NetworkThrottlingIndex /t REG_DWORD /d 0xffffffff /f >nul 2>&1
if %errorlevel%==0 (echo [OK] NetworkThrottlingIndex = 0xffffffff) else (echo [!] Failed to set NetworkThrottlingIndex)
echo.

echo [3/6] Removing QoS 20%% bandwidth reserve - NonBestEffortLimit=0...
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Psched" /v NonBestEffortLimit /t REG_DWORD /d 0 /f >nul 2>&1
if %errorlevel%==0 (echo [OK] NonBestEffortLimit = 0 - QoS reserve removed) else (echo [!] Failed to set NonBestEffortLimit)
echo.

echo [4/6] Applying TCP optimizations via netsh...
netsh int tcp set global autotuninglevel=normal >nul 2>&1
if %errorlevel%==0 (echo [OK] autotuninglevel = normal) else (echo [!] autotuninglevel was not applied)
netsh int tcp set global rss=enabled >nul 2>&1
if %errorlevel%==0 (echo [OK] rss = enabled) else (echo [!] rss was not applied)
netsh int tcp set global chimney=enabled >nul 2>&1
if %errorlevel%==0 (echo [OK] chimney = enabled) else (echo [!] chimney not supported on this system - skipped)
echo.

echo [5/6] Flushing DNS cache and ARP table...
ipconfig /flushdns >nul 2>&1
if %errorlevel%==0 (echo [OK] DNS cache flushed) else (echo [!] DNS flush failed)
arp -d * >nul 2>&1
if %errorlevel%==0 (echo [OK] ARP table cleared) else (echo [!] ARP clear failed)
echo.

echo [6/6] Disabling power saving on network adapters...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up' | ForEach-Object { try { Disable-NetAdapterPowerManagement -Name $_.Name -NoRestart -ErrorAction Stop; Write-Host ('[OK] Power management disabled: ' + $_.Name) -ForegroundColor Green } catch { Write-Host ('[!] ' + $_.Name + ': ' + $_.Exception.Message) -ForegroundColor Yellow } }"
echo.

echo ==================== TCP RESULT ====================
netsh int tcp show global
echo ===================================================
echo.
echo [i] Rollback: run undo.bat (restores these settings and the optimize.bat changes)
echo.
echo Сетевые настройки оптимизированы. Рекомендуется перезагрузка ПК.
echo.
pause
endlocal
exit /b 0
