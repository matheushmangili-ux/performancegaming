<#
.SYNOPSIS
    Win11 Gaming Suite - Instalador one-liner.

.DESCRIPTION
    Baixa os 3 scripts (Audit, Benchmark, Sentinel) para %USERPROFILE%\Win11GamingSuite,
    cria atalhos no Desktop/Start e apresenta menu interativo.

.EXAMPLE
    # Instalacao direta (PowerShell como admin):
    irm https://matheushmangili-ux.github.io/performancegaming/install.ps1 | iex

    # Ou apos clonar:
    .\Install-Win11GamingSuite.ps1
    .\Install-Win11GamingSuite.ps1 -Menu
    .\Install-Win11GamingSuite.ps1 -Uninstall
#>

param(
    [switch]$Menu,
    [switch]$Uninstall,
    [string]$BaseUrl = 'https://raw.githubusercontent.com/matheushmangili-ux/performancegaming/main',
    [string]$LocalSource  # alternativa: pasta local com os .ps1
)

$ErrorActionPreference = 'Stop'

$installDir = Join-Path $env:USERPROFILE 'Win11GamingSuite'
$files = @('Win11-Gaming-Audit.ps1','Win11-Gaming-Benchmark.ps1','Win11-Gaming-Sentinel.ps1')

# ============================================================================
# ANIMACAO
# ============================================================================
function Show-Banner {
    Clear-Host
    $art = @(
        '  __        ___       _ _    ____                 _             '
        '  \ \      / (_)_ __ / / |  / ___| __ _ _ __ ___ (_)_ __   __ _ '
        '   \ \ /\ / /| | `_ \| | | | |  _ / _` | `_ ` _ \| | `_ \ / _` |'
        '    \ V  V / | | | | | | | | |_| | (_| | | | | | | | | | | (_| |'
        '     \_/\_/  |_|_| |_|_|_|  \____|\__,_|_| |_| |_|_|_| |_|\__, |'
        '                                                          |___/ '
        '                  S U I T E   I N S T A L L E R                 '
    )
    $palette = @('Cyan','Blue','Magenta','Red','Yellow','Green','DarkCyan')
    for ($i=0; $i -lt $art.Count; $i++) {
        Write-Host $art[$i] -ForegroundColor $palette[$i % $palette.Count]
        Start-Sleep -Milliseconds 55
    }
    Write-Host ""
}

