<#
.SYNOPSIS
    Win11 Gaming Benchmark - Mede FPS/frametimes via PresentMon e compara snapshots.

.DESCRIPTION
    Wrapper em PowerShell para PresentMon (Intel, open source). Captura um jogo
    por N segundos, extrai AVG FPS, 1% lows, 0.1% lows, frametime p99 e salva
    snapshot JSON. Dois snapshots permitem comparacao antes/depois do fix.

.PARAMETER Process
    Nome do processo do jogo (ex: cs2, VALORANT-Win64-Shipping). Obrigatorio.

.PARAMETER Duration
    Segundos de captura. Default 60.

.PARAMETER Label
    Rotulo do snapshot (ex: "before-fix", "after-fix").

.PARAMETER Compare
    Caminho de dois JSONs para comparar: -Compare "a.json,b.json".

.PARAMETER PresentMonPath
    Caminho do PresentMon-1.x-x64.exe. Default: procura no PATH e .\tools\.

.EXAMPLE
    # Preparacao: baixar PresentMon em https://github.com/GameTechDev/PresentMon/releases
    # Colocar o exe em .\tools\PresentMon.exe

    .\Win11-Gaming-Benchmark.ps1 -Process cs2 -Duration 60 -Label before-fix
    # ... aplica fix, reinicia ...
    .\Win11-Gaming-Benchmark.ps1 -Process cs2 -Duration 60 -Label after-fix
    .\Win11-Gaming-Benchmark.ps1 -Compare "benchmark-before-fix.json,benchmark-after-fix.json"
#>

#Requires -Version 5.1

param(
    [string]$Process,
    [int]$Duration = 60,
    [string]$Label = 'snapshot',
    [string]$Compare,
    [string]$PresentMonPath
)

$ErrorActionPreference = 'Stop'

# ============================================================================
# COMPARE MODE
# ============================================================================
if ($Compare) {
    $paths = $Compare -split ','
    if ($paths.Count -ne 2) { throw "Use -Compare 'a.json,b.json'" }
    $a = Get-Content $paths[0].Trim() -Raw | ConvertFrom-Json
    $b = Get-Content $paths[1].Trim() -Raw | ConvertFrom-Json

    function Fmt($v) { if ($v -is [double]) {'{0:N2}' -f $v} else {"$v"} }
    function Delta($before, $after) {
        if ($before -eq 0) { return '' }
        $d = (($after-$before)/$before)*100
        $sign = if ($d -ge 0) {'+'} else {''}
        $color = if ($d -ge 0) {'Green'} else {'Red'}
        return @{Text=("$sign{0:N1}%" -f $d); Color=$color}
    }
    Clear-Host
    Write-Host ('=' * 70) -ForegroundColor Cyan
    Write-Host "  BENCHMARK COMPARE" -ForegroundColor Cyan
    Write-Host "  A: $($a.label) ($($a.timestamp))" -ForegroundColor Gray
    Write-Host "  B: $($b.label) ($($b.timestamp))" -ForegroundColor Gray
    Write-Host ('=' * 70) -ForegroundColor Cyan
    Write-Host ""
    Write-Host ("{0,-18} {1,12} {2,12} {3,10}" -f 'Metric','A','B','Delta') -ForegroundColor White
    Write-Host ('-' * 54)
    foreach ($k in @('avgFps','p99Fps','p999Fps','minFps','maxFps','avgFrametimeMs','p99FrametimeMs')) {
        $av = $a.metrics.$k; $bv = $b.metrics.$k
        $higherIsBetter = $k -notmatch 'Frametime'
        $d = Delta $av $bv
        if ($d -is [hashtable]) {
            $color = if ($higherIsBetter) { $d.Color } else { if ($d.Color -eq 'Green') {'Red'} else {'Green'} }
            Write-Host ("{0,-18} {1,12} {2,12} " -f $k,(Fmt $av),(Fmt $bv)) -NoNewline
            Write-Host ("{0,10}" -f $d.Text) -ForegroundColor $color
        } else {
            Write-Host ("{0,-18} {1,12} {2,12}" -f $k,(Fmt $av),(Fmt $bv))
        }
    }
    Write-Host ""
    exit
}

# ============================================================================
# CAPTURE MODE
# ============================================================================
if (-not $Process) { throw "Informe -Process <nome do exe sem .exe> ou use -Compare" }

# Localiza PresentMon
if (-not $PresentMonPath) {
    $candidates = @(
        ".\tools\PresentMon.exe",
        ".\PresentMon.exe",
        "$PSScriptRoot\tools\PresentMon.exe"
    )
    $cmd = Get-Command PresentMon -EA SilentlyContinue
    if ($cmd) { $PresentMonPath = $cmd.Source }
    else { $PresentMonPath = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1 }
}
if (-not $PresentMonPath -or -not (Test-Path $PresentMonPath)) {
    Write-Host "PresentMon nao encontrado." -ForegroundColor Red
    Write-Host "Baixe em: https://github.com/GameTechDev/PresentMon/releases" -ForegroundColor Yellow
    Write-Host "Coloque o .exe em .\tools\PresentMon.exe" -ForegroundColor Yellow
    exit 1
}

