<#
.SYNOPSIS
    Executa um lote de fixes em modo streaming.

.DESCRIPTION
    Consome fixes.json (array de { id, title, command, severity }),
    cria um System Restore Point, e executa cada comando via cmd.exe /c.
    Emite eventos JSONL no stdout compatíveis com o orchestrator Rust.
#>

#Requires -Version 5.1

param(
    [Parameter(Mandatory)][string]$FixesJson,
    [switch]$StreamJson,
    [switch]$SkipRestorePoint,
    [ValidateSet('fix','revert')] [string]$Mode = 'fix'
)

if ($StreamJson) {
    $helper = Join-Path $PSScriptRoot 'lib\json-emit.ps1'
    if (Test-Path $helper) { . $helper } else {
        Write-Error "Missing lib/json-emit.ps1"
        exit 2
    }
}

function Write-EventSafe {
    param([string]$Type, [hashtable]$Data)
    if ($StreamJson) { Emit-Event -Type $Type -Rest $Data }
}

# ────────────────────────────────────────────────────────────────────────
# Admin check
# ────────────────────────────────────────────────────────────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent() `
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-EventSafe -Type 'error' -Data @{
        where = 'admin-check'
        message = 'Administrator privileges required. Relaunch ClockReaper as admin.'
    }
    exit 3
}

# ────────────────────────────────────────────────────────────────────────
# Load fixes
# ────────────────────────────────────────────────────────────────────────
if (-not (Test-Path $FixesJson)) {
    Write-EventSafe -Type 'error' -Data @{ where = 'load'; message = "Not found: $FixesJson" }
    exit 4
}

try {
    $fixes = Get-Content $FixesJson -Raw | ConvertFrom-Json
} catch {
    Write-EventSafe -Type 'error' -Data @{ where = 'parse'; message = $_.Exception.Message }
    exit 5
}

if (-not $fixes -or $fixes.Count -eq 0) {
    Write-EventSafe -Type 'error' -Data @{ where = 'load'; message = 'No fixes to apply' }
    exit 6
}

# ────────────────────────────────────────────────────────────────────────
# Start
# ────────────────────────────────────────────────────────────────────────
Write-EventSafe -Type 'start' -Data @{
    mode        = $Mode
    total       = $fixes.Count
    restore_pt  = -not $SkipRestorePoint
    pid         = $PID
    ts          = [DateTime]::UtcNow.ToString('o')
}

# ────────────────────────────────────────────────────────────────────────
# Restore Point (best-effort; never blocks)
# ────────────────────────────────────────────────────────────────────────
if (-not $SkipRestorePoint) {
    Write-EventSafe -Type 'restore_point' -Data @{ status = 'creating' }
    try {
        $label = "ClockReaper-$Mode-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        # Habilita System Restore na C: (caso esteja off)
        try { Enable-ComputerRestore -Drive 'C:\' -ErrorAction SilentlyContinue } catch {}
        Checkpoint-Computer -Description $label -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
        Write-EventSafe -Type 'restore_point' -Data @{ status = 'created'; label = $label }
    } catch {
        Write-EventSafe -Type 'restore_point' -Data @{
            status = 'skipped'
            reason = $_.Exception.Message
        }
    }
}

# ────────────────────────────────────────────────────────────────────────
# Execute
# ────────────────────────────────────────────────────────────────────────
$applied = 0
$failed  = 0
$skipped = 0
$results = @()

for ($i = 0; $i -lt $fixes.Count; $i++) {
    $f = $fixes[$i]
    $cmd = if ($Mode -eq 'revert') { $f.revert_cmd } else { $f.fix_cmd }

    if ([string]::IsNullOrWhiteSpace($cmd)) {
        $skipped++
        Write-EventSafe -Type 'item' -Data @{
            id       = $f.id
            index    = $i
            title    = $f.title
            status   = 'skipped'
            reason   = "No $Mode command provided"
        }
        continue
    }

    Write-EventSafe -Type 'item' -Data @{
        id      = $f.id
        index   = $i
        title   = $f.title
        status  = 'running'
        command = $cmd
    }

    $tmpOut = [IO.Path]::GetTempFileName()
    $tmpErr = [IO.Path]::GetTempFileName()
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName  = 'cmd.exe'
        $psi.Arguments = "/c $cmd"
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true
        $psi.CreateNoWindow = $true

        $proc = [System.Diagnostics.Process]::Start($psi)
        $stdout = $proc.StandardOutput.ReadToEnd()
        $stderr = $proc.StandardError.ReadToEnd()
        $proc.WaitForExit()

        if ($proc.ExitCode -eq 0) {
            $applied++
            Write-EventSafe -Type 'item' -Data @{
                id     = $f.id
                index  = $i
                title  = $f.title
                status = 'ok'
                stdout = $stdout.Trim()
            }
            $results += @{ id = $f.id; status = 'ok' }
        } else {
            $failed++
            Write-EventSafe -Type 'item' -Data @{
                id        = $f.id
                index     = $i
                title     = $f.title
                status    = 'failed'
                exit_code = $proc.ExitCode
                stderr    = $stderr.Trim()
            }
            $results += @{ id = $f.id; status = 'failed'; exit_code = $proc.ExitCode }
        }
    } catch {
        $failed++
        Write-EventSafe -Type 'item' -Data @{
            id      = $f.id
            index   = $i
            title   = $f.title
            status  = 'failed'
            message = $_.Exception.Message
        }
    } finally {
        Remove-Item $tmpOut, $tmpErr -Force -ErrorAction SilentlyContinue
    }
}

Write-EventSafe -Type 'done' -Data @{
    mode    = $Mode
    applied = $applied
    failed  = $failed
    skipped = $skipped
    total   = $fixes.Count
}

exit 0
