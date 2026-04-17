<#
.SYNOPSIS
    Win11 Gaming Audit v2 - Auditoria read-only + fix personalizado + benchmark.

.DESCRIPTION
    Escaneia Windows 11, gera relatorio (console/HTML/JSON), cria .bat de fix
    personalizado + .bat reverso, remove bloatware (opcional), detecta vendor
    GPU para recomendacoes especificas, modo -Watch continuo.

.PARAMETER Profile
    Competitive (aplica tudo), Balanced (alto+critico), Safe (so critico).

.PARAMETER OutputHtml
    Caminho HTML. Default: .\audit-<timestamp>.html

.PARAMETER OutputJson
    Caminho JSON. Default: .\audit-<timestamp>.json

.PARAMETER GenerateFix
    Gera Win11-Gaming-Fix.bat (respeita -Profile) + Reverter.bat.

.PARAMETER RemoveBloat
    Executa winget uninstall em bloatware conhecido (interativo).

.PARAMETER Watch
    Modo continuo: re-audita a cada N minutos e mostra diff.

.PARAMETER WithTemps
    Tenta ler temps via WMI (pode retornar falsos).

.PARAMETER SkipSlow
    Pula checks lentos (AppxPackage, game libraries).

.EXAMPLE
    .\Win11-Gaming-Audit.ps1
    .\Win11-Gaming-Audit.ps1 -GenerateFix -Profile Competitive
    .\Win11-Gaming-Audit.ps1 -Watch 30 -OutputJson .\history.json
    .\Win11-Gaming-Audit.ps1 -RemoveBloat
#>

#Requires -Version 5.1

param(
    [ValidateSet('Competitive','Balanced','Safe')] [string]$Profile = 'Balanced',
    [string]$OutputHtml,
    [string]$OutputJson,
    [switch]$GenerateFix,
    [switch]$RemoveBloat,
    [int]$Watch = 0,
    [switch]$WithTemps,
    [switch]$SkipSlow,
    [switch]$Auto,
    [string]$Compare,
    [switch]$Stage2,
    [switch]$DeepClean,
    [switch]$StreamJson
)

# ============================================================================
# CLOCKREAPER STREAMING PROTOCOL
# When -StreamJson is set, events are emitted on stdout as JSONL so the
# Tauri orchestrator can render scan progress in real time. Console output
# is suppressed in stream mode to keep stdout machine-parseable.
# ============================================================================
if ($StreamJson) {
    $helper = Join-Path $PSScriptRoot 'lib\json-emit.ps1'
    if (Test-Path $helper) { . $helper } else {
        Write-Error "Missing lib/json-emit.ps1 helper"
        exit 2
    }
    Emit-Start -Profile $Profile
}

# ============================================================================
# AUTO-ELEVATE
# ============================================================================
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent() `
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "Relancando como Administrador..." -ForegroundColor Yellow
    $argList = @('-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"",'-Profile',$Profile)
    if ($GenerateFix)  { $argList += '-GenerateFix' }
    if ($RemoveBloat)  { $argList += '-RemoveBloat' }
    if ($WithTemps)    { $argList += '-WithTemps' }
    if ($SkipSlow)     { $argList += '-SkipSlow' }
    if ($Watch -gt 0)  { $argList += '-Watch'; $argList += $Watch }
    if ($OutputHtml)   { $argList += '-OutputHtml'; $argList += "`"$OutputHtml`"" }
    if ($OutputJson)   { $argList += '-OutputJson'; $argList += "`"$OutputJson`"" }
    Start-Process powershell.exe -ArgumentList $argList -Verb RunAs
    exit
}

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'

# ============================================================================
# ANIMACOES (TUI)
# ============================================================================
function Show-FlowDiagram {
    Write-Host ""
    Write-Host "  COMO FUNCIONA O FLUXO:" -ForegroundColor White
    Write-Host ""
    Write-Host "    +-----------------+     +-----------------+     +-----------------+" -ForegroundColor DarkCyan
    Write-Host "    |   1. SCAN       |---->|   2. FIX.BAT    |---->|  3. APLICAR     |" -ForegroundColor DarkCyan
    Write-Host "    |   (read-only)   |     |  (gerado sob    |     |  + RESTORE PT   |" -ForegroundColor DarkCyan
    Write-Host "    |   acha erros    |     |   medida p/voce)|     |  + REBOOT       |" -ForegroundColor DarkCyan
    Write-Host "    +-----------------+     +-----------------+     +--------+--------+" -ForegroundColor DarkCyan
    Write-Host "                                                              |" -ForegroundColor DarkCyan
    Write-Host "    +-----------------+     +-----------------+              v" -ForegroundColor DarkCyan
    Write-Host "    |  5. SENTINEL    |<----|  4. RE-SCAN     |<---- (reinicia PC)" -ForegroundColor DarkCyan
    Write-Host "    |  monitora drift |     |  + COMPARE      |" -ForegroundColor DarkCyan
    Write-Host "    |  pos Windows Up |     |  antes x depois |" -ForegroundColor DarkCyan
    Write-Host "    +-----------------+     +-----------------+" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "  MODO AUTO: 1 comando faz passos 1-4 sozinho" -ForegroundColor Yellow
    Write-Host "    .\Win11-Gaming-Audit.ps1 -Auto" -ForegroundColor White
    Write-Host ""
    Write-Host "  MODO MANUAL: cada passo separado" -ForegroundColor Yellow
    Write-Host "    1) .\Win11-Gaming-Audit.ps1                 (so scan)" -ForegroundColor Gray
    Write-Host "    2) .\Win11-Gaming-Audit.ps1 -GenerateFix    (gera .bat)" -ForegroundColor Gray
    Write-Host "    3) .\Win11-Gaming-Fix-Balanced.bat          (voce roda)" -ForegroundColor Gray
    Write-Host "    4) reiniciar + .\Win11-Gaming-Audit.ps1     (valida)" -ForegroundColor Gray
    Write-Host "    5) .\Win11-Gaming-Sentinel.ps1 -Install     (blinda)" -ForegroundColor Gray
    Write-Host ""
}

function Show-StartupMenu {
    Show-FlowDiagram
    Write-Host "  MENU (ordem = jornada recomendada)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  -- DIAGNOSTICO --" -ForegroundColor DarkCyan
    Write-Host "    [1] SCAN read-only           nao modifica nada (COMECE AQUI)" -ForegroundColor White
    Write-Host ""
    Write-Host "  -- OTIMIZACAO --" -ForegroundColor DarkCyan
    Write-Host "    [2] MODO AUTO                scan + fix + reboot + compare (RECOMENDADO)" -ForegroundColor Green
    Write-Host "    [3] Gerar FIX.BAT manual     so gera, voce aplica depois" -ForegroundColor White
    Write-Host ""
    Write-Host "  -- VALIDACAO --" -ForegroundColor DarkCyan
    Write-Host "    [4] Comparar dois audits     tabela antes x depois (JSONs)" -ForegroundColor White
    Write-Host ""
    Write-Host "  -- PROTECAO --" -ForegroundColor DarkCyan
    Write-Host "    [5] INSTALAR SENTINEL        monitora drift pos Windows Update" -ForegroundColor Magenta
    Write-Host ""
    Write-Host "  -- OUTROS --" -ForegroundColor DarkCyan
    Write-Host "    [H] Ajuda detalhada" -ForegroundColor DarkGray
    Write-Host "    [X] Sair" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Dica: para menu completo com Benchmark + DeepClean + Revert," -ForegroundColor DarkYellow
    Write-Host "        use .\Win11-Gaming-Launcher.ps1" -ForegroundColor DarkYellow
    Write-Host ""
    $c = Read-Host "  Escolha"
    return $c
}

function Show-Help {
    Clear-Host
    Show-FlowDiagram
    Write-Host "  PROFILES (quao agressivo):" -ForegroundColor White
    Write-Host "    Safe         - so criticos (MPO, TRIM, etc). Minimo risco." -ForegroundColor Gray
    Write-Host "    Balanced     - criticos + altos. DEFAULT recomendado." -ForegroundColor Gray
    Write-Host "    Competitive  - tudo. Para pro players competitivos." -ForegroundColor Gray
    Write-Host ""
    Write-Host "  FLAGS DISPONIVEIS:" -ForegroundColor White
    Write-Host "    -Auto              Fluxo completo automatico (scan->fix->reboot->compare)" -ForegroundColor Gray
    Write-Host "    -GenerateFix       Gera Win11-Gaming-Fix-<Profile>.bat + Revert.bat" -ForegroundColor Gray
    Write-Host "    -Profile X         Safe | Balanced | Competitive" -ForegroundColor Gray
    Write-Host "    -RemoveBloat       Remove bloatware via winget (interativo)" -ForegroundColor Gray
    Write-Host "    -Watch N           Re-audita a cada N minutos" -ForegroundColor Gray
    Write-Host "    -Compare a.json,b.json   Compara dois audits" -ForegroundColor Gray
    Write-Host "    -WithTemps         Tenta ler temperaturas (WMI limitado)" -ForegroundColor Gray
    Write-Host "    -OutputHtml x      Caminho custom do HTML" -ForegroundColor Gray
    Write-Host "    -OutputJson x      Caminho custom do JSON (append historico)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  SCRIPTS COMPLEMENTARES:" -ForegroundColor White
    Write-Host "    Win11-Gaming-Benchmark.ps1  - mede FPS real via PresentMon antes/depois" -ForegroundColor Gray
    Write-Host "    Win11-Gaming-Sentinel.ps1   - detecta drift pos Windows Update" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Pressione qualquer tecla para voltar..." -ForegroundColor DarkGray
    $null = [Console]::ReadKey($true)
}

function Show-IntroBanner {
    Clear-Host
    $art = @(
        '  ____      _    __  __ ___ _   _  ____      _   _   _ ____ ___ _____ '
        ' / ___|    / \  |  \/  |_ _| \ | |/ ___|    / \ | | | |  _ \_ _|_   _|'
        '| |  _    / _ \ | |\/| || ||  \| | |  _    / _ \| | | | | | | |  | |  '
        '| |_| |  / ___ \| |  | || || |\  | |_| |  / ___ \ |_| | |_| | |  | |  '
        ' \____| /_/   \_\_|  |_|___|_| \_|\____| /_/   \_\___/|____/___| |_|  '
        ''
        '                  W I N 1 1   G A M I N G   A U D I T                 '
        '                            v2  -  2026                               '
    )
    # Fade-in colorido linha a linha
    $palette = @('DarkCyan','Cyan','Blue','Magenta','DarkMagenta','Red','Yellow','Green')
    for ($i=0; $i -lt $art.Count; $i++) {
        $c = $palette[$i % $palette.Count]
        Write-Host $art[$i] -ForegroundColor $c
        Start-Sleep -Milliseconds 60
    }
    Write-Host ""
    # Typewriter no tagline
    $tag = "  [ read-only scanner -> personalized fix -> regression sentinel ]"
    foreach ($ch in $tag.ToCharArray()) {
        Write-Host -NoNewline $ch -ForegroundColor DarkGray
        Start-Sleep -Milliseconds 8
    }
    Write-Host ""; Write-Host ""
}

function Invoke-WithSpinner {
    param([string]$Label, [scriptblock]$Action)
    $frames = @('|','/','-','\')
    $job = Start-Job -ScriptBlock $Action
    $i = 0
    while ($job.State -eq 'Running') {
        Write-Host -NoNewline "`r  $($frames[$i % $frames.Count])  $Label         " -ForegroundColor Cyan
        Start-Sleep -Milliseconds 80
        $i++
    }
    $result = Receive-Job $job
    Remove-Job $job -Force
    Write-Host -NoNewline "`r  [OK] $Label" -ForegroundColor Green
    Write-Host (' ' * 30)
    return $result
}

