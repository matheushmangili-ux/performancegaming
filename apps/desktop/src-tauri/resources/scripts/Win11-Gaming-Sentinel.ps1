<#
.SYNOPSIS
    Win11 Gaming Sentinel - Detecta regressoes de otimizacao pos-Windows-Update.

.DESCRIPTION
    Captura baseline do estado otimizado. Re-audita no logon e detecta quando
    o Windows Update silenciosamente re-habilitou MPO, HVCI, Game Bar, servicos
    Xbox, etc. Notifica via toast + log + re-aplica fix sob confirmacao.

.PARAMETER Install
    Captura baseline atual e cria tarefa agendada no logon.

.PARAMETER Check
    Roda audit, compara vs baseline, notifica drift. (Chamado pela tarefa.)

.PARAMETER Status
    Mostra ultimo check e historico de drift.

.PARAMETER Remove
    Remove tarefa agendada + arquivos do Sentinel.

.PARAMETER Reapply
    Re-aplica o Win11-Gaming-Fix-<Profile>.bat se houver drift.

.PARAMETER AuditScript
    Caminho do Win11-Gaming-Audit.ps1. Default: .\Win11-Gaming-Audit.ps1.

.PARAMETER FixScript
    Caminho do .bat de fix gerado. Default: auto-detect ultimo Win11-Gaming-Fix-*.bat.

.EXAMPLE
    # 1) Aplique o fix, reinicie, confirme que esta otimo
    # 2) Instale o sentinel para guardar este estado:
    .\Win11-Gaming-Sentinel.ps1 -Install
    # 3) A cada logon ele checa e te avisa se algo foi revertido
    .\Win11-Gaming-Sentinel.ps1 -Status
    .\Win11-Gaming-Sentinel.ps1 -Reapply
#>

#Requires -Version 5.1

param(
    [switch]$Install,
    [switch]$Check,
    [switch]$Status,
    [switch]$Remove,
    [switch]$Reapply,
    [string]$AuditScript,
    [string]$FixScript
)

$ErrorActionPreference = 'Stop'

# ============================================================================
# PATHS
# ============================================================================
$dataDir  = Join-Path $env:LOCALAPPDATA 'Win11GamingSentinel'
if (-not (Test-Path $dataDir)) { New-Item -Path $dataDir -ItemType Directory -Force | Out-Null }

$baselineFile = Join-Path $dataDir 'baseline.json'
$lastCheckFile = Join-Path $dataDir 'last-check.json'
$logFile = Join-Path $dataDir 'sentinel.log'
$taskName = 'Win11GamingSentinel'

if (-not $AuditScript) {
    $candidates = @(".\Win11-Gaming-Audit.ps1", "$PSScriptRoot\Win11-Gaming-Audit.ps1", "$env:USERPROFILE\Win11-Gaming-Audit.ps1")
    $AuditScript = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $FixScript) {
    $FixScript = Get-ChildItem -Path ".\","$env:USERPROFILE" -Filter 'Win11-Gaming-Fix-*.bat' -EA SilentlyContinue |
                 Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
}

function Write-Log {
    param($msg, $level='INFO')
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$level] $msg"
    Add-Content -Path $logFile -Value $line -Encoding UTF8
    if ($level -eq 'ERROR') { Write-Host $line -ForegroundColor Red }
    elseif ($level -eq 'WARN') { Write-Host $line -ForegroundColor Yellow }
    else { Write-Host $line -ForegroundColor Gray }
}

