# Что меняют скрипты

Этот файл описывает изменения, которые вносят скрипты. Если что-то в файле расходится с кодом, верить нужно коду.

## optimize.bat

### Точка восстановления

Создаёт точку «OptiForge Gaming Optimizer». Перед этим включает `SystemRestorePointCreationFrequency = 0`, чтобы точку можно было создать без ожидания суточного лимита.

### Удаление приложений (UWP)

Удаляются пакеты по шаблонам, в том числе:

- Xbox: `Microsoft.XboxApp`, `Microsoft.Xbox.TCUI`, `Microsoft.XboxGameOverlay`, `Microsoft.XboxGamingOverlay`, `Microsoft.XboxIdentityProvider`, `Microsoft.XboxSpeechToTextOverlay`, `Microsoft.GamingApp`
- Реклама и предложения: `Microsoft.Bing*`, `Microsoft.Copilot*`, `Microsoft.News`, `Microsoft.Getstarted`, `Microsoft.WidgetsPlatformRuntime` и другие
- Сторонние приложения-вставки вроде `Flipboard`, `LinkedInforWindows`, `SlingTV`, `PandoraMediaInc`
- Прочее: `Microsoft.YourPhone`, `Microsoft.People`, `Microsoft.ZuneMusic`, `Microsoft.ZuneVideo`, `MicrosoftTeams`

Пакеты возвращаются через Microsoft Store. `undo.bat` их не восстанавливает.

### Телеметрия и слежка

Службы, которые отключаются (тип запуска `Disabled`): `DiagTrack`, `dmwappushservice`.

Задачи планировщика, которые отключаются:

- `\Microsoft\Windows\Customer Experience Improvement Program\Consolidator`
- `\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip`
- `\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser`
- `\Microsoft\Windows\Application Experience\ProgramDataUpdater`
- `\Microsoft\Windows\Autochk\Proxy`
- `\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector`
- `\Microsoft\Windows\Feedback\Siuf\Rules\NumberOfSIUFInPeriod`

Реестр (раздел `HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection` и связанные):

- `AllowTelemetry = 0` в `DataCollection` (два раздела)
- `CEIPEnable = 0` в `SQM Clients\Windows`
- `Windows Error Reporting\Disabled = 1`
- `AdvertisingInfo\DisabledByGroupPolicy = 1` и `HKCU\...\AdvertisingInfo\Enabled = 0`
- `CloudContent\DisableWindowsConsumerFeatures = 1`
- `DeliveryOptimization\DODownloadMode = 0`
- `Windows Search\AllowCortana = 0`, `Explorer\DisableSearchBoxSuggestions = 1`
- Ряд параметров в `HKCU`: Input/Speech personalization, `Siuf\Rules`, `Search\BingSearchEnabled`, `Search\CortanaConsent`, `Privacy\TailoredExperiencesWithDiagnosticDataEnabled`

### Игровые параметры

- Game DVR и Game Bar: `GameDVR` и `GameBar` в `HKCU` и `HKLM\...\Policies\...\GameDVR\AllowGameDVR = 0`. Win+G перестаёт работать.
- `GameConfigStore`: `GameDVR_Enabled = 0`, `GameDVR_FSEBehaviorMode = 2` и связанные.
- `SystemProfile\Multimedia`: настройки MMCSS.
- `GraphicsDrivers\HwSchMode = 2` (аппаратное планирование GPU; работает не на всех видеокартах).
- `PriorityControl\Win32PrioritySeparation = 38`.
- `Power\PowerThrottling\PowerThrottlingOff = 1`.
- `DirectXUserGlobalSettings`: `SwapEffectUpgradeEnable=1`.

### Визуальные эффекты

- `VisualFXSetting = 3` (особые эффекты выключены, кроме пары базовых).
- `MinAnimate`, `TaskbarAnimations`, `ListviewShadow`, `ListviewAlphaSelect`, `EnableAeroPeek = 0`, `EnableTransparency = 0`.
- `DragFullWindows`, `MenuShowDelay`, `KeyboardDelay` переставляются на низкие значения.

### Службы RAM

- `SysMain` (Superfetch) отключается.
- `WSearch` (Windows Search) отключается. Поиск по файлам при этом деградирует.

### План питания

Активируется «Максимальная производительность» (`e9a42b02-...`). Если его нет, активируется «Высокая производительность» (`8c5e7fda-...`).

### Очистка

- Standby list и working set очищаются через `EmptyWorkingSet` (psapi.dll).
- Удаляются содержимое `%TEMP%`, `Windows\Temp`, `Windows\Prefetch`.
- Очищается кэш Windows Update и Delivery Optimization. Для этого останавливаются `wuauserv` и `bits`.

### Маркер

Создаётся раздел `HKLM\SOFTWARE\OptiForge` со значением `Applied`.

## network_optimizer.bat

### Снимок до изменений

Сохраняются в папку скрипта:

- `net_backup_interfaces.reg`: `HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces`
- `net_backup_systemprofile.reg`: `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile`
- `net_backup_psched.reg`: `HKLM\SOFTWARE\Policies\Microsoft\Windows\Psched` (файла нет, если раздела не было)
- `net_state.txt`: для каждого активного адаптера и для `Psched` записано, существовал ли параметр до изменений, и состояние энергосбережения адаптера

Если `net_state.txt` уже есть, снимок не пересоздаётся.

### Изменения

- Алгоритм Нэгла: `TcpAckFrequency = 1` и `TCPNoDelay = 1` в `Interfaces\{GUID}` для каждого активного адаптера.
- `SystemProfile\NetworkThrottlingIndex = 0xffffffff`.
- `Policies\Microsoft\Windows\Psched\NonBestEffortLimit = 0` (снимается резерв 20% полосы под QoS).
- `netsh int tcp`: `autotuninglevel=normal`, `rss=enabled`, `chimney=enabled`.
- Сброс кэша DNS (`ipconfig /flushdns`) и ARP (`arp -d *`).
- Отключение энергосбережения адаптеров: `Disable-NetAdapterPowerManagement`.

Перед изменениями создаётся точка восстановления «Network Latency Optimizer».

## undo.bat

1. Импортирует три `.reg`-файла из снимка.
2. Удаляет параметры, которых не было до изменений (по `net_state.txt`): `TcpAckFrequency`, `TCPNoDelay`, `NonBestEffortLimit`.
3. Возвращает состояние энергосбережения адаптеров.
4. Ставит `netsh` в значения по умолчанию Windows: `autotuninglevel=normal`, `rss=enabled`, `chimney=disabled`.
5. Удаляет `net_state.txt`, чтобы следующий запуск `network_optimizer.bat` снял новый снимок.
6. Запускает откат `optimize.bat -undo`: возвращает реестр, службы, задачи и план питания по своему бэкапу. Перерегистрирует UWP-пакеты, которые остались в системе. Удалённые пакеты возвращаются только через Microsoft Store.
