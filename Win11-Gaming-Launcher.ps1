<#
.SYNOPSIS
    Win11 Gaming Launcher - Menu interativo para a suite completa.

.DESCRIPTION
    Ponto de entrada unico. Orquestra Audit, Benchmark e Sentinel atraves de
    menu numerico seguindo a jornada recomendada (diagnostico -> benchmark ->
    otimizacao -> validacao -> protecao).

.EXAMPLE
    .\Win11-Gaming-Launcher.ps1
#>

$ErrorActionPreference = 'SilentlyContinue'

# Auto-elevar
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent() `
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process -FilePath $MyInvocation.MyCommand.Path -Verb RunAs
    exit
}

# Localizar pasta de scripts
$root = if ($MyInvocation.MyCommand.Path) { Split-Path $MyInvocation.MyCommand.Path -Parent }
        else { [AppDomain]::CurrentDomain.BaseDirectory }
$audit    = Join-Path $root 'Win11-Gaming-Audit.ps1'
$bench    = Join-Path $root 'Win11-Gaming-Benchmark.ps1'
$sentinel = Join-Path $root 'Win11-Gaming-Sentinel.ps1'

if (-not (Test-Path $audit)) {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show("Scripts nao encontrados em:`n$root", "Erro", 'OK', 'Error') | Out-Null
    exit 1
}

$Host.UI.RawUI.WindowTitle = 'Win11 Gaming Suite'

function Show-Banner {
    Clear-Host
    $art = @(
        '  __        ___       _ _    ____                 _             '
        '  \ \      / (_)_ __ / / |  / ___| __ _ _ __ ___ (_)_ __   __ _ '
        "   \ \ /\ / /| | '_ \| | | | |  _ / _`` | '_ `` _ \| | '_ \ / _`` |"
        '    \ V  V / | | | | | | | | |_| | (_| | | | | | | | | | | (_| |'
        '     \_/\_/  |_|_| |_|_|_|  \____|\__,_|_| |_| |_|_|_| |_|\__, |'
        '                                                          |___/ '
        '                     S U I T E   L A U N C H E R                '
    )
    $palette = @('Cyan','Blue','Magenta','Red','Yellow','Green','DarkCyan')
    for ($i=0; $i -lt $art.Count; $i++) {
        Write-Host $art[$i] -ForegroundColor $palette[$i % $palette.Count]
        Start-Sleep -Milliseconds 35
    }
    Write-Host ''
}