function Spin {
    param([string]$Label, [scriptblock]$Action)
    $frames = @('|','/','-','\')
    $job = Start-Job -ScriptBlock $Action
    $i = 0
    while ($job.State -eq 'Running') {
        Write-Host -NoNewline ("`r  $($frames[$i % 4])  $Label" + (' ' * 20)) -ForegroundColor Cyan
        Start-Sleep -Milliseconds 80; $i++
    }
    $r = Receive-Job $job; Remove-Job $job -Force
    Write-Host -NoNewline ("`r  [OK] $Label" + (' ' * 30)) -ForegroundColor Green
    Write-Host ""
    return $r
}

# ============================================================================
# UNINSTALL
# ============================================================================
function Do-Uninstall {
    Show-Banner
    Write-Host "  Desinstalando..." -ForegroundColor Yellow
    # Sentinel task
    schtasks /delete /tn 'Win11GamingSentinel' /f 2>$null | Out-Null
    # Pasta
    if (Test-Path $installDir) {
        Write-Host "  Remover $installDir ? [Y/N]: " -NoNewline
        if ((Read-Host) -match '^[Yy]') {
            Remove-Item $installDir -Recurse -Force
            Write-Host "  Pasta removida." -ForegroundColor Green
        }
    }
    # Atalhos
    $desktop = [Environment]::GetFolderPath('Desktop')
    Get-ChildItem $desktop -Filter 'Win11 Gaming*.lnk' -EA SilentlyContinue | Remove-Item -Force
    # Dados Sentinel
    $data = Join-Path $env:LOCALAPPDATA 'Win11GamingSentinel'
    if (Test-Path $data) {
        Write-Host "  Remover dados do Sentinel em $data ? [Y/N]: " -NoNewline
        if ((Read-Host) -match '^[Yy]') { Remove-Item $data -Recurse -Force }
    }
    Write-Host "  Concluido." -ForegroundColor Green
    exit
}
if ($Uninstall) { Do-Uninstall }

# ============================================================================
# DOWNLOAD
# ============================================================================
function Download-Files {
    if (-not (Test-Path $installDir)) {
        New-Item -Path $installDir -ItemType Directory -Force | Out-Null
    }
    foreach ($f in $files) {
        $dest = Join-Path $installDir $f
        Spin -Label "Obtendo $f..." -Action {
            param($url, $dst, $src)
            if ($src) {
                $srcFile = Join-Path $src (Split-Path $dst -Leaf)
                if (Test-Path $srcFile) { Copy-Item $srcFile $dst -Force; return }
                else { throw "Arquivo local nao encontrado: $srcFile" }
            }
            try {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                Invoke-WebRequest -Uri $url -OutFile $dst -UseBasicParsing
            } catch { throw "Falha download $url : $_" }
        }.GetNewClosure() `
          -ArgumentList @("$BaseUrl/$f", $dest, $LocalSource) | Out-Null

        # Actually Start-Job não suporta -ArgumentList do jeito acima - simplifico:
    }
}

# Versao mais direta (sem jobs complexos pra download)
function Get-Files {
    if (-not (Test-Path $installDir)) { New-Item -Path $installDir -ItemType Directory -Force | Out-Null }
    foreach ($f in $files) {
        $dest = Join-Path $installDir $f
        Write-Host -NoNewline "  -> $f " -ForegroundColor Cyan
        try {
            if ($LocalSource) {
                $src = Join-Path $LocalSource $f
                if (-not (Test-Path $src)) { throw "Nao existe: $src" }
                Copy-Item $src $dest -Force
            } else {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                Invoke-WebRequest -Uri "$BaseUrl/$f" -OutFile $dest -UseBasicParsing -TimeoutSec 30
            }
            Write-Host "[OK]" -ForegroundColor Green
        } catch {
            Write-Host "[FALHOU]" -ForegroundColor Red
            Write-Host "     $_" -ForegroundColor DarkRed
            throw
        }
    }
}

# ============================================================================
# SHORTCUTS
# ============================================================================
function New-Shortcuts {
    $desktop = [Environment]::GetFolderPath('Desktop')
    $shell = New-Object -ComObject WScript.Shell

    $shortcuts = @(
        @{Name='Win11 Gaming Audit.lnk'; Target=(Join-Path $installDir 'Win11-Gaming-Audit.ps1'); Args='-GenerateFix'}
        @{Name='Win11 Gaming Sentinel.lnk'; Target=(Join-Path $installDir 'Win11-Gaming-Sentinel.ps1'); Args='-Status'}
    )
    foreach ($s in $shortcuts) {
        $lnk = $shell.CreateShortcut((Join-Path $desktop $s.Name))
        $lnk.TargetPath = 'powershell.exe'
        $lnk.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$($s.Target)`" $($s.Args)"
        $lnk.WorkingDirectory = $installDir
        $lnk.IconLocation = 'powershell.exe,0'
        $lnk.Save()
    }
    Write-Host "  Atalhos criados em $desktop" -ForegroundColor Green
}

# ============================================================================
# MENU
# ============================================================================
function Show-Menu {
    while ($true) {
        Clear-Host
        Show-Banner
        Write-Host "  Suite em: $installDir" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  [1] Rodar Audit (scan + HTML)" -ForegroundColor White
        Write-Host "  [2] Rodar Audit + gerar Fix.bat personalizado" -ForegroundColor White
        Write-Host "  [3] Aplicar ultimo Fix.bat gerado" -ForegroundColor White
        Write-Host "  [4] Benchmark (PresentMon - requer exe em tools/)" -ForegroundColor White
        Write-Host "  [5] Instalar Sentinel (detecta drift pos-update)" -ForegroundColor White
        Write-Host "  [6] Status do Sentinel" -ForegroundColor White
        Write-Host "  [7] Remover bloatware (winget)" -ForegroundColor White
        Write-Host "  [8] Modo Watch (re-audit a cada 30min)" -ForegroundColor White
        Write-Host "  [9] Abrir pasta de instalacao" -ForegroundColor White
        Write-Host "  [X] Sair" -ForegroundColor DarkGray
        Write-Host ""
        $op = Read-Host "  Escolha"

        $audit = Join-Path $installDir 'Win11-Gaming-Audit.ps1'
        $bench = Join-Path $installDir 'Win11-Gaming-Benchmark.ps1'
        $sent  = Join-Path $installDir 'Win11-Gaming-Sentinel.ps1'

        switch ($op) {
            '1' { & powershell -NoProfile -ExecutionPolicy Bypass -File $audit; Pause }
            '2' {
                Write-Host "  Profile? [1=Safe 2=Balanced 3=Competitive]: " -NoNewline
                $p = switch (Read-Host) {'1'{'Safe'}'3'{'Competitive'}default{'Balanced'}}
                & powershell -NoProfile -ExecutionPolicy Bypass -File $audit -GenerateFix -Profile $p
                Pause
            }
            '3' {
                $bat = Get-ChildItem $installDir -Filter 'Win11-Gaming-Fix-*.bat' -EA SilentlyContinue |
                       Sort-Object LastWriteTime -Descending | Select-Object -First 1
                if ($bat) { Start-Process cmd.exe -ArgumentList "/c `"$($bat.FullName)`"" -Verb RunAs -Wait }
                else { Write-Host "  Nenhum Fix.bat. Gere primeiro (opcao 2)." -ForegroundColor Yellow; Pause }
            }
            '4' {
                $proc = Read-Host "  Nome do processo (ex: cs2, VALORANT-Win64-Shipping)"
                & powershell -NoProfile -ExecutionPolicy Bypass -File $bench -Process $proc -Duration 60; Pause
            }
            '5' { & powershell -NoProfile -ExecutionPolicy Bypass -File $sent -Install; Pause }
            '6' { & powershell -NoProfile -ExecutionPolicy Bypass -File $sent -Status; Pause }
            '7' { & powershell -NoProfile -ExecutionPolicy Bypass -File $audit -RemoveBloat; Pause }
            '8' { & powershell -NoProfile -ExecutionPolicy Bypass -File $audit -Watch 30 }
            '9' { Start-Process explorer.exe $installDir }
            { $_ -match '^[xX]$' } { exit }
            default { Write-Host "  Opcao invalida." -ForegroundColor Red; Start-Sleep 1 }
        }
    }
}

# ============================================================================
# MAIN
# ============================================================================
if ($Menu) {
    if (-not (Test-Path (Join-Path $installDir 'Win11-Gaming-Audit.ps1'))) {
        Write-Host "Suite nao instalada. Rode sem -Menu primeiro." -ForegroundColor Red; exit
    }
    Show-Menu; exit
}

Show-Banner
Write-Host "  Destino: $installDir" -ForegroundColor Gray
Write-Host "  Origem:  $(if($LocalSource){$LocalSource}else{$BaseUrl})" -ForegroundColor Gray
Write-Host ""

# Check admin (recomendado pra atalhos + Sentinel depois)
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent() `
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "  AVISO: nao esta como Admin. Instalacao prossegue, mas Audit/Sentinel exigem admin na execucao." -ForegroundColor Yellow
    Write-Host ""
}

Write-Host "  Baixando scripts..." -ForegroundColor Cyan
Get-Files
Write-Host ""
Write-Host "  Criando atalhos..." -ForegroundColor Cyan
New-Shortcuts
Write-Host ""
Write-Host "  Instalacao concluida." -ForegroundColor Green
Write-Host ""
Write-Host "  Proximos passos:" -ForegroundColor Cyan
Write-Host "    1) Clique no atalho 'Win11 Gaming Audit' (gera scan + fix.bat)"
Write-Host "    2) Aplique o .bat gerado em $installDir"
Write-Host "    3) Reinicie"
Write-Host "    4) Instale o Sentinel: atalho 'Win11 Gaming Sentinel' ou"
Write-Host "       powershell -File `"$(Join-Path $installDir 'Win11-Gaming-Sentinel.ps1')`" -Install"
Write-Host ""
Write-Host "  Menu interativo:" -ForegroundColor Cyan
Write-Host "    powershell -File `"$PSCommandPath`" -Menu" -ForegroundColor White
Write-Host ""
