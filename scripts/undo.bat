@echo off
setlocal EnableExtensions
chcp 65001 >nul
title Rollback - network optimizer and OptiForge

echo ==============================================================
echo    ROLLBACK  -  network optimizer + optimize.bat changes
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

call :NET_UNDO
echo.

echo ==================== OPTIMIZE.BAT ROLLBACK ====================
call "%~dp0optimize.bat" -undo
echo ===============================================================
endlocal
exit /b 0


:NET_UNDO
set "NETSTATE=%~dp0net_state.txt"
if not exist "%NETSTATE%" (
    echo [i] net_state.txt not found - network optimizer was not run, skipping network rollback.
    goto :eof
)

echo [..] Restoring registry keys saved by network_optimizer.bat...
reg import "%~dp0net_backup_interfaces.reg" >nul 2>&1
if %errorlevel%==0 (echo [OK] Interfaces restored) else (echo [!] Interfaces backup not imported)
reg import "%~dp0net_backup_systemprofile.reg" >nul 2>&1
if %errorlevel%==0 (echo [OK] SystemProfile restored) else (echo [!] SystemProfile backup not imported)
reg import "%~dp0net_backup_psched.reg" >nul 2>&1
if %errorlevel%==0 (echo [OK] Psched restored) else (echo [i] Psched backup absent - key did not exist before, values removed below)
echo.

echo [..] Removing values that did not exist before, restoring adapter power settings...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-Content -LiteralPath '%NETSTATE%' | ForEach-Object { $f = $_ -split ';'; if ($f[0] -eq 'Reg' -and $f[3] -eq '0') { if (Get-ItemProperty -LiteralPath $f[1] -Name $f[2] -ErrorAction SilentlyContinue) { Remove-ItemProperty -LiteralPath $f[1] -Name $f[2] -Force; Write-Host ('[OK] Removed ' + $f[2]) -ForegroundColor Green } } elseif ($f[0] -eq 'Pwr' -and ($f[2] -eq 'Enabled' -or $f[2] -eq 'Disabled')) { try { Set-NetAdapterPowerManagement -Name $f[1] -AllowComputerToTurnOffDevice $f[2] -ErrorAction Stop; Write-Host ('[OK] Power management restored: ' + $f[1]) -ForegroundColor Green } catch { Write-Host ('[!] ' + $f[1] + ': ' + $_.Exception.Message) -ForegroundColor Yellow } } }"
echo.

echo [..] Setting TCP globals to Windows defaults...
netsh int tcp set global autotuninglevel=normal >nul 2>&1
netsh int tcp set global rss=enabled >nul 2>&1
netsh int tcp set global chimney=disabled >nul 2>&1
echo [OK] autotuninglevel=normal, rss=enabled, chimney=disabled
echo.

del /q "%NETSTATE%" >nul 2>&1
echo [OK] Network rollback done. net_state.txt removed, so the next network_optimizer.bat run saves a fresh snapshot.
goto :eof