function Show-Menu {
    while ($true) {
        Show-Banner
        Write-Host '  MENU PRINCIPAL (siga a ordem numerica pra jornada completa)' -ForegroundColor White
        Write-Host ('  ' + ('=' * 66)) -ForegroundColor DarkGray
        Write-Host ''
        Write-Host '  -- DIAGNOSTICO --' -ForegroundColor Cyan
        Write-Host '    [1] SCAN read-only         ver erros sem modificar nada' -ForegroundColor White
        Write-Host ''
        Write-Host '  -- BENCHMARK (opcional, baseline ANTES do fix) --' -ForegroundColor Cyan
        Write-Host '    [2] Benchmark FPS ANTES    mede 1% lows, avg, frametime' -ForegroundColor White
        Write-Host ''
        Write-Host '  -- OTIMIZACAO --' -ForegroundColor Cyan
        Write-Host '    [3] MODO AUTO              scan + fix + reboot + compare (RECOMENDADO)' -ForegroundColor Green
        Write-Host '    [4] Gerar FIX.BAT manual   so gera, voce revisa e aplica depois' -ForegroundColor White
        Write-Host '    [5] Aplicar FIX.BAT        roda o ultimo .bat gerado' -ForegroundColor White
        Write-Host ''
        Write-Host '  -- VALIDACAO --' -ForegroundColor Cyan
        Write-Host '    [6] Benchmark FPS DEPOIS   mede apos aplicar, auto-compara com [2]' -ForegroundColor White
        Write-Host '    [7] Comparar audits JSON   tabela antes x depois por categoria' -ForegroundColor White
        Write-Host ''
        Write-Host '  -- PROTECAO --' -ForegroundColor Cyan
        Write-Host '    [8] Instalar SENTINEL      detecta drift pos Windows Update' -ForegroundColor Magenta
        Write-Host '    [9] Status do Sentinel     baseline, ultimo check, drift' -ForegroundColor White
        Write-Host ''
        Write-Host '  -- EXTRAS --' -ForegroundColor Cyan
        Write-Host '    [0] Bloatware removal + DeepClean (temp/cache/DNS)' -ForegroundColor White
        Write-Host ''
        Write-Host '  -- EMERGENCIA / OUTROS --' -ForegroundColor DarkYellow
        Write-Host '    [R] REVERTER mudancas      usa Win11-Gaming-Revert.bat' -ForegroundColor Yellow
        Write-Host '    [H] Ajuda detalhada' -ForegroundColor DarkGray
        Write-Host '    [X] Sair' -ForegroundColor DarkGray
        Write-Host ''
        $c = (Read-Host '  Escolha').ToUpper()

        switch ($c) {
            '1' { & powershell -NoProfile -ExecutionPolicy Bypass -File $audit; Pause-Continue }
            '2' {
                Write-Host ''
                Write-Host '  PRE-REQUISITO: PresentMon em .\tools\PresentMon.exe' -ForegroundColor Yellow
                Write-Host '  Baixe: https://github.com/GameTechDev/PresentMon/releases' -ForegroundColor Cyan
                Write-Host ''
                $proc = Read-Host '  Nome do processo do jogo (ex: cs2, VALORANT-Win64-Shipping)'
                if ($proc) {
                    & powershell -NoProfile -ExecutionPolicy Bypass -File $bench -Process $proc -Duration 60 -Label 'before'
                }
                Pause-Continue
            }
            '3' {
                $p = Select-Profile
                & powershell -NoProfile -ExecutionPolicy Bypass -File $audit -Auto -Profile $p
                Pause-Continue
            }
            '4' {
                $p = Select-Profile
                & powershell -NoProfile -ExecutionPolicy Bypass -File $audit -GenerateFix -Profile $p
                Write-Host ''
                Write-Host '  .bat gerado em:' -ForegroundColor Cyan
                Get-ChildItem $root -Filter "Win11-Gaming-Fix-$p.bat" | ForEach-Object { Write-Host "    $($_.FullName)" -ForegroundColor White }
                Write-Host '  Use opcao [5] para aplicar.' -ForegroundColor Cyan
                Pause-Continue
            }
            '5' {
                $bat = Get-ChildItem $root -Filter 'Win11-Gaming-Fix-*.bat' -EA SilentlyContinue |
                       Sort-Object LastWriteTime -Descending | Select-Object -First 1
                if ($bat) {
                    Write-Host "  Aplicando $($bat.Name)..." -ForegroundColor Cyan
                    Start-Process cmd.exe -ArgumentList "/c `"$($bat.FullName)`"" -Verb RunAs -Wait
                    Write-Host '  Concluido. REINICIE e depois use [6] e [7].' -ForegroundColor Green
                } else {
                    Write-Host '  Nenhum Fix.bat encontrado. Use [4] primeiro.' -ForegroundColor Yellow
                }
                Pause-Continue
            }
            '6' {
                $proc = Read-Host '  Nome do processo do jogo'
                if ($proc) {
                    & powershell -NoProfile -ExecutionPolicy Bypass -File $bench -Process $proc -Duration 60 -Label 'after'
                    Write-Host ''
                    Write-Host '  Comparar com baseline [2]? [Y/N]: ' -NoNewline -ForegroundColor Cyan
                    if ((Read-Host) -match '^[Yy]') {
                        $before = Get-ChildItem $root -Filter 'benchmark-before-*.json' | Sort-Object LastWriteTime -Desc | Select-Object -First 1
                        $after  = Get-ChildItem $root -Filter 'benchmark-after-*.json'  | Sort-Object LastWriteTime -Desc | Select-Object -First 1
                        if ($before -and $after) {
                            & powershell -NoProfile -ExecutionPolicy Bypass -File $bench -Compare "$($before.FullName),$($after.FullName)"
                        }
                    }
                }
                Pause-Continue
            }
            '7' {
                Write-Host ''
                Write-Host '  Comparar 2 audits (JSONs do scan)' -ForegroundColor Cyan
                $a = Read-Host '  Caminho do JSON ANTES'
                $b = Read-Host '  Caminho do JSON DEPOIS'
                & powershell -NoProfile -ExecutionPolicy Bypass -File $audit -Compare "$a,$b"
                Pause-Continue
            }
            '8' { & powershell -NoProfile -ExecutionPolicy Bypass -File $sentinel -Install; Pause-Continue }
            '9' { & powershell -NoProfile -ExecutionPolicy Bypass -File $sentinel -Status; Pause-Continue }
            '0' {
                Write-Host ''
                Write-Host '  [A] Remover bloatware (winget uninstall)' -ForegroundColor White
                Write-Host '  [B] DeepClean (temp, prefetch, DNS, shader cache)' -ForegroundColor White
                Write-Host '  [C] Ambos' -ForegroundColor White
                switch ((Read-Host '  Qual?').ToUpper()) {
                    'A' { & powershell -NoProfile -ExecutionPolicy Bypass -File $audit -RemoveBloat }
                    'B' { & powershell -NoProfile -ExecutionPolicy Bypass -File $audit -DeepClean }
                    'C' {
                        & powershell -NoProfile -ExecutionPolicy Bypass -File $audit -DeepClean
                        & powershell -NoProfile -ExecutionPolicy Bypass -File $audit -RemoveBloat
                    }
                }
                Pause-Continue
            }
            'R' {
                $rev = Join-Path $root 'Win11-Gaming-Revert.bat'
                if (Test-Path $rev) {
                    Write-Host ''
                    Write-Host '  ATENCAO: reverte TODAS as otimizacoes aplicadas.' -ForegroundColor Red
                    if ((Read-Host '  Confirma? [Y/N]') -match '^[Yy]') {
                        Start-Process cmd.exe -ArgumentList "/c `"$rev`"" -Verb RunAs -Wait
                        Write-Host '  REINICIE.' -ForegroundColor Green
                    }
                } else {
                    Write-Host '  Revert.bat nao encontrado. Use rstrui.exe (restore point).' -ForegroundColor Yellow
                }
                Pause-Continue
            }
            'H' { Show-Help }
            'X' { exit }
            default { Write-Host '  Opcao invalida.' -ForegroundColor Red; Start-Sleep 1 }
        }
    }
}

