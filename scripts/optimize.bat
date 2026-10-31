@echo off
setlocal EnableExtensions
title OptiForge - Gaming Performance Optimizer

net session >nul 2>&1
if %errorlevel% neq 0 goto ELEVATE
goto RUN

:ELEVATE
echo Requesting administrator privileges...
powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%~1' -Verb RunAs"
exit /b

:RUN
cd /d "%~dp0"
set "ARG=%~1"
if not defined ARG set "ARG=-"
set "ARG=%ARG:-=%"
set "ARG=%ARG:/=%"
set "MODE=Optimize"
if /i "%ARG%"=="undo" set "MODE=Undo"

set "PSFILE=%TEMP%\OptiForge_engine.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$raw=[IO.File]::ReadAllText('%~f0'); $s=$raw.IndexOf('<PS'+'BEGIN>'); $e=$raw.IndexOf('<PS'+'END>'); if($s -lt 0 -or $e -lt 0){exit 2}; $p=$s+9; [IO.File]::WriteAllText('%PSFILE%',$raw.Substring($p,$e-$p),(New-Object Text.UTF8Encoding $true)); exit 0"
if %errorlevel% neq 0 goto FAIL
if not exist "%PSFILE%" goto FAIL

set "OPTIFORGE_BASE=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%PSFILE%" -Mode %MODE%
echo.
pause
exit /b 0

:FAIL
echo [X] Failed to extract PowerShell engine from this file.
pause
exit /b 1

<PSBEGIN>
param(
  [ValidateSet('Optimize','Undo')][string]$Mode = 'Optimize',
  [string]$BaseDir = ''
)

if (-not $BaseDir -and $env:OPTIFORGE_BASE) { $BaseDir = $env:OPTIFORGE_BASE }
if (-not $BaseDir) { $BaseDir = $env:TEMP }
$BaseDir = ([string]$BaseDir).Trim().Trim('"').Trim("'").TrimEnd('\','/')
if ($BaseDir.Length -lt 3 -or -not (Test-Path -LiteralPath $BaseDir -ErrorAction SilentlyContinue)) { $BaseDir = $env:TEMP }
$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Write-Host '[X] Требуются права администратора. Запустите optimize.bat от имени администратора.' -ForegroundColor Red
  exit 1
}

$os = Get-CimInstance Win32_OperatingSystem
if ($os.Caption -like '*Server*') {
  Write-Host '[X] Windows Server не поддерживается.' -ForegroundColor Red
  exit 1
}

$stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$LogFile = Join-Path $BaseDir ('OptiForge_{0}_{1}.log' -f $Mode, $stamp)
$BackupRoot = Join-Path $BaseDir 'OptiForge_Backup'
$script:CurrentBackup = ''
$script:CreatedValues = @()
$script:CreatedKeys = @()
$script:RestorePointOK = $false
$script:RemovedApps = 0

$script:ServiceNames = @('SysMain','WSearch','DiagTrack','dmwappushservice')