function Show-ProgressBar {
    param([int]$Current, [int]$Total, [string]$Label)
    $width = 40
    $pct = [math]::Min(100, [int](($Current / $Total) * 100))
    $filled = [int](($Current / $Total) * $width)
    $bar = ('#' * $filled) + ('.' * ($width - $filled))
    Write-Host -NoNewline ("`r  [$bar] {0,3}%  {1,-30}" -f $pct, $Label) -ForegroundColor Cyan
}

function Show-ScoreReveal {
    param([int]$Score)
    Write-Host ""
    Write-Host "  Calculando score" -NoNewline -ForegroundColor Cyan
    1..5 | ForEach-Object { Start-Sleep -Milliseconds 200; Write-Host -NoNewline '.' -ForegroundColor Cyan }
    Start-Sleep -Milliseconds 400
    Write-Host ""
    # Countdown revelador
    $color = if ($Score -ge 80) {'Green'} elseif ($Score -ge 60) {'Yellow'} else {'Red'}
    for ($i=0; $i -le $Score; $i += [math]::Max(1, [int]($Score/25))) {
        Write-Host -NoNewline ("`r     ->  $i/100  ") -ForegroundColor $color
        Start-Sleep -Milliseconds 20
    }
    Write-Host -NoNewline ("`r     ->  $Score/100  ") -ForegroundColor $color
    Write-Host ""
}

# ============================================================================
# MODELO
# ============================================================================
$findings = [System.Collections.Generic.List[object]]::new()
$advisories = [System.Collections.Generic.List[string]]::new()

function Add-Finding {
    param(
        [ValidateSet('CRITICO','ALTO','MEDIO','OK','INFO')] [string]$Severity,
        [string]$Category, [string]$Title, [string]$Current,
        [string]$Why, [string]$Impact, [string]$FixCmd, [string]$RevertCmd
    )
    $f = [pscustomobject]@{
        Severity=$Severity; Category=$Category; Title=$Title; Current=$Current
        Why=$Why; Impact=$Impact; FixCmd=$FixCmd; RevertCmd=$RevertCmd
    }
    $findings.Add($f) | Out-Null
    if ($StreamJson) { Emit-Finding -Finding $f }
}

function Get-RegValue { param($Path,$Name)
    try { (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name }
    catch { $null }
}

# ============================================================================
# INFO SISTEMA + VENDOR
# ============================================================================
$os   = Get-CimInstance Win32_OperatingSystem
$cs   = Get-CimInstance Win32_ComputerSystem
$cpu  = Get-CimInstance Win32_Processor | Select-Object -First 1
$gpus = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -notmatch 'Basic|Remote|Meta|Parsec' }
$ram  = [math]::Round($cs.TotalPhysicalMemory/1GB,1)

function Get-HardwareInventory {
    $inv = [ordered]@{}
    $bb = Get-CimInstance Win32_BaseBoard -EA SilentlyContinue
    $inv.Motherboard = if ($bb) { "$($bb.Manufacturer) $($bb.Product) (rev $($bb.Version))" } else { 'N/A' }
    $bios = Get-CimInstance Win32_BIOS -EA SilentlyContinue
    $inv.BIOS = if ($bios) { "$($bios.Manufacturer) $($bios.SMBIOSBIOSVersion) ($($bios.ReleaseDate.Substring(0,8)))" } else { 'N/A' }
    $encl = Get-CimInstance Win32_SystemEnclosure -EA SilentlyContinue
    $types = @{1='Other';2='Unknown';3='Desktop';4='Low Profile Desktop';5='Pizza Box';6='Mini Tower';7='Tower';8='Portable';9='Laptop';10='Notebook';11='Hand Held';13='All in One';14='Sub Notebook'}
    $inv.Chassis = if ($encl) { $types[[int]$encl.ChassisTypes[0]] } else { 'N/A' }
    $mods = @(Get-CimInstance Win32_PhysicalMemory)
    $ramDetails = $mods | ForEach-Object {
        $type = switch ([int]$_.SMBIOSMemoryType) { 26{'DDR4'} 34{'DDR5'} 24{'DDR3'} default{"Type$($_.SMBIOSMemoryType)"} }
        $cap = [math]::Round($_.Capacity/1GB,0)
        "$($_.Manufacturer.Trim()) $($_.PartNumber.Trim()) ${cap}GB $type @$($_.ConfiguredClockSpeed)MHz/$($_.Speed)MHz (slot $($_.DeviceLocator))"
    }
    $inv.RAM_Modules = $ramDetails
    $inv.RAM_Total = "$([math]::Round(($mods | Measure-Object Capacity -Sum).Sum/1GB,1)) GB ($($mods.Count)x)"
    $inv.CPU = "$($cpu.Name.Trim()) | $($cpu.NumberOfCores)C/$($cpu.NumberOfLogicalProcessors)T | base $($cpu.MaxClockSpeed)MHz | socket $($cpu.SocketDesignation)"
    $inv.GPUs = $gpus | ForEach-Object {
        $vram = if ($_.AdapterRAM) { [math]::Round($_.AdapterRAM/1GB,1) } else { '?' }
        "$($_.Name) | ${vram}GB VRAM | driver $($_.DriverVersion)"
    }
    $inv.Storage = Get-PhysicalDisk | ForEach-Object {
        $size = [math]::Round($_.Size/1GB,0)
        "$($_.FriendlyName) | ${size}GB | $($_.MediaType) | $($_.BusType)"
    }
    $inv.Network = Get-NetAdapter | Where-Object Status -eq 'Up' | ForEach-Object {
        "$($_.InterfaceDescription) | $($_.LinkSpeed) | MAC $($_.MacAddress)"
    }
    try {
        $monitors = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -EA Stop
        $inv.Monitors = $monitors | ForEach-Object {
            $name = -join ($_.UserFriendlyName | Where-Object { $_ -ne 0 } | ForEach-Object {[char]$_})
            $mfg  = -join ($_.ManufacturerName | Where-Object { $_ -ne 0 } | ForEach-Object {[char]$_})
            "$mfg $name"
        }
    } catch { $inv.Monitors = @('N/A') }
    $inv.Audio = Get-CimInstance Win32_SoundDevice -EA SilentlyContinue | Where-Object Status -eq 'OK' | ForEach-Object { $_.Name }
    try {
        $fans = Get-CimInstance Win32_Fan -EA Stop
        $inv.Fans = if ($fans) { $fans | ForEach-Object { "$($_.Name) @ $($_.DesiredSpeed) RPM" } } else { @('Nao detectado via WMI (normal em desktop - use HWiNFO64/FanControl)') }
    } catch { $inv.Fans = @('Nao detectado via WMI (normal em desktop - use HWiNFO64/FanControl)') }
    $bat = Get-CimInstance Win32_Battery -EA SilentlyContinue
    if ($bat) { $inv.Battery = "$($bat.Name) | design $($bat.DesignCapacity)mWh" }
    try {
        $tpm = Get-Tpm -EA Stop
        $inv.TPM = "Present=$($tpm.TpmPresent) Ready=$($tpm.TpmReady)"
    } catch { $inv.TPM = 'N/A' }
    return $inv
}

function Show-Hardware {
    param($inv)
    Write-Host ""
    Write-Host ('=' * 74) -ForegroundColor Magenta
    Write-Host "   HARDWARE INVENTORY" -ForegroundColor Magenta
    Write-Host ('=' * 74) -ForegroundColor Magenta
    foreach ($k in $inv.Keys) {
        $v = $inv[$k]
        if ($v -is [array] -or $v -is [System.Collections.IList]) {
            Write-Host ("  {0}:" -f $k) -ForegroundColor Cyan
            $v | ForEach-Object { Write-Host "     $_" -ForegroundColor Gray }
        } else {
            Write-Host ("  {0,-14}: " -f $k) -ForegroundColor Cyan -NoNewline
            Write-Host $v -ForegroundColor Gray
        }
    }
    Write-Host ('=' * 74) -ForegroundColor Magenta
    Write-Host ""
}

function Get-GpuVendor {
    $names = ($gpus | Select-Object -ExpandProperty Name) -join ' '
    if ($names -match 'NVIDIA|GeForce|RTX|GTX') { return 'NVIDIA' }
    if ($names -match 'AMD|Radeon|RX ')         { return 'AMD' }
    if ($names -match 'Intel Arc|Intel\(R\) Graphics') { return 'Intel' }
    return 'Unknown'
}
function Get-CpuVendor {
    if ($cpu.Manufacturer -match 'AMD')   { return 'AMD' }
    if ($cpu.Manufacturer -match 'Intel') { return 'Intel' }
    return 'Unknown'
}
$gpuVendor = Get-GpuVendor
$cpuVendor = Get-CpuVendor