function Select-Profile {
    Write-Host ''
    Write-Host '  Profile?' -ForegroundColor Cyan
    Write-Host '    [1] Safe         so criticos (minimo risco)' -ForegroundColor Gray
    Write-Host '    [2] Balanced     criticos + altos (RECOMENDADO)' -ForegroundColor Green
    Write-Host '    [3] Competitive  tudo, incluindo VBS off (pro)' -ForegroundColor Yellow
    switch (Read-Host '  Escolha') {
        '1' { return 'Safe' }
        '3' { return 'Competitive' }
        default { return 'Balanced' }
    }
}

function Pause-Continue {
    Write-Host ''
    Write-Host '  Pressione qualquer tecla para voltar ao menu...' -ForegroundColor DarkGray
    $null = [Console]::ReadKey($true)
}

function Show-Help {
    Clear-Host
    Write-Host ''
    Write-Host '  WIN11 GAMING SUITE - AJUDA' -ForegroundColor Cyan
    Write-Host ('  ' + ('=' * 66)) -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  JORNADA RECOMENDADA (primeira vez):' -ForegroundColor White
    Write-Host '    [1] SCAN                   ver score atual e entender problemas'
    Write-Host '    [2] Benchmark ANTES        opcional, mede FPS real de baseline'
    Write-Host '    [3] MODO AUTO              aplica tudo automaticamente'
    Write-Host '    [6] Benchmark DEPOIS       confirma ganho com numeros'
    Write-Host '    [8] SENTINEL               blinda contra Windows Update'
    Write-Host ''
    Write-Host '  JORNADA AVANCADA:' -ForegroundColor White
    Write-Host '    [1] SCAN -> [4] Gerar -> revisar no notepad -> [5] Aplicar -> [6]/[7]'
    Write-Host ''
    Write-Host '  PROFILES:' -ForegroundColor White
    Write-Host '    Safe         = so criticos (MPO, TRIM) - risco minimo'
    Write-Host '    Balanced     = criticos + altos - recomendado default'
    Write-Host '    Competitive  = tudo, incluindo VBS off - pro gaming'
    Write-Host ''
    Write-Host '  SE ALGO QUEBRAR:' -ForegroundColor Yellow
    Write-Host '    [R] Reverter mudancas (usa Win11-Gaming-Revert.bat)'
    Write-Host '    Alternativa: tecla Win -> "restore" -> escolha ponto anterior'
    Write-Host ''
    Write-Host '  SEGURANCA:' -ForegroundColor White
    Write-Host '    - Restore point criado automaticamente antes de qualquer fix'
    Write-Host '    - Cada fix gera revert especifico em paralelo'
    Write-Host '    - Scan read-only [1] NAO modifica nada (use sempre primeiro)'
    Write-Host ''
    Pause-Continue
}

Show-Menu