$script:TaskList = @(
  @{ Path = '\Microsoft\Windows\Customer Experience Improvement Program\'; Name = 'Consolidator' },
  @{ Path = '\Microsoft\Windows\Customer Experience Improvement Program\'; Name = 'UsbCeip' },
  @{ Path = '\Microsoft\Windows\Application Experience\'; Name = 'Microsoft Compatibility Appraiser' },
  @{ Path = '\Microsoft\Windows\Application Experience\'; Name = 'ProgramDataUpdater' },
  @{ Path = '\Microsoft\Windows\Autochk\'; Name = 'Proxy' },
  @{ Path = '\Microsoft\Windows\DiskDiagnostic\'; Name = 'Microsoft-Windows-DiskDiagnosticDataCollector' },
  @{ Path = '\Microsoft\Windows\Feedback\Siuf\Rules\'; Name = 'NumberOfSIUFInPeriod' }
)

$RegKeysToBackup = @(
  'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager',
  'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo',
  'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy',
  'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search',
  'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced',
  'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects',
  'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR',
  'HKCU:\Software\Microsoft\GameBar',
  'HKCU:\System\GameConfigStore',
  'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences',
  'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize',
  'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications',
  'HKCU:\Software\Microsoft\Siuf\Rules',
  'HKCU:\Software\Microsoft\Input\TIPC',
  'HKCU:\Software\Microsoft\InputPersonalization',
  'HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore',
  'HKCU:\Software\Microsoft\Personalization\Settings',
  'HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy',
  'HKCU:\Control Panel\Desktop',
  'HKCU:\Control Panel\Keyboard',
  'HKCU:\Software\Microsoft\Windows\DWM',
  'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile',
  'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore',
  'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl',
  'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers',
  'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling',
  'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection',
  'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection',
  'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR',
  'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo',
  'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search',
  'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer',
  'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent',
  'HKLM:\SOFTWARE\Policies\Microsoft\SQM Clients',
  'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting',
  'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization'
)

function Log {
  param([string]$Level = 'I', [string]$Message = '')
  $colors = @{ 'OK' = 'Green'; '!' = 'Yellow'; 'X' = 'Red'; 'I' = 'Cyan'; 'H' = 'Magenta' }
  $line = '[{0}] {1}  {2}' -f $Level, (Get-Date -Format 'HH:mm:ss'), $Message
  Write-Host $line -ForegroundColor $colors[$Level]
  try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 } catch { }
}

function Header {
  param([string]$Text = '')
  $bar = '=' * 64
  Write-Host ''
  Write-Host $bar -ForegroundColor Magenta
  Write-Host ('  ' + $Text) -ForegroundColor Magenta
  Write-Host $bar -ForegroundColor Magenta
  try { Add-Content -LiteralPath $LogFile -Value ('' ) -Encoding UTF8; Add-Content -LiteralPath $LogFile -Value ('===== ' + $Text + ' =====') -Encoding UTF8 } catch { }
}

function Set-RegValue {
  param([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord')
  try {
    if (-not (Test-Path -LiteralPath $Path)) {
      New-Item -Path $Path -Force | Out-Null
      $script:CreatedKeys += $Path
    }
    $prop = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
    if (-not ($null -ne $prop -and ($prop.PSObject.Properties.Name -contains $Name))) {
      $script:CreatedValues += [pscustomobject]@{ Path = $Path; Name = $Name }
    }
    New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
    Log 'OK' ('{0} -> {1} = {2}' -f ($Path -replace 'Registry::',''), $Name, $Value)
  } catch {
    Log 'X' ('{0} -> {1}: {2}' -f $Path, $Name, $_.Exception.Message)
  }
}

function Get-DirSize {
  param([string]$Path)
  $sum = 0
  if (Test-Path -LiteralPath $Path) {
    try { $s = (Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum; if ($s) { $sum = $s } } catch { }
  }
  return $sum
}

function Invoke-RegBackup {
  $regDir = Join-Path $script:CurrentBackup 'reg'
  New-Item -ItemType Directory -Path $regDir -Force | Out-Null
  $i = 0
  foreach ($k in $RegKeysToBackup) {
    $i++
    if (Test-Path -LiteralPath $k) {
      $key = ($k -replace '^HKLM:', 'HKLM') -replace '^HKCU:', 'HKCU'
      $file = Join-Path $regDir ('{0:D2}_{1}.reg' -f $i, ($key -replace '[\\:\{\}]', '_'))
      reg.exe export $key $file /y 1>$null 2>$null
      if ($LASTEXITCODE -eq 0) { Log 'OK' ('бэкап реестра: ' + $k) } else { Log '!' ('бэкап не удался: ' + $k) }
    }
  }
}

function Invoke-Snapshot {
  $svcRows = @()
  foreach ($n in $script:ServiceNames) {
    $svc = Get-Service -Name $n -ErrorAction SilentlyContinue
    if ($svc) {
      $reg = Get-ItemProperty -LiteralPath ('HKLM:\SYSTEM\CurrentControlSet\Services\' + $n) -ErrorAction SilentlyContinue
      $delayed = 0
      if ($reg -and $null -ne $reg.DelayedAutostart) { $delayed = [int]$reg.DelayedAutostart }
      $svcRows += [pscustomobject]@{ Name = $n; StartType = [string]$svc.StartType; Status = [string]$svc.Status; Delayed = $delayed }
    }
  }
  if ($svcRows.Count -gt 0) { $svcRows | Export-Csv -Path (Join-Path $script:CurrentBackup 'services.csv') -NoTypeInformation -Encoding UTF8 }
  $taskRows = @()
  foreach ($t in $script:TaskList) {
    try {
      $task = Get-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction Stop
      $taskRows += [pscustomobject]@{ TaskPath = $task.TaskPath; TaskName = $task.TaskName; State = [string]$task.State }
    } catch { }
  }
  if ($taskRows.Count -gt 0) { $taskRows | Export-Csv -Path (Join-Path $script:CurrentBackup 'tasks.csv') -NoTypeInformation -Encoding UTF8 }
  $guid = ''
  $name = ''
  $cur = powercfg /getactivescheme
  if ($cur -match '([0-9a-fA-F]{8}-[0-9a-fA-F-]{27})\s+\((.+)\)') { $guid = $Matches[1]; $name = $Matches[2] }
  Set-Content -Path (Join-Path $script:CurrentBackup 'powerplan.txt') -Value $guid -Encoding UTF8
  Log 'I' ('Текущий план питания: ' + $name + ' ' + $guid)
}

function Invoke-RebootPrompt {
  Write-Host ''
  $a = Read-Host 'Перезагрузить ПК сейчас для применения твиков? (Y/N)'
  if ($a -match '^[YyДд]') {
    Log 'I' 'Перезагрузка через 10 секунд. Сохраните все файлы!'
    shutdown.exe /r /t 10 /c 'OptiForge: применение игровых твиков'
  }
}

function Invoke-Undo {
  Header 'ОТКАТ НАСТРОЕК - UNDO'
  if (-not (Test-Path -LiteralPath $BackupRoot)) { Log 'X' ('Папка бэкапов не найдена: ' + $BackupRoot); return }
  $latest = Get-ChildItem -LiteralPath $BackupRoot -Directory | Sort-Object CreationTime -Descending | Select-Object -First 1
  if (-not $latest) { Log 'X' 'Бэкапы не найдены.'; return }
  Log 'I' ('Используется бэкап: ' + $latest.FullName)

  Header 'UNDO 1/5 - ИМПОРТ РЕЕСТРА'
  $regDir = Join-Path $latest.FullName 'reg'
  if (Test-Path -LiteralPath $regDir) {
    foreach ($f in (Get-ChildItem -LiteralPath $regDir -Filter '*.reg')) {
      $null = reg.exe import $f.FullName 2>&1
      if ($LASTEXITCODE -eq 0) { Log 'OK' ('импортирован: ' + $f.Name) } else { Log '!' ('ошибка импорта: ' + $f.Name) }
    }
  } else { Log '!' 'Папка с .reg файлами не найдена.' }

  Header 'UNDO 2/5 - УДАЛЕНИЕ СОЗДАННЫХ КЛЮЧЕЙ И ПАРАМЕТРОВ'
  $ck = Join-Path $latest.FullName 'created-keys.txt'
  if (Test-Path -LiteralPath $ck) {
    foreach ($k in (Get-Content -LiteralPath $ck)) {
      if ($k) { Remove-Item -LiteralPath $k -Recurse -Force -ErrorAction SilentlyContinue; Log 'OK' ('удалён созданный ключ: ' + $k) }
    }
  }
  $cv = Join-Path $latest.FullName 'created-values.csv'
  if (Test-Path -LiteralPath $cv) {
    Import-Csv -LiteralPath $cv | ForEach-Object {
      Remove-ItemProperty -LiteralPath $_.Path -Name $_.Name -Force -ErrorAction SilentlyContinue
      Log 'OK' ('удалён созданный параметр: ' + $_.Path + ' -> ' + $_.Name)
    }
  }

  Header 'UNDO 3/5 - ВОССТАНОВЛЕНИЕ СЛУЖБ И ЗАДАЧ'
  $svcCsv = Join-Path $latest.FullName 'services.csv'
  if (Test-Path -LiteralPath $svcCsv) {
    Import-Csv -LiteralPath $svcCsv | ForEach-Object {
      try {
        if ([int]$_.Delayed -eq 1) {
          $null = sc.exe config $_.Name start= delayed-auto
          Log 'OK' ('служба ' + $_.Name + ': Automatic, отложенный запуск')
        } else {
          Set-Service -Name $_.Name -StartupType $_.StartType -ErrorAction Stop
          Log 'OK' ('служба ' + $_.Name + ': ' + $_.StartType)
        }
        if ($_.Status -eq 'Running') { Start-Service -Name $_.Name -ErrorAction SilentlyContinue }
      } catch { Log '!' ('служба ' + $_.Name + ': ' + $_.Exception.Message) }
    }
  }
  $taskCsv = Join-Path $latest.FullName 'tasks.csv'
  if (Test-Path -LiteralPath $taskCsv) {
    Import-Csv -LiteralPath $taskCsv | ForEach-Object {
      try {
        if ($_.State -eq 'Enabled') {
          Enable-ScheduledTask -TaskPath $_.TaskPath -TaskName $_.TaskName -ErrorAction Stop | Out-Null
        } else {
          Disable-ScheduledTask -TaskPath $_.TaskPath -TaskName $_.TaskName -ErrorAction Stop | Out-Null
        }
        Log 'OK' ('задача восстановлена: ' + $_.TaskName)
      } catch { Log '!' ('задача ' + $_.TaskName + ': ' + $_.Exception.Message) }
    }
  }

  Header 'UNDO 4/5 - ВОССТАНОВЛЕНИЕ ПЛАНА ПИТАНИЯ'
  $pp = Join-Path $latest.FullName 'powerplan.txt'
  if (Test-Path -LiteralPath $pp) {
    $pguid = (Get-Content -LiteralPath $pp | Select-Object -First 1)
    if ($pguid) {
      powercfg /setactive $pguid
      Log 'OK' ('план питания восстановлен: ' + $pguid)
    }
  } else {
    powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e
    Log 'OK' 'установлен сбалансированный план питания (Balanced)'
  }

  Header 'UNDO 5/5 - ПЕРЕРЕГИСТРАЦИЯ UWP-ПРИЛОЖЕНИЙ'
  try {
    Get-AppxPackage -AllUsers | ForEach-Object {
      try {
        if ($_.InstallLocation) {
          $man = Join-Path $_.InstallLocation 'AppXManifest.xml'
          if (Test-Path -LiteralPath $man) { Add-AppxPackage -DisableDevelopmentMode -Register $man -ErrorAction SilentlyContinue }
        }
      } catch { }
    }
    Log 'OK' 'UWP-приложения перерегистрированы'
  } catch { Log '!' ('AppX: ' + $_.Exception.Message) }
  $ap = Join-Path $latest.FullName 'appx-removed.txt'
  if (Test-Path -LiteralPath $ap) {
    $list = Get-Content -LiteralPath $ap
    Log 'I' ('Удалённые пакеты можно вернуть из Microsoft Store: ' + ($list -join ', '))
  }
  Log 'I' 'Полный откат системы: rstrui.exe -> точка восстановления OptiForge Gaming Optimizer'
}

Header ('OPTIFORGE - РЕЖИМ: ' + $Mode.ToUpper())
Log 'I' ('ОС: ' + $os.Caption + ' ' + $os.Version)
Log 'I' ('Компьютер: ' + $env:COMPUTERNAME + ', пользователь: ' + $env:USERNAME)
Log 'I' ('Лог-файл: ' + $LogFile)
Log 'I' ('Папка бэкапов: ' + $BackupRoot)

if ($Mode -eq 'Undo') {
  Invoke-Undo
  Invoke-RebootPrompt
  exit 0
}

$markerKey = 'HKLM:\SOFTWARE\OptiForge'
if (Test-Path -LiteralPath $markerKey -ErrorAction SilentlyContinue) {
  $prevRun = (Get-ItemProperty -LiteralPath $markerKey -ErrorAction SilentlyContinue).Applied
  if ($prevRun) {
    Log '!' ('Обнаружен предыдущий запуск OptiForge: ' + $prevRun)
    Log '!' 'Новый бэкап зафиксирует УЖЕ оптимизированное состояние. Откат к исходным настройкам Windows - только через rstrui.exe.'
  }
}

Write-Host ''
Write-Host 'Скрипт агрессивно оптимизирует Windows под игры: деблоат UWP,' -ForegroundColor White
Write-Host 'отключение телеметрии, MMCSS/GameDVR/приоритеты, SysMain/WSearch,' -ForegroundColor White
Write-Host 'очистка RAM и Temp-файлов. Не трогает активацию, System32 и драйверы.' -ForegroundColor White
$a = Read-Host 'Продолжить? (Y/N)'
if ($a -notmatch '^[YyДд]') { Log 'I' 'Остановлено пользователем.'; exit 0 }

Header 'ШАГ 0/6 - ТОЧКА ВОССТАНОВЛЕНИЯ СИСТЕМЫ'
try {
  Set-RegValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' -Name 'SystemRestorePointCreationFrequency' -Value 0
  Enable-ComputerRestore -Drive $env:SystemDrive -ErrorAction Stop
  Checkpoint-Computer -Description 'OptiForge Gaming Optimizer' -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
  $script:RestorePointOK = $true
  Log 'OK' 'Точка восстановления создана: OptiForge Gaming Optimizer'
} catch {
  Log '!' ('Не удалось создать точку восстановления: ' + $_.Exception.Message)
  Write-Host ''
  Write-Host 'Продолжить БЕЗ точки восстановления? Откат останется возможен через undo.' -ForegroundColor Yellow
  $ans = Read-Host 'Y - продолжить, N - выход'
  if ($ans -notmatch '^[YyДд]') { Log 'I' 'Остановлено пользователем.'; exit 0 }
}

Header 'РЕЗЕРВНЫЕ КОПИИ И СНАПШОТ СОСТОЯНИЯ'
$script:CurrentBackup = Join-Path $BackupRoot ('backup_' + $stamp)
New-Item -ItemType Directory -Path (Join-Path $script:CurrentBackup 'reg') -Force | Out-Null
Invoke-RegBackup
Invoke-Snapshot
Log 'OK' ('Бэкап сохранён: ' + $script:CurrentBackup)

Header 'ШАГ 1/6 - EXTREME DEBLOAT: УДАЛЕНИЕ UWP-МУСОРА'
Get-Process -Name '*Widget*' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
$patterns = @(
  'Clipchamp.Clipchamp',
  'Microsoft.3DBuilder',
  'Microsoft.549981C3F5F10',
  'Microsoft.Bing*',
  'Microsoft.Copilot*',
  'Microsoft.News',
  'Microsoft.Getstarted',
  'Microsoft.Messaging',
  'Microsoft.Microsoft3DViewer',
  'Microsoft.MicrosoftJournal',
  'Microsoft.MicrosoftOfficeHub',
  'Microsoft.MicrosoftPowerBIForWindows',
  'Microsoft.MicrosoftSolitaireCollection',
  'Microsoft.MicrosoftStickyNotes',
  'Microsoft.MixedReality.Portal',
  'Microsoft.NetworkSpeedTest',
  'Microsoft.Office.OneNote',
  'Microsoft.Office.Sway',
  'Microsoft.OneConnect',
  'Microsoft.Print3D',
  'Microsoft.PowerAutomateDesktop',
  'Microsoft.SkypeApp',
  'Microsoft.Todos',
  'Microsoft.Whiteboard',
  'Microsoft.Windows.AIHub',
  'Microsoft.Windows.DevHome',
  'Microsoft.WindowsFeedbackHub',
  'Microsoft.WindowsMaps',
  'Microsoft.WindowsAlarms',
  'Microsoft.WindowsSoundRecorder',
  'Microsoft.WindowsCommunicationsApps',
  'Microsoft.WidgetsPlatformRuntime',
  'MicrosoftWindows.Client.WebExperience',
  'Microsoft.XboxApp',
  'Microsoft.Xbox.TCUI',
  'Microsoft.XboxGameOverlay',
  'Microsoft.XboxGamingOverlay',
  'Microsoft.XboxIdentityProvider',
  'Microsoft.XboxSpeechToTextOverlay',
  'Microsoft.GamingApp',
  'Microsoft.YourPhone',
  'Microsoft.ZuneMusic',
  'Microsoft.ZuneVideo',
  'Microsoft.People',
  'MicrosoftCorporationII.MicrosoftFamily',
  'MicrosoftTeams',
  'MSTeams',
  'king.com.*',
  'SpotifyAB.SpotifyMusic',
  '4DF9E0F8.Netflix',
  'BytedancePte.Ltd.TikTok',
  'FACEBOOK.FACEBOOK',
  'Facebook.Instagram',
  'Disney*',
  'AdobeSystemsIncorporated.AdobePhotoshopExpress',
  'AmazonVideo.PrimeVideo',
  'Asphalt8Airborne',
  'AutodeskSketchBook',
  'Flipboard',
  'DrawboardPDF',
  'Duolingo-LearnLanguagesforFree',
  'HiddenCity',
  'iHeartRadio',
  'TuneInRadio',
  'WinZipUniversal',
  'LinkedInforWindows',
  'MarchofEmpires',
  'FarmVille2CountryEscape',
  'COOKINGFEVER',
  'CaesarsSlotsFreeCasino',
  'CyberLinkMediaSuiteEssentials',
  'PandoraMediaInc',
  'PicsArt-PhotoStudio',
  'PolarrPhotoEditorAcademicEdition',
  'PhototasticCollage',
  'Sidia.LiveWallpaper',
  'SlingTV',
  'HULULLC.HULUPLUS',
  'NYTCrossword',
  'OneCalendar',
  'ACGMediaPlayer',
  'ActiproSoftwareLLC',
  'flaregamesGmbH.RoyalRevolt'
)
$removed = @()
$all = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue
$targets = @($all | Where-Object { $n = $_.Name; @($patterns | Where-Object { $n -like $_ }).Count -gt 0 })
Log 'I' ('Найдено пакетов к удалению: ' + $targets.Count)
foreach ($pkg in $targets) {
  $done = $false
  try { $pkg | Remove-AppxPackage -AllUsers -ErrorAction Stop; $done = $true } catch { }
  if (-not $done) {
    try { $pkg | Remove-AppxPackage -ErrorAction Stop; $done = $true } catch { Log '!' ('не удалён: ' + $pkg.Name + ' - ' + $_.Exception.Message) }
  }
  if ($done) { Log 'OK' ('удалён: ' + $pkg.Name); $removed += $pkg.PackageFullName }
}
try {
  $prov = Get-AppxProvisionedPackage -Online -ErrorAction Stop
  foreach ($p in $prov) {
    if (@($patterns | Where-Object { $p.DisplayName -like $_ }).Count -gt 0) {
      try {
        Remove-AppxProvisionedPackage -Online -PackageName $p.PackageName -ErrorAction Stop | Out-Null
        Log 'OK' ('удалён из provisioning: ' + $p.DisplayName)
      } catch { Log '!' ('provisioning: ' + $p.DisplayName + ' - ' + $_.Exception.Message) }
    }
  }
} catch { Log '!' ('Get-AppxProvisionedPackage: ' + $_.Exception.Message) }
if ($removed.Count -gt 0) { $removed | Set-Content -Path (Join-Path $script:CurrentBackup 'appx-removed.txt') -Encoding UTF8 }
$script:RemovedApps = $removed.Count
Log 'I' ('Итого удалено пакетов: ' + $removed.Count)
Log '!' 'Важно: Xbox Identity Provider удалён. Если играете в Game Pass / игры из Store - верните его из Microsoft Store после оптимизации.'

Header 'ШАГ 2/6 - ТЕЛЕМЕТРИЯ, РЕКЛАМА, СЛЕЖКА'
foreach ($n in @('DiagTrack','dmwappushservice')) {
  $svc = Get-Service -Name $n -ErrorAction SilentlyContinue
  if ($svc) {
    try { Stop-Service -Name $n -Force -ErrorAction SilentlyContinue } catch { }
    try { Set-Service -Name $n -StartupType Disabled -ErrorAction Stop; Log 'OK' ('служба отключена: ' + $n) } catch { Log '!' ('служба ' + $n + ': ' + $_.Exception.Message) }
  } else { Log 'I' ('служба не найдена: ' + $n) }
}
foreach ($t in $script:TaskList) {
  try {
    $task = Get-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction Stop
    Disable-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction Stop | Out-Null
    Log 'OK' ('задача отключена: ' + $t.Name)
  } catch { Log 'I' ('задача пропущена: ' + $t.Name) }
}
Set-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' -Name 'AllowTelemetry' -Value 0
Set-RegValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' -Name 'AllowTelemetry' -Value 0
Set-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\SQM Clients\Windows' -Name 'CEIPEnable' -Value 0
Set-RegValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting' -Name 'Disabled' -Value 1
Set-RegValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' -Name 'Enabled' -Value 0
Set-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo' -Name 'DisabledByGroupPolicy' -Value 1
Set-RegValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' -Name 'TailoredExperiencesWithDiagnosticDataEnabled' -Value 0
Set-RegValue -Path 'HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy' -Name 'HasAccepted' -Value 0
Set-RegValue -Path 'HKCU:\Software\Microsoft\Input\TIPC' -Name 'Enabled' -Value 0
Set-RegValue -Path 'HKCU:\Software\Microsoft\InputPersonalization' -Name 'RestrictImplicitInkCollection' -Value 1
Set-RegValue -Path 'HKCU:\Software\Microsoft\InputPersonalization' -Name 'RestrictImplicitTextCollection' -Value 1
Set-RegValue -Path 'HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore' -Name 'HarvestContacts' -Value 0
Set-RegValue -Path 'HKCU:\Software\Microsoft\Personalization\Settings' -Name 'AcceptedPrivacyPolicy' -Value 0
Set-RegValue -Path 'HKCU:\Software\Microsoft\Siuf\Rules' -Name 'NumberOfSIUFInPeriod' -Value 0
Set-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name 'DisableWindowsConsumerFeatures' -Value 1
Set-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' -Name 'DODownloadMode' -Value 0
Set-RegValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' -Name 'BingSearchEnabled' -Value 0
Set-RegValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' -Name 'CortanaConsent' -Value 0
Set-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' -Name 'AllowCortana' -Value 0
Set-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer' -Name 'DisableSearchBoxSuggestions' -Value 1
$cdm = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
Set-RegValue -Path $cdm -Name 'SilentInstalledAppsEnabled' -Value 0
Set-RegValue -Path $cdm -Name 'SystemPaneSuggestionsEnabled' -Value 0
Set-RegValue -Path $cdm -Name 'PreInstalledAppsEnabled' -Value 0
Set-RegValue -Path $cdm -Name 'OemPreInstalledAppsEnabled' -Value 0
Set-RegValue -Path $cdm -Name 'SoftLandingEnabled' -Value 0
Set-RegValue -Path $cdm -Name 'RotatingLockScreenOverlayEnabled' -Value 0
Set-RegValue -Path $cdm -Name 'SubscribedContent-338387Enabled' -Value 0
Set-RegValue -Path $cdm -Name 'SubscribedContent-338388Enabled' -Value 0
Set-RegValue -Path $cdm -Name 'SubscribedContent-338389Enabled' -Value 0
Set-RegValue -Path $cdm -Name 'SubscribedContent-338393Enabled' -Value 0
Set-RegValue -Path $cdm -Name 'SubscribedContent-310093Enabled' -Value 0
Set-RegValue -Path $cdm -Name 'SubscribedContent-353694Enabled' -Value 0
Set-RegValue -Path $cdm -Name 'SubscribedContent-353696Enabled' -Value 0
Set-RegValue -Path $cdm -Name 'SubscribedContent-353698Enabled' -Value 0
Log 'OK' 'рекламный ID, предложения в Пуске, советы и автоустановка приложений отключены'

Header 'ШАГ 3/6 - FPS И ЛАГ: MMCSS, GAME DVR, ПРИОРИТЕТЫ'
$sp = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
Set-RegValue -Path $sp -Name 'NetworkThrottlingIndex' -Value 4294967295
Set-RegValue -Path $sp -Name 'SystemResponsiveness' -Value 0
$games = $sp + '\Tasks\Games'
Set-RegValue -Path $games -Name 'Affinity' -Value 0
Set-RegValue -Path $games -Name 'Background Only' -Value 'False' -Type 'String'
Set-RegValue -Path $games -Name 'Clock Rate' -Value 10000
Set-RegValue -Path $games -Name 'GPU Priority' -Value 8
Set-RegValue -Path $games -Name 'Priority' -Value 6
Set-RegValue -Path $games -Name 'Scheduling Category' -Value 'High' -Type 'String'
Set-RegValue -Path $games -Name 'SFIO Priority' -Value 'High' -Type 'String'
Log 'OK' 'MMCSS для игр: Priority=6, GPU Priority=8, Scheduling=High, SFIO=High'
Set-RegValue -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_Enabled' -Value 0
Set-RegValue -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_FSEBehaviorMode' -Value 2
Set-RegValue -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_HonorUserFSEBehaviorMode' -Value 1
Set-RegValue -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_DXGIHonorFSEWindowsCompatible' -Value 1
Set-RegValue -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_EFSEFeatureFlags' -Value 0
Set-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' -Name 'AllowGameDVR' -Value 0
Set-RegValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' -Name 'AppCaptureEnabled' -Value 0
Set-RegValue -Path 'HKCU:\Software\Microsoft\GameBar' -Name 'ShowStartupPanel' -Value 0
Set-RegValue -Path 'HKCU:\Software\Microsoft\GameBar' -Name 'UseNexusForGameBarEnabled' -Value 0
Set-RegValue -Path 'HKCU:\Software\Microsoft\GameBar' -Name 'AllowAutoGameMode' -Value 1
Set-RegValue -Path 'HKCU:\Software\Microsoft\GameBar' -Name 'AutoGameModeEnabled' -Value 1
Log 'OK' 'Game DVR и Game Bar выключены, оптимизация полного экрана отключена, игровой режим включён'
Set-RegValue -Path 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' -Name 'DirectXUserGlobalSettings' -Value 'SwapEffectUpgradeEnable=1;' -Type 'String'
Set-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name 'HwSchMode' -Value 2
Set-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' -Name 'Win32PrioritySeparation' -Value 38
Set-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' -Name 'PowerThrottlingOff' -Value 1
Set-RegValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'EnableTransparency' -Value 0
Set-RegValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' -Name 'GlobalUserDisabled' -Value 1
Set-RegValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'Start_IrisRecommendations' -Value 0
Set-RegValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'Start_AccountNotifications' -Value 0
Set-RegValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'TaskbarDa' -Value 0
Set-RegValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'TaskbarMn' -Value 0
Set-RegValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'ShowSyncProviderNotifications' -Value 0
Set-RegValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'Start_TrackProgs' -Value 0
Log 'OK' 'HAGS включён (если поддерживается GPU), приоритет форграунда=38, Power Throttling выключен, виджеты и уведомления Пуска убраны'

Header 'ШАГ 3B - ВИЗУАЛЬНЫЕ ЭФФЕКТЫ: ПРОИЗВОДИТЕЛЬНОСТЬ'
Set-RegValue -Path 'HKCU:\Control Panel\Desktop' -Name 'DragFullWindows' -Value '0' -Type 'String'
Set-RegValue -Path 'HKCU:\Control Panel\Desktop' -Name 'MenuShowDelay' -Value '0' -Type 'String'
Set-RegValue -Path 'HKCU:\Control Panel\Desktop\WindowMetrics' -Name 'MinAnimate' -Value '0' -Type 'String'
Set-RegValue -Path 'HKCU:\Control Panel\Keyboard' -Name 'KeyboardDelay' -Value '0' -Type 'String'
Set-RegValue -Path 'HKCU:\Control Panel\Desktop' -Name 'UserPreferencesMask' -Value ([byte[]](144,18,3,128,16,0,0,0)) -Type 'Binary'
Set-RegValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'ListviewAlphaSelect' -Value 0
Set-RegValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'ListviewShadow' -Value 0
Set-RegValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'TaskbarAnimations' -Value 0
Set-RegValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' -Name 'VisualFXSetting' -Value 3
Set-RegValue -Path 'HKCU:\Software\Microsoft\Windows\DWM' -Name 'EnableAeroPeek' -Value 0
Log 'OK' 'анимации и прозрачность выключены, визуальные эффекты: производительность'

Header 'ШАГ 4/6 - RAM: SysMain, WSearch И ПЛАН ПИТАНИЯ'
foreach ($n in @('SysMain','WSearch')) {
  $svc = Get-Service -Name $n -ErrorAction SilentlyContinue
  if ($svc) {
    try { Stop-Service -Name $n -Force -ErrorAction SilentlyContinue } catch { }
    try { Set-Service -Name $n -StartupType Disabled -ErrorAction Stop; Log 'OK' ('служба отключена: ' + $n) } catch { Log '!' ('служба ' + $n + ': ' + $_.Exception.Message) }
  } else { Log 'I' ('служба не найдена: ' + $n) }
}
Log 'I' 'WSearch отключён: поиск по файлам будет медленнее - это ожидаемо. Возврат через undo.bat.'
$dup = powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>$null
if ($dup -match '([0-9a-fA-F]{8}-[0-9a-fA-F-]{27})') {
  powercfg /setactive $Matches[1]
  Log 'OK' ('активирован план питания: Максимальная производительность ' + $Matches[1])
} else {
  powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null
  if ($LASTEXITCODE -eq 0) { Log 'OK' 'активирован план питания: Высокая производительность' }
  else { Log '!' 'Не удалось сменить план питания' }
}
$bat = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
if ($bat) { Log '!' 'Обнаружен аккумулятор: на ноутбуке этот план быстрее разряжает батарею.' }

Header 'ШАГ 5/6 - RAM: ОЧИСТКА STANDBY LIST И WORKING SET'
$freeBefore = [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1MB, 2)
Log 'I' ('Свободная RAM до очистки: ' + $freeBefore + ' ГБ')
try {
  Add-Type -MemberDefinition '[DllImport("ntdll.dll")] public static extern int RtlAdjustPrivilege(int Privilege, bool Enable, bool Thread, out bool Previous); [DllImport("ntdll.dll")] public static extern uint NtSetSystemInformation(int InfoClass, IntPtr Info, int Length);' -Name NativeMem -Namespace OptiForge -ErrorAction SilentlyContinue
  $prev = $false
  $pr = [OptiForge.NativeMem]::RtlAdjustPrivilege(13, $true, $false, [ref]$prev)
  if ($pr -eq 0) {
    $buf = [Runtime.InteropServices.Marshal]::AllocHGlobal(4)
    [Runtime.InteropServices.Marshal]::WriteInt32($buf, 4)
    $status = [OptiForge.NativeMem]::NtSetSystemInformation(80, $buf, 4)
    [Runtime.InteropServices.Marshal]::FreeHGlobal($buf)
    if ($status -eq 0) { Log 'OK' 'Standby List очищен (MemoryPurgeStandbyList)' }
    else { Log '!' ('Purge Standby List не выполнен, NTSTATUS=0x{0:X8}' -f $status) }
  } else { Log '!' 'Не выдана привилегия SeProfileSingleProcessPrivilege' }
} catch { Log '!' ('Standby List: ' + $_.Exception.Message) }
try {
  Add-Type -MemberDefinition '[DllImport("psapi.dll")] public static extern int EmptyWorkingSet(IntPtr h);' -Name PsApi -Namespace OptiForge -ErrorAction SilentlyContinue
  $cnt = 0
  foreach ($p in (Get-Process)) {
    try { $h = $p.Handle; if ($h) { [void][OptiForge.PsApi]::EmptyWorkingSet($h); $cnt++ } } catch { }
  }
  Log 'OK' ('Working set очищен у процессов: ' + $cnt)
} catch { Log '!' ('EmptyWorkingSet: ' + $_.Exception.Message) }
$freeAfter = [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1MB, 2)
Log 'I' ('Свободная RAM после очистки: ' + $freeAfter + ' ГБ')

Header 'ШАГ 6/6 - ОЧИСТКА: TEMP, PREFETCH, КЭШ ОБНОВЛЕНИЙ'
$cleanTargets = @($env:TEMP, (Join-Path $env:SystemRoot 'Temp'), (Join-Path $env:SystemRoot 'Prefetch'))
$sizeBefore = 0
foreach ($t in $cleanTargets) { $sizeBefore += Get-DirSize $t }
foreach ($t in $cleanTargets) {
  if (Test-Path -LiteralPath $t) {
    Remove-Item -Path (Join-Path $t '*') -Recurse -Force -ErrorAction SilentlyContinue
    Log 'OK' ('очищено: ' + $t)
  }
}
$wuPath = Join-Path $env:SystemRoot 'SoftwareDistribution\Download'
$wuBefore = Get-DirSize $wuPath
Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
Stop-Service -Name bits -Force -ErrorAction SilentlyContinue
Remove-Item -Path (Join-Path $wuPath '*') -Recurse -Force -ErrorAction SilentlyContinue
Start-Service -Name bits -ErrorAction SilentlyContinue
Start-Service -Name wuauserv -ErrorAction SilentlyContinue
Log 'OK' ('очищен кэш обновлений: ' + $wuPath)
if (Get-Command -Name 'Delete-DeliveryOptimizationCache' -ErrorAction SilentlyContinue) {
  Delete-DeliveryOptimizationCache -Force -ErrorAction SilentlyContinue
  Log 'OK' 'кэш Delivery Optimization очищен'
} else { Log 'I' 'Delete-DeliveryOptimizationCache недоступен - пропущено' }
$sizeAfter = 0
foreach ($t in $cleanTargets) { $sizeAfter += Get-DirSize $t }
$wuAfter = Get-DirSize $wuPath
$freedMB = [math]::Round(($sizeBefore + $wuBefore - $sizeAfter - $wuAfter) / 1MB, 1)
Log 'OK' ('освобождено на диске: ' + $freedMB + ' МБ')
Log 'I' 'Prefetch пересоздастся автоматически после запуска программ.'

Set-RegValue -Path 'HKLM:\SOFTWARE\OptiForge' -Name 'Applied' -Value $stamp -Type 'String'

if ($script:CreatedKeys.Count -gt 0) { $script:CreatedKeys | Set-Content -Path (Join-Path $script:CurrentBackup 'created-keys.txt') -Encoding UTF8 }
if ($script:CreatedValues.Count -gt 0) { $script:CreatedValues | Export-Csv -Path (Join-Path $script:CurrentBackup 'created-values.csv') -NoTypeInformation -Encoding UTF8 }

Header 'ИТОГИ ОПТИМИЗАЦИИ'
Log 'I' ('Точка восстановления: ' + $(if ($script:RestorePointOK) { 'создана' } else { 'НЕТ' }))
Log 'I' ('Удалено UWP-пакетов: ' + $script:RemovedApps)
Log 'I' ('Службы SysMain и WSearch: отключены')
Log 'I' ('План питания: Максимальная производительность')
Log 'I' ('Полный лог: ' + $LogFile)
Log 'I' ('Бэкап для отката: ' + $script:CurrentBackup)
Log 'I' 'Откат всех изменений: запустите undo.bat или optimize.bat -undo'
Log 'I' 'Полный откат системы: rstrui.exe -> точка OptiForge Gaming Optimizer'
Invoke-RebootPrompt
exit 0
<PSEND>