# ============================================================================
# GAME LIBRARIES (Steam/Epic/Battle.net/Riot)
# ============================================================================
function Get-GameLibraries {
    if ($SkipSlow) { return @() }
    $libs = @()
    # Steam
    $steamPath = Get-RegValue 'HKCU:\Software\Valve\Steam' 'SteamPath'
    if ($steamPath) {
        $vdf = Join-Path $steamPath 'steamapps\libraryfolders.vdf'
        if (Test-Path $vdf) {
            $content = Get-Content $vdf -Raw
            $paths = [regex]::Matches($content, '"path"\s+"([^"]+)"') | ForEach-Object { $_.Groups[1].Value -replace '\\\\','\' }
            foreach ($p in $paths) {
                Get-ChildItem (Join-Path $p 'steamapps\*.acf') -ErrorAction SilentlyContinue | ForEach-Object {
                    $c = Get-Content $_.FullName -Raw
                    if ($c -match '"name"\s+"([^"]+)"') { $libs += [pscustomobject]@{Store='Steam';Name=$matches[1]} }
                }
            }
        }
    }
    # Epic
    $epicManifests = "$env:ProgramData\Epic\EpicGamesLauncher\Data\Manifests"
    if (Test-Path $epicManifests) {
        Get-ChildItem $epicManifests -Filter *.item | ForEach-Object {
            $j = Get-Content $_.FullName -Raw | ConvertFrom-Json
            if ($j.DisplayName) { $libs += [pscustomobject]@{Store='Epic';Name=$j.DisplayName} }
        }
    }
    # Riot
    if (Test-Path "$env:ProgramData\Riot Games") {
        Get-ChildItem "$env:ProgramData\Riot Games" -Directory | ForEach-Object {
            $libs += [pscustomobject]@{Store='Riot';Name=$_.Name}
        }
    }
    return $libs
}

# ============================================================================
# TESTES (todos preenchem $findings)
# ============================================================================

function Test-PowerPlan {
    $active = (powercfg /getactivescheme) -join ' '
    if ($active -notmatch 'Ultimate|Maximo|Máximo') {
        Add-Finding -Severity 'ALTO' -Category 'Energia' `
            -Title 'Plano de energia nao e Ultimate Performance' -Current $active.Trim() `
            -Why 'Balanced aplica throttling e park cores, aumentando latencia de transicao.' `
            -Impact '+3-8% FPS medio' `
            -FixCmd "powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61`r`nfor /f `"tokens=4`" %%a in ('powercfg /list ^| findstr /i `"Ultimate`"') do powercfg /setactive %%a" `
            -RevertCmd 'powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e'
    } else {
        Add-Finding -Severity 'OK' -Category 'Energia' -Title 'Ultimate Performance ativo' -Current 'OK'
    }
    if (Test-Path "$env:SystemDrive\hiberfil.sys") {
        Add-Finding -Severity 'MEDIO' -Category 'Energia' `
            -Title 'Hibernacao ativa' -Current 'hiberfil.sys presente' `
            -Why 'Ocupa RAM-size GB em disco, sem uso em desktop gaming.' `
            -Impact 'Libera GBs no C:' `
            -FixCmd 'powercfg /h off' -RevertCmd 'powercfg /h on'
    }
}

function Test-GpuSettings {
    $hags = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode'
    if ($hags -ne 2) {
        Add-Finding -Severity 'ALTO' -Category 'GPU' -Title 'HAGS desligado' `
            -Current "HwSchMode=$hags" `
            -Why 'Delega scheduling ao hardware, reduz latencia de frame e overhead CPU.' `
            -Impact 'Latencia menor, melhor DLSS/FG' `
            -FixCmd 'reg add "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" /v HwSchMode /t REG_DWORD /d 2 /f' `
            -RevertCmd 'reg add "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" /v HwSchMode /t REG_DWORD /d 1 /f'
    } else { Add-Finding -Severity 'OK' -Category 'GPU' -Title 'HAGS ativo' -Current 'OK' }

    $mpo = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\Dwm' 'OverlayTestMode'
    if ($mpo -ne 5) {
        Add-Finding -Severity 'CRITICO' -Category 'GPU' -Title 'MPO habilitado' `
            -Current "OverlayTestMode=$([string]$mpo)" `
            -Why 'MPO causa stutter/flicker em DX11/12 (bug em NVIDIA 526+).' `
            -Impact '+5-15% 1% lows em CS2/Valorant' `
            -FixCmd 'reg add "HKLM\SOFTWARE\Microsoft\Windows\Dwm" /v OverlayTestMode /t REG_DWORD /d 5 /f' `
            -RevertCmd 'reg delete "HKLM\SOFTWARE\Microsoft\Windows\Dwm" /v OverlayTestMode /f'
    } else { Add-Finding -Severity 'OK' -Category 'GPU' -Title 'MPO desabilitado' -Current 'OK' }

    foreach ($g in $gpus) {
        $date = if ($g.DriverDate) { [Management.ManagementDateTimeConverter]::ToDateTime($g.DriverDate) } else { $null }
        $age  = if ($date) { (New-TimeSpan -Start $date -End (Get-Date)).Days } else { 0 }
        if ($age -gt 180) {
            $urlHint = switch ($gpuVendor) {
                'NVIDIA' { 'https://www.nvidia.com/Download/index.aspx' }
                'AMD'    { 'https://www.amd.com/en/support' }
                'Intel'  { 'https://www.intel.com/content/www/us/en/support/detect.html' }
                default  { 'site do fabricante' }
            }
            Add-Finding -Severity 'ALTO' -Category 'GPU' -Title "Driver antigo: $($g.Name)" `
                -Current "v$($g.DriverVersion) ($age dias)" `
                -Why "Drivers gaming recebem game-ready mensal. 6+ meses = perda em titulos novos." `
                -Impact '3-20% em titulos recentes' `
                -FixCmd "REM Baixar: $urlHint"
        }
    }

    # Vendor advisories
    if ($gpuVendor -eq 'NVIDIA') {
        $advisories.Add('[NVIDIA] Ativar Low Latency Mode=Ultra + Reflex no NVIDIA Control Panel. Desabilitar "Overlays" no GeForce Experience.')
    } elseif ($gpuVendor -eq 'AMD') {
        $advisories.Add('[AMD] Adrenalin > Gaming > Radeon Anti-Lag + Boost. Chill OFF em competitivo. Verificar Smart Access Memory (SAM) na BIOS.')
    } elseif ($gpuVendor -eq 'Intel') {
        $advisories.Add('[Intel] Arc Control > Performance Boost. Atualize driver via Intel Driver & Support Assistant.')
    }
}

function Test-GameFeatures {
    $gb = Get-RegValue 'HKCU:\Software\Microsoft\GameBar' 'UseNexusForGameBarEnabled'
    if ($gb -ne 0) {
        Add-Finding -Severity 'MEDIO' -Category 'Gaming' -Title 'Xbox Game Bar habilitada' `
            -Current "=$gb" -Why 'Overlay + XBL consome CPU/GPU em idle.' `
            -Impact '+1-3% FPS' `
            -FixCmd 'reg add "HKCU\Software\Microsoft\GameBar" /v UseNexusForGameBarEnabled /t REG_DWORD /d 0 /f' `
            -RevertCmd 'reg add "HKCU\Software\Microsoft\GameBar" /v UseNexusForGameBarEnabled /t REG_DWORD /d 1 /f'
    }
    $dvr = Get-RegValue 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled'
    if ($dvr -ne 0) {
        Add-Finding -Severity 'ALTO' -Category 'Gaming' -Title 'Game DVR habilitado' `
            -Current "=$dvr" -Why 'Grava clip continuo em jogos, stutter de disco.' `
            -Impact '+2-5% FPS' `
            -FixCmd "reg add `"HKCU\System\GameConfigStore`" /v GameDVR_Enabled /t REG_DWORD /d 0 /f`r`nreg add `"HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR`" /v AllowGameDVR /t REG_DWORD /d 0 /f" `
            -RevertCmd 'reg add "HKCU\System\GameConfigStore" /v GameDVR_Enabled /t REG_DWORD /d 1 /f'
    }
    $fso = Get-RegValue 'HKCU:\System\GameConfigStore' 'GameDVR_FSEBehaviorMode'
    if ($fso -ne 2) {
        Add-Finding -Severity 'MEDIO' -Category 'Gaming' -Title 'Fullscreen Optimizations ativas' `
            -Current "=$fso" -Why 'FSO forca borderless via DWM, ~1 frame de latencia extra.' `
            -Impact '-3 a -8ms latencia' `
            -FixCmd 'reg add "HKCU\System\GameConfigStore" /v GameDVR_FSEBehaviorMode /t REG_DWORD /d 2 /f' `
            -RevertCmd 'reg add "HKCU\System\GameConfigStore" /v GameDVR_FSEBehaviorMode /t REG_DWORD /d 0 /f'
    }
}

function Test-Services {
    $bloat = @(
        @{N='DiagTrack';      D='Telemetry';            W='Telemetria continua CPU/rede.'}
        @{N='SysMain';        D='Superfetch';           W='Preload de apps, inutil em SSD.'}
        @{N='WSearch';        D='Windows Search';       W='Indexacao gera spikes de disco.'}
        @{N='XblAuthManager'; D='Xbox Auth';            W='Inutil sem Xbox/GamePass.'}
        @{N='XboxGipSvc';     D='Xbox Accessory';       W='Idem.'}
        @{N='XboxNetApiSvc';  D='Xbox Live Net';        W='Idem.'}
        @{N='MapsBroker';     D='Downloaded Maps';      W='Mapas offline, inutil.'}
        @{N='RetailDemo';     D='Retail Demo';          W='So PCs de loja.'}
        @{N='Fax';            D='Fax';                  W='2026, serio?'}
        @{N='RemoteRegistry'; D='Remote Registry';      W='Vetor de seguranca se exposto.'}
        @{N='WerSvc';         D='Error Reporting';      W='Envia crash dumps, trava apps.'}
        @{N='dmwappushservice'; D='WAP Push Routing';   W='Inutil em desktop.'}
    )
    foreach ($s in $bloat) {
        $svc = Get-Service -Name $s.N -EA SilentlyContinue
        if (-not $svc) { continue }
        if ($svc.StartType -ne 'Disabled') {
            $sev = if ($svc.Status -eq 'Running') {'ALTO'} else {'MEDIO'}
            Add-Finding -Severity $sev -Category 'Servicos' `
                -Title "$($s.D) ($($s.N)) ativo" `
                -Current "Status=$($svc.Status) Start=$($svc.StartType)" -Why $s.W `
                -Impact 'RAM/CPU/disco liberados' `
                -FixCmd "sc config $($s.N) start=disabled & sc stop $($s.N)" `
                -RevertCmd "sc config $($s.N) start=auto & sc start $($s.N)"
        }
    }
    $sp = Get-Service Spooler -EA SilentlyContinue
    if ($sp -and $sp.StartType -ne 'Disabled') {
        Add-Finding -Severity 'INFO' -Category 'Servicos' -Title 'Print Spooler ativo (avalie)' `
            -Current "Status=$($sp.Status)" `
            -Why 'RAM + historico de CVEs (PrintNightmare). Desabilite se nao imprime.' `
            -Impact '~20-40MB RAM' `
            -FixCmd 'sc config Spooler start=disabled & sc stop Spooler' `
            -RevertCmd 'sc config Spooler start=auto & sc start Spooler'
    }
}

function Test-Network {
    $nti = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'NetworkThrottlingIndex'
    if ($nti -ne 0xFFFFFFFF -and $nti -ne -1) {
        Add-Finding -Severity 'ALTO' -Category 'Rede' -Title 'NetworkThrottlingIndex limitando pacotes' `
            -Current "=$nti" -Why 'Throttling multimidia causa micro-pauses em jogo online.' `
            -Impact 'Spikes de ping reduzidos' `
            -FixCmd 'reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v NetworkThrottlingIndex /t REG_DWORD /d 0xFFFFFFFF /f' `
            -RevertCmd 'reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v NetworkThrottlingIndex /t REG_DWORD /d 10 /f'
    }
    $sr = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'SystemResponsiveness'
    if ($sr -ne 0 -and $sr -ne 10) {
        Add-Finding -Severity 'MEDIO' -Category 'Rede' -Title 'SystemResponsiveness reserva CPU nao-gaming' `
            -Current "=$sr (default 20)" -Why 'Default reserva 20% CPU para tarefas de fundo.' `
            -Impact 'Mais CPU em picos' `
            -FixCmd 'reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v SystemResponsiveness /t REG_DWORD /d 0 /f' `
            -RevertCmd 'reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v SystemResponsiveness /t REG_DWORD /d 20 /f'
    }
    $ifs = Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces' -EA SilentlyContinue
    $nag = 0
    foreach ($i in $ifs) {
        if ((Get-RegValue $i.PSPath 'TcpAckFrequency') -ne 1 -or (Get-RegValue $i.PSPath 'TCPNoDelay') -ne 1) { $nag++ }
    }
    if ($nag -gt 0) {
        $fix = $ifs | ForEach-Object {
            $g=$_.PSChildName
            "reg add `"HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$g`" /v TcpAckFrequency /t REG_DWORD /d 1 /f"
            "reg add `"HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$g`" /v TCPNoDelay /t REG_DWORD /d 1 /f"
        }
        $rev = $ifs | ForEach-Object {
            $g=$_.PSChildName
            "reg delete `"HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$g`" /v TcpAckFrequency /f"
            "reg delete `"HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$g`" /v TCPNoDelay /f"
        }
        Add-Finding -Severity 'ALTO' -Category 'Rede' -Title "Nagle ativo em $nag interface(s)" `
            -Current 'TcpAckFrequency/TCPNoDelay nao setados' `
            -Why 'Nagle agrega pacotes, +40ms latencia. Inimigo #1 do FPS online.' `
            -Impact '-10 a -40ms latencia real' `
            -FixCmd ($fix -join "`r`n") -RevertCmd ($rev -join "`r`n")
    }
    $tcp = netsh int tcp show global 2>$null
    if ($tcp -match 'Receive-Side Scaling State\s*:\s*disabled') {
        Add-Finding -Severity 'MEDIO' -Category 'Rede' -Title 'RSS desabilitado' -Current 'RSS=off' `
            -Why 'Sem RSS, um core gargala no processamento de pacotes.' `
            -Impact 'Menos jitter' `
            -FixCmd 'netsh int tcp set global rss=enabled' `
            -RevertCmd 'netsh int tcp set global rss=disabled'
    }
}

function Test-Security {
    $dg = Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard -EA SilentlyContinue
    if ($dg -and $dg.SecurityServicesRunning -contains 2) {
        Add-Finding -Severity 'ALTO' -Category 'Seguranca' -Title 'Memory Integrity (HVCI) ativa' `
            -Current 'HVCI running' `
            -Why 'Isola kernel via virtualizacao. Reduz 5-15% FPS em CPU-bound.' `
            -Impact '+5-15% FPS. TRADEOFF: reduz seguranca anti-rootkit.' `
            -FixCmd 'reg add "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" /v Enabled /t REG_DWORD /d 0 /f' `
            -RevertCmd 'reg add "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" /v Enabled /t REG_DWORD /d 1 /f'
    }
    if ($dg -and $dg.VirtualizationBasedSecurityStatus -eq 2) {
        Add-Finding -Severity 'MEDIO' -Category 'Seguranca' -Title 'VBS ativo' `
            -Current 'VBS running' -Why 'Overhead de hypervisor mesmo sem HVCI.' `
            -Impact '+2-5% FPS. Reduz seguranca.' `
            -FixCmd 'bcdedit /set hypervisorlaunchtype off' `
            -RevertCmd 'bcdedit /set hypervisorlaunchtype auto'
    }
}