# Admin check
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent() `
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { throw "Rode como Administrador (PresentMon exige)." }

# Verifica processo
$proc = Get-Process -Name $Process -EA SilentlyContinue
if (-not $proc) {
    Write-Host "Processo '$Process' nao esta rodando. Abra o jogo e tente novamente." -ForegroundColor Red
    exit 1
}

$csv = ".\presentmon-$Label-$(Get-Date -Format 'yyyyMMdd-HHmm').csv"
Write-Host "Capturando '$Process' por $Duration s..." -ForegroundColor Cyan
Write-Host "Foco no jogo agora. Jogue normal (movimento, tiros)." -ForegroundColor Yellow

$pm = Start-Process -FilePath $PresentMonPath `
    -ArgumentList "--process_name $Process.exe --output_file `"$csv`" --timed $Duration --terminate_on_proc_exit" `
    -PassThru -WindowStyle Hidden

$pm.WaitForExit()

if (-not (Test-Path $csv)) { throw "PresentMon nao gerou CSV." }

# ============================================================================
# ANALISE DO CSV
# ============================================================================
Write-Host "Analisando $csv..." -ForegroundColor Cyan
$data = Import-Csv $csv
if ($data.Count -eq 0) { throw "CSV vazio." }

# Coluna de frametime varia entre versoes de PresentMon
$ftCol = $null
foreach ($c in @('MsBetweenPresents','msBetweenPresents','FrameTime','msBetweenDisplayChange')) {
    if ($data[0].PSObject.Properties.Name -contains $c) { $ftCol = $c; break }
}
if (-not $ftCol) { throw "Coluna de frametime nao encontrada no CSV." }

$frametimes = $data | ForEach-Object { [double]$_.$ftCol } | Where-Object { $_ -gt 0 }
$sorted = $frametimes | Sort-Object
$count = $sorted.Count
if ($count -lt 10) { throw "Poucas amostras ($count). Aumente -Duration." }

function Pct($arr, $p) {
    $idx = [math]::Min([math]::Floor(($arr.Count - 1) * $p / 100), $arr.Count - 1)
    return $arr[$idx]
}

$avgFt   = ($frametimes | Measure-Object -Average).Average
$p99Ft   = Pct $sorted 99
$maxFt   = Pct $sorted 100
$minFt   = Pct $sorted 0

$avgFps  = 1000 / $avgFt
$p99Fps  = 1000 / $p99Ft       # 1% low (pior frame em 99%)
$p999Fps = 1000 / (Pct $sorted 99.9)  # 0.1% low
$minFps  = 1000 / $maxFt       # pior frame absoluto
$maxFps  = 1000 / $minFt

$result = [pscustomobject]@{
    timestamp = (Get-Date).ToString('o')
    label     = $Label
    process   = $Process
    duration  = $Duration
    samples   = $count
    metrics   = [ordered]@{
        avgFps          = [math]::Round($avgFps,2)
        p99Fps          = [math]::Round($p99Fps,2)   # "1% low"
        p999Fps         = [math]::Round($p999Fps,2)  # "0.1% low"
        minFps          = [math]::Round($minFps,2)
        maxFps          = [math]::Round($maxFps,2)
        avgFrametimeMs  = [math]::Round($avgFt,3)
        p99FrametimeMs  = [math]::Round($p99Ft,3)
    }
    csv = $csv
}

$jsonPath = ".\benchmark-$Label-$(Get-Date -Format 'yyyyMMdd-HHmm').json"
$result | ConvertTo-Json -Depth 5 | Out-File $jsonPath -Encoding UTF8

Write-Host ""
Write-Host ('=' * 60) -ForegroundColor Green
Write-Host "  RESULTADOS [$Label]  -  $Process  -  $count amostras" -ForegroundColor Green
Write-Host ('=' * 60) -ForegroundColor Green
Write-Host ("  AVG FPS        : {0,8:N1}" -f $avgFps)
Write-Host ("  1% LOW (p99)   : {0,8:N1}" -f $p99Fps) -ForegroundColor Yellow
Write-Host ("  0.1% LOW (p999): {0,8:N1}" -f $p999Fps) -ForegroundColor Red
Write-Host ("  MIN FPS        : {0,8:N1}" -f $minFps)
Write-Host ("  MAX FPS        : {0,8:N1}" -f $maxFps)
Write-Host ("  AVG frametime  : {0,8:N2} ms" -f $avgFt)
Write-Host ("  p99 frametime  : {0,8:N2} ms" -f $p99Ft)
Write-Host ('=' * 60) -ForegroundColor Green
Write-Host "  Snapshot: $jsonPath" -ForegroundColor Cyan
Write-Host ""
Write-Host "Para comparar depois do fix:" -ForegroundColor Yellow
Write-Host "  .\Win11-Gaming-Benchmark.ps1 -Compare `"$jsonPath,benchmark-after-fix-*.json`"" -ForegroundColor Gray