# ============================================================================
# TOAST NOTIFICATION (nativo Windows, sem deps)
# ============================================================================
function Show-Toast {
    param($title, $body, $tag='sentinel')
    try {
        [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        [void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
        $xml = @"
<toast><visual><binding template="ToastGeneric">
<text>$([System.Security.SecurityElement]::Escape($title))</text>
<text>$([System.Security.SecurityElement]::Escape($body))</text>
</binding></visual></toast>
"@
        $doc = New-Object Windows.Data.Xml.Dom.XmlDocument
        $doc.LoadXml($xml)
        $toast = [Windows.UI.Notifications.ToastNotification]::new($doc)
        $toast.Tag = $tag
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('Win11GamingSentinel').Show($toast)
    } catch {
        # Fallback: balão legacy
        Write-Log "Toast falhou: $_" 'WARN'
        Add-Type -AssemblyName System.Windows.Forms
        $n = New-Object System.Windows.Forms.NotifyIcon
        $n.Icon = [System.Drawing.SystemIcons]::Warning
        $n.Visible = $true
        $n.ShowBalloonTip(10000, $title, $body, 'Warning')
        Start-Sleep 11; $n.Dispose()
    }
}

# ============================================================================
# AUDIT WRAPPER
# ============================================================================
function Invoke-AuditJson {
    param($path)
    if (-not $AuditScript -or -not (Test-Path $AuditScript)) {
        throw "Win11-Gaming-Audit.ps1 nao encontrado. Use -AuditScript <caminho>."
    }
    # Roda o audit em subprocess e recupera JSON
    $tmp = [IO.Path]::GetTempFileName() + '.json'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $AuditScript -OutputJson $tmp -SkipSlow -Profile Balanced | Out-Null
    if (-not (Test-Path $tmp)) { throw "Audit nao gerou JSON em $tmp" }
    $json = Get-Content $tmp -Raw | ConvertFrom-Json
    # Audit cria array (append history). Pegar o ultimo.
    if ($json -is [array]) { $json = $json[-1] }
    Copy-Item $tmp $path -Force
    Remove-Item $tmp -Force -EA SilentlyContinue
    return $json
}

# Hash de um finding (ignora timestamp/dados voláteis)
function Get-FindingSignature {
    param($f)
    "$($f.Category)||$($f.Title)||$($f.Severity)"
}

# ============================================================================
# INSTALL
# ============================================================================
function Do-Install {
    $isAdmin = ([Security.Principal.WindowsPrincipal] `
        [Security.Principal.WindowsIdentity]::GetCurrent() `
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) { throw "Rode como Administrador para criar a tarefa agendada." }

    Write-Host "Capturando baseline do sistema otimizado..." -ForegroundColor Cyan
    $baseline = Invoke-AuditJson -path $baselineFile
    Write-Log "Baseline capturada: $($baseline.findings.Count) achados, score $($baseline.score.Score)"

    Write-Host "Criando tarefa agendada '$taskName' (on logon)..." -ForegroundColor Cyan
    $exe = "powershell.exe"
    $args = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Check"
    if ($AuditScript) { $args += " -AuditScript `"$AuditScript`"" }
    if ($FixScript)   { $args += " -FixScript `"$FixScript`"" }

    # Remove task se existir
    schtasks /delete /tn $taskName /f 2>$null | Out-Null

    $action = "$exe $args"
    schtasks /create /tn $taskName /tr $action /sc onlogon /rl highest /delay 0002:00 /f | Out-Null

    Write-Host ""
    Write-Host "Sentinel instalado." -ForegroundColor Green
    Write-Host "  Baseline: $baselineFile ($($baseline.findings.Count) achados)" -ForegroundColor Gray
    Write-Host "  Task:     $taskName (on logon, 2min delay)" -ForegroundColor Gray
    Write-Host "  Log:      $logFile" -ForegroundColor Gray
    if ($FixScript) { Write-Host "  Fix.bat:  $FixScript" -ForegroundColor Gray }
    else { Write-Host "  AVISO: Win11-Gaming-Fix-*.bat nao encontrado. -Reapply nao funcionara." -ForegroundColor Yellow }
    Write-Host ""
    Write-Host "Teste manual: .\Win11-Gaming-Sentinel.ps1 -Check" -ForegroundColor Cyan
}

# ============================================================================
# CHECK
# ============================================================================
function Do-Check {
    if (-not (Test-Path $baselineFile)) {
        Write-Log "Baseline nao existe. Rode -Install primeiro." 'ERROR'
        exit 1
    }
    $baseline = Get-Content $baselineFile -Raw | ConvertFrom-Json
    if ($baseline -is [array]) { $baseline = $baseline[-1] }

    Write-Log "Iniciando check..."
    try {
        $current = Invoke-AuditJson -path $lastCheckFile
    } catch {
        Write-Log "Audit falhou: $_" 'ERROR'
        exit 1
    }

    # Compara: achados CRITICOS/ALTOS que antes estavam OK agora voltaram
    $baselineSigs = $baseline.findings | ForEach-Object { Get-FindingSignature $_ }
    $drift = @()
    foreach ($f in $current.findings) {
        if ($f.Severity -in @('CRITICO','ALTO') -and $f.FixCmd) {
            # Mesma categoria+titulo estava OK/ausente no baseline?
            $wasOk = $baseline.findings | Where-Object {
                $_.Category -eq $f.Category -and $_.Title -eq $f.Title -and $_.Severity -eq 'OK'
            }
            $wasAbsent = -not ($baseline.findings | Where-Object {
                $_.Category -eq $f.Category -and $_.Title -eq $f.Title
            })
            if ($wasOk -or $wasAbsent) { $drift += $f }
        }
    }

    $scoreDelta = $current.score.Score - $baseline.score.Score

    Write-Log "Check concluido. Score baseline=$($baseline.score.Score) atual=$($current.score.Score) delta=$scoreDelta drift=$($drift.Count)"

    if ($drift.Count -gt 0) {
        $titles = ($drift | Select-Object -First 3 -ExpandProperty Title) -join ' | '
        $body = "$($drift.Count) otimizacoes foram revertidas. Score: $($baseline.score.Score) -> $($current.score.Score)`n$titles"
        Show-Toast -title "⚠️ Gaming Optimizations Reverted" -body $body
        Write-Log "DRIFT DETECTADO: $($drift.Count) itens" 'WARN'
        foreach ($d in $drift) {
            Write-Log "  [$($d.Severity)] $($d.Category) - $($d.Title)" 'WARN'
        }

        # Salva lista de drift para -Reapply saber o que re-aplicar
        $drift | ConvertTo-Json -Depth 5 | Out-File (Join-Path $dataDir 'drift.json') -Encoding UTF8
    } else {
        Write-Log "Sem drift. Sistema estavel."
    }

    Write-Host ""
    Write-Host "Check: $($drift.Count) drift(s), score $($current.score.Score)/100 (delta $scoreDelta)" -ForegroundColor $(if($drift.Count){'Yellow'}else{'Green'})
}

# ============================================================================
# STATUS
# ============================================================================
function Do-Status {
    Write-Host ""
    Write-Host "=== WIN11 GAMING SENTINEL STATUS ===" -ForegroundColor Cyan

    if (Test-Path $baselineFile) {
        $b = Get-Content $baselineFile -Raw | ConvertFrom-Json
        if ($b -is [array]) { $b = $b[-1] }
        Write-Host "Baseline:   $($b.timestamp)" -ForegroundColor Gray
        Write-Host "  Score:    $($b.score.Score)/100" -ForegroundColor Gray
        Write-Host "  Achados:  $($b.findings.Count)" -ForegroundColor Gray
    } else {
        Write-Host "Baseline:   (nao capturado, use -Install)" -ForegroundColor Yellow
    }

    if (Test-Path $lastCheckFile) {
        $l = Get-Content $lastCheckFile -Raw | ConvertFrom-Json
        if ($l -is [array]) { $l = $l[-1] }
        Write-Host "Ultimo check: $($l.timestamp)" -ForegroundColor Gray
        Write-Host "  Score:    $($l.score.Score)/100" -ForegroundColor Gray
    }

    $drift = Join-Path $dataDir 'drift.json'
    if (Test-Path $drift) {
        $d = Get-Content $drift -Raw | ConvertFrom-Json
        if ($d.Count -gt 0) {
            Write-Host ""
            Write-Host "DRIFT ATUAL ($($d.Count)):" -ForegroundColor Red
            foreach ($i in $d) {
                Write-Host "  [$($i.Severity)] $($i.Category) - $($i.Title)" -ForegroundColor Yellow
                if ($i.Why) { Write-Host "     $($i.Why)" -ForegroundColor DarkGray }
            }
            Write-Host ""
            Write-Host "Para re-aplicar:  .\Win11-Gaming-Sentinel.ps1 -Reapply" -ForegroundColor Cyan
        }
    }

    $task = schtasks /query /tn $taskName 2>$null
    if ($LASTEXITCODE -eq 0) { Write-Host "Tarefa:     ativa" -ForegroundColor Green }
    else { Write-Host "Tarefa:     nao instalada" -ForegroundColor Yellow }

    Write-Host "Log:        $logFile" -ForegroundColor Gray
    Write-Host ""
    if (Test-Path $logFile) {
        Write-Host "Ultimas 10 entradas do log:" -ForegroundColor Cyan
        Get-Content $logFile -Tail 10 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
    }
}

# ============================================================================
# REAPPLY
# ============================================================================
function Do-Reapply {
    $driftFile = Join-Path $dataDir 'drift.json'
    if (-not (Test-Path $driftFile)) { Write-Host "Nenhum drift detectado. Rode -Check primeiro." -ForegroundColor Yellow; return }
    $drift = Get-Content $driftFile -Raw | ConvertFrom-Json
    if ($drift.Count -eq 0) { Write-Host "Drift vazio." -ForegroundColor Green; return }

    Write-Host "Drift detectado ($($drift.Count) itens):" -ForegroundColor Yellow
    foreach ($d in $drift) { Write-Host "  - [$($d.Severity)] $($d.Title)" -ForegroundColor Yellow }

    Write-Host ""
    Write-Host "Opcoes:" -ForegroundColor Cyan
    Write-Host "  [1] Rodar $FixScript inteiro (recomendado se foi gerado recentemente)"
    Write-Host "  [2] Gerar mini-fix.bat so com os itens em drift e rodar"
    Write-Host "  [3] Cancelar"
    $op = Read-Host "Escolha"

    switch ($op) {
        '1' {
            if (-not $FixScript -or -not (Test-Path $FixScript)) {
                Write-Host "Fix script nao encontrado. Use -FixScript ou regere via Audit -GenerateFix." -ForegroundColor Red
                return
            }
            Write-Host "Executando $FixScript como admin..." -ForegroundColor Cyan
            Start-Process cmd.exe -ArgumentList "/c `"$FixScript`"" -Verb RunAs -Wait
            Write-Log "Reapply via $FixScript"
            Remove-Item $driftFile -Force -EA SilentlyContinue
        }
        '2' {
            $miniPath = Join-Path $dataDir "mini-fix-$(Get-Date -Format 'yyyyMMdd-HHmm').bat"
            $lines = @('@echo off','chcp 65001 >nul','title Sentinel Mini-Fix','',
                       'net session >nul 2>&1 || (echo Precisa admin. & pause & exit /b)','')
            foreach ($d in $drift) {
                if ($d.FixCmd) {
                    $lines += "REM [$($d.Severity)] $($d.Title)"
                    $lines += "REM $($d.Why)"
                    $lines += $d.FixCmd
                    $lines += ''
                }
            }
            $lines += 'echo Concluido. Reinicie.','pause'
            $lines -join "`r`n" | Out-File $miniPath -Encoding ASCII
            Write-Host "Mini-fix: $miniPath" -ForegroundColor Green
            Start-Process cmd.exe -ArgumentList "/c `"$miniPath`"" -Verb RunAs -Wait
            Write-Log "Reapply via mini-fix $miniPath"
            Remove-Item $driftFile -Force -EA SilentlyContinue
        }
        default { Write-Host "Cancelado." -ForegroundColor Gray }
    }
}

# ============================================================================
# REMOVE
# ============================================================================
function Do-Remove {
    schtasks /delete /tn $taskName /f 2>$null | Out-Null
    Write-Host "Tarefa $taskName removida." -ForegroundColor Green
    if (Test-Path $dataDir) {
        Write-Host "Remover dados em $dataDir tambem? [Y/N]: " -NoNewline
        if ((Read-Host) -match '^[Yy]') {
            Remove-Item $dataDir -Recurse -Force
            Write-Host "Dados removidos." -ForegroundColor Green
        }
    }
}

# ============================================================================
# MAIN
# ============================================================================
if ($Install)  { Do-Install;  exit }
if ($Check)    { Do-Check;    exit }
if ($Status)   { Do-Status;   exit }
if ($Reapply)  { Do-Reapply;  exit }
if ($Remove)   { Do-Remove;   exit }

Write-Host @"

Win11 Gaming Sentinel - uso:

  -Install    Captura baseline atual + cria tarefa agendada no logon
  -Check      Re-audita e detecta drift (chamado pela tarefa)
  -Status     Mostra baseline, ultimo check, drift atual, log
  -Reapply    Re-aplica fix se houve drift
  -Remove     Desinstala tarefa agendada + dados

Fluxo recomendado:
  1) .\Win11-Gaming-Audit.ps1 -GenerateFix -Profile Balanced
  2) Execute Win11-Gaming-Fix-Balanced.bat como admin, reinicie
  3) .\Win11-Gaming-Sentinel.ps1 -Install
  4) (seguira checando a cada logon; toast aparece se drift)
  5) Quando vier toast: .\Win11-Gaming-Sentinel.ps1 -Reapply

"@ -ForegroundColor Cyan