function Test-Scheduler {
    $wp = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation'
    if ($wp -ne 38) {
        Add-Finding -Severity 'MEDIO' -Category 'Scheduler' -Title 'Win32PrioritySeparation subotimo' `
            -Current "=$wp" -Why 'Valor 38 (0x26) boost 3x foreground.' `
            -Impact 'Menos stutter com apps abertos' `
            -FixCmd 'reg add "HKLM\SYSTEM\CurrentControlSet\Control\PriorityControl" /v Win32PrioritySeparation /t REG_DWORD /d 38 /f' `
            -RevertCmd 'reg add "HKLM\SYSTEM\CurrentControlSet\Control\PriorityControl" /v Win32PrioritySeparation /t REG_DWORD /d 2 /f'
    }
    $k = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'
    if ((Get-RegValue $k 'GPU Priority') -ne 8 -or (Get-RegValue $k 'Priority') -ne 6) {
        Add-Finding -Severity 'MEDIO' -Category 'Scheduler' -Title 'Tasks\Games nao priorizado' `
            -Current 'GPU Priority/Priority/Scheduling' `
            -Why 'MMCSS usa esses valores para priorizar threads de jogo.' `
            -Impact 'Threads priorizados sobre telemetria' `
            -FixCmd @'
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v "GPU Priority" /t REG_DWORD /d 8 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v "Priority" /t REG_DWORD /d 6 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v "Scheduling Category" /t REG_SZ /d "High" /f
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v "SFIO Priority" /t REG_SZ /d "High" /f
'@ `
            -RevertCmd 'reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v "GPU Priority" /t REG_DWORD /d 2 /f'
    }
}

function Test-Memory {
    $mm = Get-MMAgent -EA SilentlyContinue
    if ($mm -and $mm.MemoryCompression) {
        $sev = if ($ram -ge 32) {'MEDIO'} else {'INFO'}
        Add-Finding -Severity $sev -Category 'Memoria' -Title 'Memory Compression ativo' `
            -Current 'True' -Why 'Em 32GB+ RAM custa CPU sem beneficio.' `
            -Impact 'Menos CPU em bursts' `
            -FixCmd 'powershell -Command "Disable-MMAgent -MemoryCompression"' `
            -RevertCmd 'powershell -Command "Enable-MMAgent -MemoryCompression"'
    }
    $used = [math]::Round(100-($os.FreePhysicalMemory/$os.TotalVisibleMemorySize*100),1)
    if ($used -gt 80) {
        Add-Finding -Severity 'ALTO' -Category 'Memoria' -Title 'RAM alta em idle' `
            -Current "$used% de $ram GB" `
            -Why 'Pouca margem para jogos. Revise startup.' `
            -Impact 'Menos swap' -FixCmd 'REM Revise Gerenciador de Tarefas > Inicializar'
    }
}

function Test-Storage {
    $la = fsutil behavior query DisableLastAccess 2>$null
    if ($la -notmatch '= 1|= 3') {
        Add-Finding -Severity 'MEDIO' -Category 'Storage' -Title 'LastAccess ativo' `
            -Current ($la -join ' ') `
            -Why 'Cada leitura grava timestamp, I/O inutil em jogos.' `
            -Impact 'Menos escritas, menor desgaste SSD' `
            -FixCmd 'fsutil behavior set DisableLastAccess 1' `
            -RevertCmd 'fsutil behavior set DisableLastAccess 0'
    }
    foreach ($d in Get-PhysicalDisk) {
        $vols = Get-Partition -DiskNumber $d.DeviceId -EA SilentlyContinue | Get-Volume | Where-Object DriveLetter
        foreach ($v in $vols) {
            $pct = [math]::Round($v.SizeRemaining/$v.Size*100,1)
            if ($pct -lt 15) {
                Add-Finding -Severity 'ALTO' -Category 'Storage' -Title "Disco $($v.DriveLetter): com $pct% livre" `
                    -Current "$([math]::Round($v.SizeRemaining/1GB,1))/$([math]::Round($v.Size/1GB,1))GB" `
                    -Why 'SSD <15% livre degrada escrita (SLC cache).' -Impact 'Velocidade de escrita' `
                    -FixCmd 'cleanmgr /sagerun:1'
            }
        }
        if ($d.MediaType -eq 'SSD' -or $d.BusType -eq 'NVMe') {
            $t = fsutil behavior query DisableDeleteNotify NTFS 2>$null
            if ($t -match '= 1') {
                Add-Finding -Severity 'CRITICO' -Category 'Storage' -Title "TRIM off em SSD $($d.FriendlyName)" `
                    -Current 'DisableDeleteNotify=1' `
                    -Why 'Sem TRIM SSDs degradam progressivamente.' -Impact 'Restaura escrita' `
                    -FixCmd 'fsutil behavior set DisableDeleteNotify NTFS 0' `
                    -RevertCmd 'fsutil behavior set DisableDeleteNotify NTFS 1'
            }
        }
    }
}

function Test-Telemetry {
    $t = Get-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry'
    if ($t -ne 0) {
        Add-Finding -Severity 'MEDIO' -Category 'Telemetria' -Title 'Telemetria nao minimizada' `
            -Current "=$t" -Why 'Envio periodico consome CPU/rede/disco.' -Impact 'Menos processos' `
            -FixCmd 'reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry /t REG_DWORD /d 0 /f' `
            -RevertCmd 'reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry /f'
    }
    $ad = Get-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled'
    if ($ad -ne 0) {
        Add-Finding -Severity 'INFO' -Category 'Telemetria' -Title 'Advertising ID ativo' -Current "=$ad" `
            -Why 'Tracking pub.' -Impact 'Privacidade' `
            -FixCmd 'reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" /v Enabled /t REG_DWORD /d 0 /f' `
            -RevertCmd 'reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" /v Enabled /t REG_DWORD /d 1 /f'
    }
    $c = Get-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'AllowCortana'
    if ($c -ne 0) {
        Add-Finding -Severity 'INFO' -Category 'Telemetria' -Title 'Cortana ativa' -Current "=$c" `
            -Why 'RAM + requests de fundo.' -Impact '~100-200MB RAM' `
            -FixCmd 'reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search" /v AllowCortana /t REG_DWORD /d 0 /f' `
            -RevertCmd 'reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search" /v AllowCortana /f'
    }
}

function Test-Startup {
    $st = @(Get-CimInstance Win32_StartupCommand -EA SilentlyContinue)
    if ($st.Count -gt 8) {
        Add-Finding -Severity 'ALTO' -Category 'Startup' -Title "Muitos itens startup ($($st.Count))" `
            -Current (($st | Select-Object -First 10 -ExpandProperty Name) -join ', ') `
            -Why 'Cada item consome RAM e atrasa boot.' -Impact 'Boot rapido' `
            -FixCmd 'REM Ctrl+Shift+Esc > Inicializar, desabilite manualmente'
    }
    if (Get-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' 'OneDrive') {
        Add-Finding -Severity 'MEDIO' -Category 'Startup' -Title 'OneDrive no startup' `
            -Current 'presente' -Why 'Sync em background.' -Impact 'Menos I/O' `
            -FixCmd 'reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v OneDrive /f'
    }
}

function Test-Timer {
    $bcd = bcdedit /enum '{current}' 2>$null
    $u = $bcd -match 'useplatformtick\s+Yes'
    $d = $bcd -match 'disabledynamictick\s+Yes'
    if (-not $u -or -not $d) {
        Add-Finding -Severity 'MEDIO' -Category 'Timer' -Title 'Timer nao fixo (jitter)' `
            -Current "tick=$u dyn=$d" `
            -Why 'Win11 24H2 quebrou timer dinamica; tick fixo estabiliza frametime.' `
            -Impact 'Frametime estavel' `
            -FixCmd "bcdedit /set useplatformtick yes`r`nbcdedit /set disabledynamictick yes`r`nbcdedit /set useplatformclock no" `
            -RevertCmd "bcdedit /deletevalue useplatformtick`r`nbcdedit /deletevalue disabledynamictick"
    }
}

function Test-RamXmp {
    foreach ($m in Get-CimInstance Win32_PhysicalMemory) {
        if ($m.ConfiguredClockSpeed -and $m.Speed -and $m.ConfiguredClockSpeed -lt $m.Speed) {
            $biosKey = if ($cpuVendor -eq 'AMD') {'EXPO (AMD)'} else {'XMP (Intel)'}
            Add-Finding -Severity 'ALTO' -Category 'BIOS' -Title "RAM abaixo da spec ($($m.DeviceLocator))" `
                -Current "$($m.ConfiguredClockSpeed)MHz / $($m.Speed)MHz" `
                -Why "Sem $biosKey, RAM roda em JEDEC base." `
                -Impact '+5-15% FPS CPU-bound' `
                -FixCmd "REM Entre na BIOS (DEL/F2) e habilite $biosKey"
            break
        }
    }
    if ($cpuVendor -eq 'AMD') {
        $advisories.Add('[AMD CPU] Considere Ryzen Master para PBO/Curve Optimizer (undervolt + boost).')
    } elseif ($cpuVendor -eq 'Intel') {
        $advisories.Add('[Intel CPU] Considere Intel XTU para undervolt/OC.')
    }
}

function Test-Temps {
    if (-not $WithTemps) { return }
    try {
        $t = Get-CimInstance -Namespace root\WMI -ClassName MSAcpi_ThermalZoneTemperature -EA Stop
        foreach ($z in $t) {
            $c = [math]::Round(($z.CurrentTemperature/10)-273.15,1)
            if ($c -gt 85) {
                Add-Finding -Severity 'ALTO' -Category 'Termica' -Title "Zona termica quente: $c°C" `
                    -Current "$($z.InstanceName) $c°C" `
                    -Why 'Throttling termico acima de 85°C em CPU.' `
                    -Impact 'FPS cai sob carga' `
                    -FixCmd 'REM Limpe fans, troque thermal paste, cheque curva de fan.'
            } else {
                Add-Finding -Severity 'INFO' -Category 'Termica' -Title "Zona termica: $c°C" -Current 'OK'
            }
        }
    } catch {
        $advisories.Add('[TEMPS] WMI sem dados. Use HWiNFO64 ou LibreHardwareMonitor para temps reais.')
    }
}

function Test-MouseAccel {
    $ma = Get-RegValue 'HKCU:\Control Panel\Mouse' 'MouseSpeed'
    $mt1 = Get-RegValue 'HKCU:\Control Panel\Mouse' 'MouseThreshold1'
    $mt2 = Get-RegValue 'HKCU:\Control Panel\Mouse' 'MouseThreshold2'
    if ($ma -ne '0' -or $mt1 -ne '0' -or $mt2 -ne '0') {
        Add-Finding -Severity 'ALTO' -Category 'Input' -Title 'Mouse acceleration (Enhance Pointer Precision) ativo' `
            -Current "MouseSpeed=$ma Thresholds=$mt1/$mt2" `
            -Why 'Aceleracao de mouse e DESASTRE em FPS competitivo - mesmo movimento fisico gera deslocamentos diferentes dependendo da velocidade.' `
            -Impact 'Muscle memory consistente. Critico em CS2/Valorant/Apex.' `
            -FixCmd @'
reg add "HKCU\Control Panel\Mouse" /v MouseSpeed /t REG_SZ /d "0" /f
reg add "HKCU\Control Panel\Mouse" /v MouseThreshold1 /t REG_SZ /d "0" /f
reg add "HKCU\Control Panel\Mouse" /v MouseThreshold2 /t REG_SZ /d "0" /f
'@ `
            -RevertCmd @'
reg add "HKCU\Control Panel\Mouse" /v MouseSpeed /t REG_SZ /d "1" /f
reg add "HKCU\Control Panel\Mouse" /v MouseThreshold1 /t REG_SZ /d "6" /f
reg add "HKCU\Control Panel\Mouse" /v MouseThreshold2 /t REG_SZ /d "10" /f
'@
    }
}

function Test-FastStartup {
    $fs = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled'
    if ($fs -ne 0) {
        Add-Finding -Severity 'MEDIO' -Category 'Energia' -Title 'Fast Startup habilitado' `
            -Current "HiberbootEnabled=$fs" `
            -Why 'Fast Startup e hibernacao parcial do kernel. Causa bugs de estado (drivers nao recarregam, VBS nao respeita toggle, rede as vezes congela no boot).' `
            -Impact 'Boot mais limpo, sem estado corrompido.' `
            -FixCmd 'reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power" /v HiberbootEnabled /t REG_DWORD /d 0 /f' `
            -RevertCmd 'reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power" /v HiberbootEnabled /t REG_DWORD /d 1 /f'
    }
}

function Test-SsdDefrag {
    $t = schtasks /query /tn '\Microsoft\Windows\Defrag\ScheduledDefrag' 2>$null
    if ($LASTEXITCODE -eq 0 -and $t -match 'Ready|Running|Pronto|Em execucao') {
        $hasSSD = (Get-PhysicalDisk | Where-Object { $_.MediaType -eq 'SSD' -or $_.BusType -eq 'NVMe' }).Count -gt 0
        if ($hasSSD) {
            Add-Finding -Severity 'MEDIO' -Category 'Storage' -Title 'Defrag agendado ativo (com SSD presente)' `
                -Current 'ScheduledDefrag=Ready' `
                -Why 'Defrag em SSD nao ajuda e causa writes desnecessarios. Win11 tecnicamente roda ReTrim em SSD, mas a task agendada ainda dispara analise.' `
                -Impact 'Menos writes, menor desgaste. Win11 faz TRIM automatico ainda.' `
                -FixCmd 'schtasks /Change /TN "\Microsoft\Windows\Defrag\ScheduledDefrag" /Disable' `
                -RevertCmd 'schtasks /Change /TN "\Microsoft\Windows\Defrag\ScheduledDefrag" /Enable'
        }
    }
}

function Test-NduService {
    $ndu = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Services\Ndu' 'Start'
    if ($ndu -ne 4) {
        Add-Finding -Severity 'INFO' -Category 'Rede' -Title 'Windows Network Data Usage (Ndu) ativo' `
            -Current "Start=$ndu" `
            -Why 'Ndu monitora uso de rede por app. Consome RAM passivamente. Pode adicionar microstutter em picos.' `
            -Impact 'Pequena reducao de RAM e jitter de rede.' `
            -FixCmd 'reg add "HKLM\SYSTEM\CurrentControlSet\Services\Ndu" /v Start /t REG_DWORD /d 4 /f' `
            -RevertCmd 'reg add "HKLM\SYSTEM\CurrentControlSet\Services\Ndu" /v Start /t REG_DWORD /d 2 /f'
    }
}

function Test-PageCombining {
    $mm = Get-MMAgent -EA SilentlyContinue
    if ($mm -and $mm.PageCombining) {
        Add-Finding -Severity 'INFO' -Category 'Memoria' -Title 'Page Combining ativo' `
            -Current 'True' `
            -Why 'Consolida paginas de memoria identicas. CPU overhead baixo mas mensuravel.' `
            -Impact 'Menos CPU em alocacao.' `
            -FixCmd 'powershell -Command "Disable-MMAgent -PageCombining"' `
            -RevertCmd 'powershell -Command "Enable-MMAgent -PageCombining"'
    }
}

function Test-BackgroundApps {
    $bg = Get-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled'
    if ($bg -ne 1) {
        Add-Finding -Severity 'MEDIO' -Category 'Startup' -Title 'Background apps permitidas' `
            -Current "GlobalUserDisabled=$bg" `
            -Why 'Apps UWP rodam em background consumindo RAM/CPU mesmo quando nao usados.' `
            -Impact 'Menos processos, mais RAM livre.' `
            -FixCmd 'reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" /v GlobalUserDisabled /t REG_DWORD /d 1 /f' `
            -RevertCmd 'reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" /v GlobalUserDisabled /f'
    }
}

function Test-DefenderExclusions {
    # Verifica exclusoes de jogos conhecidos
    try {
        $prefs = Get-MpPreference -EA Stop
        $excludedPaths = @($prefs.ExclusionPath)
        $gameFolders = @(
            "$env:ProgramFiles\Epic Games",
            "$env:ProgramFiles(x86)\Steam\steamapps",
            "$env:ProgramFiles(x86)\Riot Games"
        ) | Where-Object { Test-Path $_ }

        $missing = $gameFolders | Where-Object { $_ -notin $excludedPaths }
        if ($missing.Count -gt 0) {
            $adviceCmd = ($missing | ForEach-Object { "powershell -Command `"Add-MpPreference -ExclusionPath '$_'`"" }) -join "`r`n"
            Add-Finding -Severity 'ALTO' -Category 'Seguranca' -Title 'Windows Defender scaneando pastas de jogos' `
                -Current "$($missing.Count) pasta(s) sem exclusao" `
                -Why 'Defender faz scan em tempo real. Em jogos com muita leitura de asset (open world, MMO), causa stutters por I/O.' `
                -Impact '+3-10% carregamento, fim de stutters em loading de area. TRADEOFF: exclusoes reduzem superficie de deteccao.' `
                -FixCmd $adviceCmd `
                -RevertCmd (($missing | ForEach-Object { "powershell -Command `"Remove-MpPreference -ExclusionPath '$_'`"" }) -join "`r`n")
        }
    } catch {
        # Get-MpPreference falhou (Defender off?)
    }
}

function Test-Games {
    if ($SkipSlow) { return }
    $libs = Get-GameLibraries
    if ($libs.Count -eq 0) { return }
    $names = ($libs | Select-Object -First 8 -ExpandProperty Name) -join ', '
    Add-Finding -Severity 'INFO' -Category 'Jogos' -Title "$($libs.Count) jogos detectados" -Current $names
    $competitive = @('Counter-Strike','CS2','VALORANT','Apex Legends','League of Legends','Fortnite','Rainbow Six','Overwatch','Rocket League')
    $hits = $libs | Where-Object { $n=$_.Name; $competitive | Where-Object { $n -match $_ } }
    if ($hits) {
        $advisories.Add("[COMP] Detectado competitivo: $(($hits.Name -join ', ')). Priorize Profile=Competitive + desabilite VBS/HVCI.")
    }
}

# ============================================================================
# EXECUTAR
# ============================================================================
function Invoke-DeepClean {
    Write-Host ""
    Write-Host "  LIMPEZA PROFUNDA" -ForegroundColor Magenta
    Write-Host ('  ' + ('-' * 60)) -ForegroundColor DarkGray
    Write-Host "  Isso vai limpar: temp, Prefetch, DNS, shader cache (opcional)" -ForegroundColor Yellow
    Write-Host "  Pressione Y para continuar, N para cancelar: " -NoNewline -ForegroundColor Cyan
    if ((Read-Host) -notmatch '^[Yy]') { return }

    $totalFreed = 0

    # Temp user
    Write-Host "  -> Limpando %TEMP%..." -ForegroundColor Cyan
    $sizeBefore = (Get-ChildItem $env:TEMP -Recurse -Force -EA SilentlyContinue | Measure-Object Length -Sum).Sum
    Remove-Item "$env:TEMP\*" -Recurse -Force -EA SilentlyContinue
    $sizeAfter = (Get-ChildItem $env:TEMP -Recurse -Force -EA SilentlyContinue | Measure-Object Length -Sum).Sum
    $freed = [math]::Round(($sizeBefore - $sizeAfter)/1MB, 1)
    $totalFreed += $freed
    Write-Host "     liberados: $freed MB" -ForegroundColor Green

    # Windows Temp
    Write-Host "  -> Limpando C:\Windows\Temp..." -ForegroundColor Cyan
    Remove-Item "$env:SystemRoot\Temp\*" -Recurse -Force -EA SilentlyContinue
    Write-Host "     OK" -ForegroundColor Green

    # Prefetch (Windows recria os relevantes rapidamente)
    Write-Host "  -> Limpando Prefetch..." -ForegroundColor Cyan
    Remove-Item "$env:SystemRoot\Prefetch\*" -Recurse -Force -EA SilentlyContinue
    Write-Host "     OK (Windows recria os relevantes no proximo boot)" -ForegroundColor Green

    # DNS flush
    Write-Host "  -> Flush DNS cache..." -ForegroundColor Cyan
    ipconfig /flushdns | Out-Null
    Write-Host "     OK" -ForegroundColor Green

    # Software Distribution (Windows Update cache)
    Write-Host "  -> Limpando SoftwareDistribution\Download..." -ForegroundColor Cyan
    Stop-Service wuauserv -Force -EA SilentlyContinue
    Remove-Item "$env:SystemRoot\SoftwareDistribution\Download\*" -Recurse -Force -EA SilentlyContinue
    Start-Service wuauserv -EA SilentlyContinue
    Write-Host "     OK" -ForegroundColor Green

    # Delivery Optimization
    Write-Host "  -> Delivery Optimization cache..." -ForegroundColor Cyan
    try { Delete-DeliveryOptimizationCache -EA Stop; Write-Host "     OK" -ForegroundColor Green }
    catch { Write-Host "     pulado (cmdlet nao disponivel)" -ForegroundColor DarkGray }

    # Shader cache (AVISO: piora 10-30min depois)
    Write-Host ""
    Write-Host "  ATENCAO: apagar shader cache PIORA performance por 10-30min apos primeiro jogo." -ForegroundColor Yellow
    Write-Host "  Util apenas se suspeita de cache corrompido (stutter novo sem motivo)." -ForegroundColor Yellow
    Write-Host "  Apagar shader cache? [Y/N]: " -NoNewline -ForegroundColor Cyan
    if ((Read-Host) -match '^[Yy]') {
        $caches = @(
            "$env:USERPROFILE\AppData\LocalLow\NVIDIA\DXCache",
            "$env:USERPROFILE\AppData\LocalLow\NVIDIA\GLCache",
            "$env:USERPROFILE\AppData\Local\NVIDIA\DXCache",
            "$env:USERPROFILE\AppData\Local\NVIDIA\GLCache",
            "$env:USERPROFILE\AppData\Roaming\NVIDIA\ComputeCache",
            "$env:LOCALAPPDATA\AMD\DxCache",
            "$env:LOCALAPPDATA\AMD\GLCache",
            "$env:LOCALAPPDATA\D3DSCache"
        )
        foreach ($c in $caches) {
            if (Test-Path $c) {
                Remove-Item "$c\*" -Recurse -Force -EA SilentlyContinue
                Write-Host "     limpo: $c" -ForegroundColor Gray
            }
        }
    }

    # Icon cache rebuild
    Write-Host ""
    Write-Host "  Rebuild icon/thumb cache? (fix de icones bugados) [Y/N]: " -NoNewline -ForegroundColor Cyan
    if ((Read-Host) -match '^[Yy]') {
        Stop-Process -Name explorer -Force -EA SilentlyContinue
        Remove-Item "$env:LOCALAPPDATA\IconCache.db" -Force -EA SilentlyContinue
        Remove-Item "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\iconcache_*" -Force -EA SilentlyContinue
        Remove-Item "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*" -Force -EA SilentlyContinue
        Start-Process explorer.exe
        Write-Host "     OK (explorer reiniciado)" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "  DEEP CLEAN concluido. Total liberado estimado: ~$totalFreed MB em TEMP." -ForegroundColor Green
    Write-Host ""
}

function Invoke-Audit {
    $findings.Clear(); $advisories.Clear()
    $tests = @(
        @{Name='Test-PowerPlan';    Label='Plano de energia'}
        @{Name='Test-GpuSettings';  Label='GPU (HAGS, MPO, driver)'}
        @{Name='Test-GameFeatures'; Label='Game Bar / DVR / FSO'}
        @{Name='Test-Services';     Label='Servicos desnecessarios'}
        @{Name='Test-Network';      Label='Rede (Nagle, throttling)'}
        @{Name='Test-Security';     Label='VBS / HVCI'}
        @{Name='Test-Scheduler';    Label='Scheduler / MMCSS'}
        @{Name='Test-Memory';       Label='Memoria'}
        @{Name='Test-Storage';      Label='Storage / TRIM'}
        @{Name='Test-Telemetry';    Label='Telemetria / Cortana'}
        @{Name='Test-Startup';      Label='Itens de inicializacao'}
        @{Name='Test-Timer';        Label='Timer de sistema'}
        @{Name='Test-RamXmp';       Label='RAM XMP/EXPO'}
        @{Name='Test-Temps';        Label='Temperaturas'}
        @{Name='Test-MouseAccel';   Label='Mouse acceleration'}
        @{Name='Test-FastStartup';  Label='Fast Startup'}
        @{Name='Test-SsdDefrag';    Label='Defrag agendado em SSD'}
        @{Name='Test-NduService';   Label='Ndu service'}
        @{Name='Test-PageCombining';Label='Page Combining'}
        @{Name='Test-BackgroundApps';Label='Background apps UWP'}
        @{Name='Test-DefenderExclusions';Label='Defender exclusions'}
        @{Name='Test-Games';        Label='Biblioteca de jogos'}
    )
    Write-Host ""
    for ($i=0; $i -lt $tests.Count; $i++) {
        Show-ProgressBar -Current ($i+1) -Total $tests.Count -Label $tests[$i].Label
        & $tests[$i].Name
        Start-Sleep -Milliseconds 40
    }
    Write-Host ""
}

# ============================================================================
# RENDER CONSOLE
# ============================================================================
$sevColor = @{CRITICO='Red';ALTO='Yellow';MEDIO='DarkYellow';INFO='Cyan';OK='Green'}
$sevIcon  = @{CRITICO='[!!]';ALTO='[! ]';MEDIO='[~ ]';INFO='[i ]';OK='[ok]'}
$sevOrder = @{CRITICO=0;ALTO=1;MEDIO=2;INFO=3;OK=4}

function Render-Console {
    $line = ('=' * 74)
    Write-Host ""; Write-Host $line -ForegroundColor Cyan
    Write-Host "   WIN11 GAMING AUDIT v2  -  $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -ForegroundColor Cyan
    Write-Host "   Profile: $Profile" -ForegroundColor Magenta
    Write-Host "   $($os.Caption) build $($os.BuildNumber)" -ForegroundColor Gray
    Write-Host "   CPU: $($cpu.Name.Trim()) [$cpuVendor]" -ForegroundColor Gray
    Write-Host "   GPU: $(($gpus|%{$_.Name}) -join ' | ') [$gpuVendor]" -ForegroundColor Gray
    Write-Host "   RAM: $ram GB" -ForegroundColor Gray
    Write-Host $line -ForegroundColor Cyan; Write-Host ""

    foreach ($g in ($findings | Group-Object Category | Sort-Object Name)) {
        Write-Host "--- $($g.Name.ToUpper()) ---" -ForegroundColor White
        foreach ($f in ($g.Group | Sort-Object @{E={$sevOrder[$_.Severity]}})) {
            Write-Host ("$($sevIcon[$f.Severity]) $($f.Severity.PadRight(8)) $($f.Title)") -ForegroundColor $sevColor[$f.Severity]
            if ($f.Severity -ne 'OK') {
                if ($f.Current) { Write-Host "        Atual: $($f.Current)" -ForegroundColor DarkGray }
                if ($f.Why)     { Write-Host "        Por que: $($f.Why)" -ForegroundColor Gray }
                if ($f.Impact)  { Write-Host "        Impacto: $($f.Impact)" -ForegroundColor DarkCyan }
            }
        }
        Write-Host ""
    }

    if ($advisories.Count -gt 0) {
        Write-Host "--- ADVISORIES ---" -ForegroundColor Magenta
        $advisories | ForEach-Object { Write-Host "  * $_" -ForegroundColor Magenta }
        Write-Host ""
    }

    $cr = ($findings|? Severity -eq 'CRITICO').Count
    $al = ($findings|? Severity -eq 'ALTO').Count
    $me = ($findings|? Severity -eq 'MEDIO').Count
    $total = $findings.Count
    $nonOk = ($findings|? Severity -ne 'OK').Count
    $score = if ($total -gt 0) { [math]::Max(0, 100-($cr*10)-($al*5)-($me*2)) } else { 100 }
    $color = if ($score -ge 80) {'Green'} elseif ($score -ge 60) {'Yellow'} else {'Red'}
    Write-Host $line -ForegroundColor Cyan
    Write-Host "  SCORE: $score/100  |  $nonOk achados  |  $cr criticos, $al altos, $me medios" -ForegroundColor $color
    Write-Host $line -ForegroundColor Cyan
    return @{Score=$score;Critical=$cr;High=$al;Medium=$me;Total=$total}
}

# ============================================================================
# RENDER HTML / JSON / FIX / REVERT
# ============================================================================
function Render-Html {
    param($path,$stats)
    if (-not $path) { $path = ".\audit-$(Get-Date -Format 'yyyyMMdd-HHmm').html" }
    Add-Type -AssemblyName System.Web -EA SilentlyContinue
    $enc = { param($s) if ($s){[System.Web.HttpUtility]::HtmlEncode($s)}else{''} }
    $rows = foreach ($f in ($findings | Sort-Object @{E={$sevOrder[$_.Severity]}}, Category)) {
        $cls = $f.Severity.ToLower()
        @"
<tr class="sev-$cls"><td class="sev">$($f.Severity)</td><td>$($f.Category)</td>
<td><strong>$(& $enc $f.Title)</strong><br><small>$(& $enc $f.Current)</small></td>
<td>$(& $enc $f.Why)</td><td>$(& $enc $f.Impact)</td>
<td><pre>$(& $enc $f.FixCmd)</pre></td></tr>
"@
    }
    $advHtml = ($advisories | ForEach-Object { "<li>$(& $enc $_)</li>" }) -join "`n"
    $scoreClass = if ($stats.Score -ge 80){'good'}elseif($stats.Score -ge 60){'mid'}else{'bad'}
    @"
<!DOCTYPE html><html lang="pt-br"><head><meta charset="utf-8">
<title>Win11 Gaming Audit</title><style>
body{font-family:Segoe UI,system-ui;background:#0d1117;color:#c9d1d9;margin:0;padding:20px}
h1{color:#58a6ff}.meta{background:#161b22;padding:16px;border-radius:8px;margin-bottom:20px}
.score{font-size:48px;font-weight:bold}.good{color:#3fb950}.mid{color:#d29922}.bad{color:#f85149}
table{width:100%;border-collapse:collapse;background:#161b22;border-radius:8px;overflow:hidden}
th{background:#21262d;padding:12px;text-align:left;border-bottom:2px solid #30363d}
td{padding:12px;border-bottom:1px solid #30363d;vertical-align:top}
td.sev{font-weight:bold;white-space:nowrap}
.sev-critico td.sev{color:#f85149}.sev-alto td.sev{color:#d29922}
.sev-medio td.sev{color:#e3b341}.sev-info td.sev{color:#58a6ff}.sev-ok td.sev{color:#3fb950}
pre{background:#0d1117;padding:8px;border-radius:4px;white-space:pre-wrap;font-size:11px;color:#8b949e;margin:0}
small{color:#8b949e}.adv{background:#1f2328;padding:12px;border-left:4px solid #bc8cff;margin:16px 0}
</style></head><body>
<h1>Win11 Gaming Audit v2</h1>
<div class="meta">
<div><strong>Data:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm') | <strong>Profile:</strong> $Profile</div>
<div><strong>Sistema:</strong> $($os.Caption) build $($os.BuildNumber)</div>
<div><strong>CPU:</strong> $($cpu.Name.Trim()) [$cpuVendor]</div>
<div><strong>GPU:</strong> $(($gpus|%{$_.Name}) -join ' | ') [$gpuVendor]</div>
<div><strong>RAM:</strong> $ram GB</div>
<div class="score $scoreClass">$($stats.Score) / 100</div>
<div>$(($findings|? Severity -ne 'OK').Count) achados &middot; $($stats.Critical) criticos &middot; $($stats.High) altos</div>
</div>
<details open style="background:#161b22;padding:16px;border-radius:8px;margin-bottom:20px">
<summary style="cursor:pointer;color:#58a6ff;font-weight:bold">Hardware Inventory</summary>
<table style="margin-top:12px"><tbody>
$($hardware.Keys | ForEach-Object {
    $v = $hardware[$_]
    if ($v -is [array] -or $v -is [System.Collections.IList]) {
        "<tr><td style='font-weight:bold;vertical-align:top;color:#58a6ff'>$_</td><td>$(($v | ForEach-Object { & $enc $_ }) -join '<br>')</td></tr>"
    } else {
        "<tr><td style='font-weight:bold;color:#58a6ff'>$_</td><td>$(& $enc $v)</td></tr>"
    }
} | Out-String)
</tbody></table></details>
$(if($advisories.Count){"<div class='adv'><strong>Advisories</strong><ul>$advHtml</ul></div>"})
<table><thead><tr><th>Sev</th><th>Cat</th><th>Achado</th><th>Por que</th><th>Impacto</th><th>Fix</th></tr></thead>
<tbody>$($rows -join "`n")</tbody></table></body></html>
"@ | Out-File -FilePath $path -Encoding UTF8
    Write-Host "HTML: $path" -ForegroundColor Green
}

function Render-Json {
    param($path,$stats)
    if (-not $path) { $path = ".\audit-$(Get-Date -Format 'yyyyMMdd-HHmm').json" }
    $payload = [ordered]@{
        timestamp = (Get-Date).ToString('o')
        profile   = $Profile
        system    = @{
            os=$os.Caption; build=$os.BuildNumber
            cpu=$cpu.Name.Trim(); cpuVendor=$cpuVendor
            gpu=(($gpus|%{$_.Name}) -join ' | '); gpuVendor=$gpuVendor
            ramGB=$ram
        }
        hardware = $hardware
        score = $stats
        findings = $findings
        advisories = $advisories
    }
    # Append se arquivo existe
    if (Test-Path $path) {
        try {
            $existing = Get-Content $path -Raw | ConvertFrom-Json
            if ($existing -is [array]) { $arr = @($existing) + $payload }
            else { $arr = @($existing, $payload) }
            $arr | ConvertTo-Json -Depth 10 | Out-File -FilePath $path -Encoding UTF8
        } catch { $payload | ConvertTo-Json -Depth 10 | Out-File -FilePath $path -Encoding UTF8 }
    } else {
        @($payload) | ConvertTo-Json -Depth 10 | Out-File -FilePath $path -Encoding UTF8
    }
    Write-Host "JSON: $path" -ForegroundColor Green
}

function Get-ProfileFilter {
    switch ($Profile) {
        'Safe'        { return @('CRITICO') }
        'Balanced'    { return @('CRITICO','ALTO') }
        'Competitive' { return @('CRITICO','ALTO','MEDIO') }
    }
}

function Render-FixBat {
    $filter = Get-ProfileFilter
    $items = $findings | Where-Object {
        $_.Severity -in $filter -and $_.FixCmd -and $_.FixCmd -notmatch '^\s*REM'
    }
    if ($items.Count -eq 0) { Write-Host "Nada a aplicar no profile $Profile." -ForegroundColor Yellow; return }

    $fixPath = ".\Win11-Gaming-Fix-$Profile.bat"
    $rev     = ".\Win11-Gaming-Revert.bat"

    $fixLines = @(
        '@echo off','chcp 65001 >nul',"title Win11 Gaming Fix - $Profile"
        '','REM Gerado em ' + (Get-Date -Format 'yyyy-MM-dd HH:mm') + " para $env:COMPUTERNAME"
        "REM Profile: $Profile | $($items.Count) acoes"
        'REM RODE COMO ADMIN.',''
        'net session >nul 2>&1 || (echo Precisa admin. & pause & exit /b)'
        '','echo Criando ponto de restauracao...'
        'powershell -Command "Checkpoint-Computer -Description ''Pre-Gaming-Fix'' -RestorePointType MODIFY_SETTINGS" 2>nul',''
    )
    $revLines = @(
        '@echo off','chcp 65001 >nul','title Win11 Gaming Revert'
        '','REM Reverte as mudancas do fix.bat','net session >nul 2>&1 || (echo Precisa admin. & pause & exit /b)',''
    )
    foreach ($f in $items) {
        $fixLines += "REM === [$($f.Severity)] $($f.Category) - $($f.Title) ==="
        $fixLines += "REM Por que: $($f.Why)"
        $fixLines += "REM Impacto: $($f.Impact)"
        $fixLines += $f.FixCmd; $fixLines += ''
        if ($f.RevertCmd) {
            $revLines += "REM === REVERT: $($f.Title) ==="
            $revLines += $f.RevertCmd; $revLines += ''
        }
    }
    $fixLines += 'echo.','echo Concluido. REINICIE para aplicar.','pause'
    $revLines += 'echo.','echo Reverter concluido. REINICIE.','pause'

    $fixLines -join "`r`n" | Out-File $fixPath -Encoding ASCII
    $revLines -join "`r`n" | Out-File $rev     -Encoding ASCII
    Write-Host "FIX:    $fixPath  ($($items.Count) acoes)" -ForegroundColor Green
    Write-Host "REVERT: $rev" -ForegroundColor Green
}

# ============================================================================
# BLOATWARE REMOVAL
# ============================================================================
function Invoke-BloatRemoval {
    $winget = Get-Command winget -EA SilentlyContinue
    if (-not $winget) { Write-Host "winget nao encontrado. Instale via Microsoft Store (App Installer)." -ForegroundColor Red; return }
    $bloat = @(
        'Microsoft.BingNews','Microsoft.BingWeather','Microsoft.GetHelp','Microsoft.Getstarted',
        'Microsoft.MicrosoftOfficeHub','Microsoft.MicrosoftSolitaireCollection','Microsoft.People',
        'Microsoft.SkypeApp','Microsoft.WindowsFeedbackHub','Microsoft.WindowsMaps','Microsoft.YourPhone',
        'Microsoft.ZuneMusic','Microsoft.ZuneVideo','Clipchamp.Clipchamp','Microsoft.Todos',
        'MicrosoftCorporationII.MicrosoftFamily','MicrosoftTeams','king.com.CandyCrushSaga',
        'Microsoft.OutlookForWindows','Microsoft.549981C3F5F10' # Cortana
    )
    Write-Host "`nBloatware detectado (winget list):" -ForegroundColor Yellow
    $installed = @()
    foreach ($b in $bloat) {
        $r = winget list --id $b --exact 2>$null | Out-String
        if ($r -match $b) { $installed += $b; Write-Host "  * $b" -ForegroundColor DarkYellow }
    }
    if ($installed.Count -eq 0) { Write-Host "  Nenhum encontrado." -ForegroundColor Green; return }
    Write-Host "`nRemover $($installed.Count) itens? [Y/N]: " -NoNewline -ForegroundColor Cyan
    if ((Read-Host) -notmatch '^[Yy]') { return }
    foreach ($b in $installed) {
        Write-Host "Removendo $b..." -ForegroundColor Gray
        winget uninstall --id $b --exact --silent --accept-source-agreements 2>&1 | Out-Null
    }
    Write-Host "Concluido." -ForegroundColor Green
}

# ============================================================================
# WATCH MODE
# ============================================================================
function Start-WatchMode {
    param([int]$Minutes)
    $prev = $null
    while ($true) {
        Clear-Host
        Invoke-Audit
        $stats = Render-Console
        if ($prev) {
            $diff = Compare-Object $prev.findings $findings -Property Title,Severity
            if ($diff) {
                Write-Host "`n--- DIFF desde ultima verificacao ---" -ForegroundColor Magenta
                $diff | ForEach-Object { Write-Host "  $($_.SideIndicator) [$($_.Severity)] $($_.Title)" -ForegroundColor Magenta }
            }
        }
        $prev = [pscustomobject]@{findings=$findings.ToArray()}
        if ($OutputJson) { Render-Json -path $OutputJson -stats $stats }
        Write-Host "`nProxima verificacao em $Minutes min. Ctrl+C para sair." -ForegroundColor DarkGray
        Start-Sleep -Seconds ($Minutes*60)
    }
}

# ============================================================================
# MAIN
# ============================================================================
if ($Watch -gt 0) { Start-WatchMode -Minutes $Watch; exit }
if ($DeepClean) { Invoke-DeepClean; exit }

# ============================================================================
# COMPARE MODE
# ============================================================================
function Compare-Audits {
    param($BeforePath, $AfterPath)
    $b = Get-Content $BeforePath -Raw | ConvertFrom-Json
    $a = Get-Content $AfterPath  -Raw | ConvertFrom-Json
    if ($b -is [array]) { $b = $b[0] }
    if ($a -is [array]) { $a = $a[-1] }

    Clear-Host
    $line = ('=' * 92)
    Write-Host $line -ForegroundColor Cyan
    Write-Host "   COMPARATIVO ANTES vs DEPOIS" -ForegroundColor Cyan
    Write-Host "   Antes:  $($b.timestamp.Substring(0,16))  -  Score $($b.score.Score)/100" -ForegroundColor Gray
    Write-Host "   Depois: $($a.timestamp.Substring(0,16))  -  Score $($a.score.Score)/100" -ForegroundColor Gray
    Write-Host $line -ForegroundColor Cyan

    # Score delta
    $delta = $a.score.Score - $b.score.Score
    $deltaColor = if ($delta -gt 0) {'Green'} elseif ($delta -lt 0) {'Red'} else {'Yellow'}
    $sign = if ($delta -ge 0) {'+'} else {''}
    Write-Host ""
    Write-Host ("  SCORE DELTA: $sign$delta pontos") -ForegroundColor $deltaColor
    Write-Host ""

    # Tabela por finding
    Write-Host ("  {0,-12} {1,-14} {2,-50} {3,-10}" -f 'CATEGORIA','SEVERIDADE','ACHADO','STATUS') -ForegroundColor White
    Write-Host ('-' * 92) -ForegroundColor DarkGray

    $allTitles = @($b.findings + $a.findings | ForEach-Object { "$($_.Category)||$($_.Title)" } | Select-Object -Unique)
    $fixed = 0; $regressed = 0; $unchanged = 0; $still = 0

    foreach ($key in ($allTitles | Sort-Object)) {
        $cat, $title = $key -split '\|\|', 2
        $bf = $b.findings | Where-Object { $_.Category -eq $cat -and $_.Title -eq $title } | Select-Object -First 1
        $af = $a.findings | Where-Object { $_.Category -eq $cat -and $_.Title -eq $title } | Select-Object -First 1

        $bSev = if ($bf) { $bf.Severity } else { '-' }
        $aSev = if ($af) { $af.Severity } else { '-' }
        $sev = if ($af) { $af.Severity } else { $bSev }

        $status = ''; $color = 'Gray'
        if ($bSev -ne 'OK' -and $bSev -ne '-' -and ($aSev -eq 'OK' -or $aSev -eq '-')) {
            $status = 'CORRIGIDO'; $color = 'Green'; $fixed++
        } elseif (($bSev -eq 'OK' -or $bSev -eq '-') -and $aSev -ne 'OK' -and $aSev -ne '-') {
            $status = 'REGREDIU';  $color = 'Red'; $regressed++
        } elseif ($bSev -eq $aSev -and $bSev -ne 'OK') {
            $status = 'PERSISTE';  $color = 'Yellow'; $still++
        } elseif ($bSev -eq $aSev) {
            $status = 'IGUAL';     $color = 'DarkGray'; $unchanged++
        } else {
            $status = "$bSev->$aSev"; $color = 'Cyan'
        }

        $titleShort = if ($title.Length -gt 50) { $title.Substring(0,47) + '...' } else { $title }
        Write-Host ("  {0,-12} {1,-14} {2,-50} " -f $cat, $sev, $titleShort) -NoNewline
        Write-Host ("{0,-10}" -f $status) -ForegroundColor $color
    }

    Write-Host ('-' * 92) -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  RESUMO:" -ForegroundColor White
    Write-Host "    Corrigidos: $fixed" -ForegroundColor Green
    Write-Host "    Persistem:  $still"   -ForegroundColor Yellow
    Write-Host "    Regrediram: $regressed" -ForegroundColor Red
    Write-Host "    Iguais:     $unchanged" -ForegroundColor DarkGray
    Write-Host ""

    # HTML comparativo
    $htmlPath = ".\audit-compare-$(Get-Date -Format 'yyyyMMdd-HHmm').html"
    $rows = foreach ($key in ($allTitles | Sort-Object)) {
        $cat, $title = $key -split '\|\|', 2
        $bf = $b.findings | Where-Object { $_.Category -eq $cat -and $_.Title -eq $title } | Select-Object -First 1
        $af = $a.findings | Where-Object { $_.Category -eq $cat -and $_.Title -eq $title } | Select-Object -First 1
        $bSev = if ($bf) { $bf.Severity } else { '-' }
        $aSev = if ($af) { $af.Severity } else { '-' }
        $status='';$cls='neutral'
        if ($bSev -ne 'OK' -and $bSev -ne '-' -and ($aSev -eq 'OK' -or $aSev -eq '-')) { $status='CORRIGIDO'; $cls='fixed' }
        elseif (($bSev -eq 'OK' -or $bSev -eq '-') -and $aSev -ne 'OK' -and $aSev -ne '-') { $status='REGREDIU'; $cls='regress' }
        elseif ($bSev -eq $aSev -and $bSev -ne 'OK') { $status='PERSISTE'; $cls='persist' }
        else { $status='IGUAL'; $cls='neutral' }
        "<tr class='$cls'><td>$cat</td><td>$([System.Web.HttpUtility]::HtmlEncode($title))</td><td>$bSev</td><td>$aSev</td><td><strong>$status</strong></td></tr>"
    }
    Add-Type -AssemblyName System.Web -EA SilentlyContinue
    @"
<!DOCTYPE html><html><head><meta charset="utf-8"><title>Audit Compare</title><style>
body{font-family:Segoe UI,system-ui;background:#0d1117;color:#c9d1d9;margin:0;padding:20px}
h1{color:#58a6ff}.score{font-size:32px;font-weight:bold}.good{color:#3fb950}.bad{color:#f85149}
table{width:100%;border-collapse:collapse;background:#161b22;border-radius:8px;overflow:hidden;margin-top:20px}
th{background:#21262d;padding:12px;text-align:left}td{padding:10px;border-bottom:1px solid #30363d}
tr.fixed td{background:#0d3a1e}tr.regress td{background:#3a0d0d}tr.persist td{background:#3a2a0d}
.summary{display:flex;gap:20px;margin:20px 0}
.card{background:#161b22;padding:16px;border-radius:8px;flex:1;text-align:center}
</style></head><body>
<h1>Comparativo: Antes vs Depois</h1>
<div class="summary">
<div class="card"><div>Score Antes</div><div class="score">$($b.score.Score)/100</div></div>
<div class="card"><div>Score Depois</div><div class="score $(if($a.score.Score -ge $b.score.Score){'good'}else{'bad'})">$($a.score.Score)/100</div></div>
<div class="card"><div>Delta</div><div class="score $(if($delta -ge 0){'good'}else{'bad'})">$sign$delta</div></div>
<div class="card"><div>Corrigidos</div><div class="score good">$fixed</div></div>
<div class="card"><div>Persistem</div><div class="score" style="color:#d29922">$still</div></div>
<div class="card"><div>Regrediram</div><div class="score bad">$regressed</div></div>
</div>
<table><thead><tr><th>Categoria</th><th>Achado</th><th>Antes</th><th>Depois</th><th>Status</th></tr></thead>
<tbody>$($rows -join "`n")</tbody></table>
</body></html>
"@ | Out-File $htmlPath -Encoding UTF8
    Write-Host "  HTML comparativo: $htmlPath" -ForegroundColor Green
    Start-Process $htmlPath
}

if ($Compare) {
    $paths = $Compare -split ','
    if ($paths.Count -ne 2) { Write-Host "Use: -Compare `"before.json,after.json`"" -ForegroundColor Red; exit 1 }
    Compare-Audits -BeforePath $paths[0].Trim() -AfterPath $paths[1].Trim()
    exit
}

# ============================================================================
# AUTO MODE - fluxo completo em 1 comando
# ============================================================================
$autoDir = Join-Path $env:LOCALAPPDATA 'Win11GamingAudit'
if (-not (Test-Path $autoDir)) { New-Item $autoDir -ItemType Directory -Force | Out-Null }
$beforeJson = Join-Path $autoDir 'before.json'
$afterJson  = Join-Path $autoDir 'after.json'
$runOnceKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce'

if ($Auto -and -not $Stage2) {
    # STAGE 1: scan baseline, apply fix, schedule post-reboot
    Show-IntroBanner
    $hardware = Get-HardwareInventory
    Show-Hardware $hardware
    Write-Host "  MODO AUTO - Stage 1/2" -ForegroundColor Magenta
    Write-Host "  Profile: $Profile" -ForegroundColor Magenta
    Write-Host ""

    Invoke-Audit
    $stats = Render-Console
    Show-ScoreReveal -Score $stats.Score

    # Save baseline
    Render-Json -path $beforeJson -stats $stats
    Write-Host "  Baseline salvo em $beforeJson" -ForegroundColor Green

    Render-FixBat
    $fixBat = Get-ChildItem ".\Win11-Gaming-Fix-$Profile.bat" -EA SilentlyContinue
    if (-not $fixBat) { Write-Host "  Nada pra aplicar no profile $Profile. Abortando." -ForegroundColor Yellow; exit }

    Write-Host ""
    Write-Host "  Aplicar $($fixBat.Name) agora? Sera criado restore point." -ForegroundColor Yellow
    Write-Host "  [Y] Sim, aplicar e reiniciar automaticamente"
    Write-Host "  [M] Manual - abrir o .bat pra eu revisar/aplicar"
    Write-Host "  [N] Nao, so gerei o relatorio"
    $op = Read-Host "  Escolha"

    if ($op -match '^[Yy]') {
        # Registra RunOnce pra rodar Stage2 apos reboot
        $cmd = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Auto -Stage2 -Profile $Profile"
        Set-ItemProperty -Path $runOnceKey -Name 'Win11GamingAudit-Stage2' -Value $cmd -Force
        Write-Host "  Post-reboot scheduled. Aplicando fix..." -ForegroundColor Cyan
        Start-Process cmd.exe -ArgumentList "/c `"$($fixBat.FullName)`"" -Verb RunAs -Wait
        Write-Host ""
        Write-Host "  Reiniciando em 15 segundos. Ctrl+C pra cancelar." -ForegroundColor Yellow
        for ($i=15; $i -gt 0; $i--) { Write-Host -NoNewline "`r  $i..."; Start-Sleep 1 }
        shutdown /r /t 0
    } elseif ($op -match '^[Mm]') {
        notepad $fixBat.FullName
        Write-Host "  Rode manualmente e depois: .\Win11-Gaming-Audit.ps1 -Compare `"$beforeJson,<after.json>`"" -ForegroundColor Cyan
    }
    exit
}

if ($Stage2) {
    # STAGE 2: post-reboot, re-scan and compare
    Remove-ItemProperty -Path $runOnceKey -Name 'Win11GamingAudit-Stage2' -EA SilentlyContinue
    Show-IntroBanner
    Write-Host "  MODO AUTO - Stage 2/2 (pos-reboot)" -ForegroundColor Magenta
    Write-Host ""
    $hardware = Get-HardwareInventory
    Invoke-Audit
    $stats = Render-Console
    Render-Json -path $afterJson -stats $stats
    Write-Host ""
    Write-Host "  Comparando antes vs depois..." -ForegroundColor Cyan
    Start-Sleep 2
    Compare-Audits -BeforePath $beforeJson -AfterPath $afterJson
    Write-Host ""
    Write-Host "  Instale o Sentinel pra proteger contra Windows Update:" -ForegroundColor Yellow
    Write-Host "    .\Win11-Gaming-Sentinel.ps1 -Install" -ForegroundColor White
    exit
}

# ============================================================================
# MODO PADRAO
# ============================================================================
Show-IntroBanner

# Se rodou sem nenhum parametro relevante, mostra menu interativo
$hasAction = $GenerateFix -or $RemoveBloat -or $OutputHtml -or $OutputJson -or $WithTemps
if (-not $hasAction) {
    while ($true) {
        $choice = Show-StartupMenu
        switch ($choice) {
            '1' { break }
            '2' { & $PSCommandPath -Auto -Profile $Profile; exit }
            '3' { & $PSCommandPath -GenerateFix -Profile $Profile; exit }
            '4' {
                $p = Read-Host "  Paths dos JSONs (before.json,after.json)"
                & $PSCommandPath -Compare $p; exit
            }
            '5' {
                $sent = Join-Path $PSScriptRoot 'Win11-Gaming-Sentinel.ps1'
                if (-not (Test-Path $sent)) { $sent = '.\Win11-Gaming-Sentinel.ps1' }
                & $sent -Install; exit
            }
            'h' { Show-Help; continue }
            'H' { Show-Help; continue }
            'x' { exit }
            'X' { exit }
            default { Write-Host "  Opcao invalida." -ForegroundColor Red; Start-Sleep 1 }
        }
        if ($choice -eq '1') { break }
    }
}

$hardware = Get-HardwareInventory
if ($StreamJson) {
    Emit-Hardware -Inventory @{
        cpu         = $hardware.CPU
        gpus        = @($hardware.GPUs)
        ram_gb      = $hardware.RAM_GB
        motherboard = $hardware.Motherboard
        bios        = $hardware.BIOS
        chassis     = $hardware.Chassis
        storage     = @($hardware.Storage)
    }
} else {
    Show-Hardware $hardware
}

Invoke-Audit
$stats = Render-Console

if ($StreamJson) {
    Emit-Done -Score $stats.Score -Critical $stats.Critical -High $stats.High -Medium $stats.Medium -Total $stats.Total
    exit 0
}

Show-ScoreReveal -Score $stats.Score

if ($OutputHtml -or -not $OutputJson) { Render-Html -path $OutputHtml -stats $stats }
if ($OutputJson) { Render-Json -path $OutputJson -stats $stats }
if ($GenerateFix) { Render-FixBat }
if ($RemoveBloat) { Invoke-BloatRemoval }

Write-Host ""
Write-Host "Dica: releia os achados antes de aplicar o fix." -ForegroundColor Yellow
Write-Host "Para benchmark A/B antes/depois: .\Win11-Gaming-Benchmark.ps1" -ForegroundColor Yellow
Write-Host ""
