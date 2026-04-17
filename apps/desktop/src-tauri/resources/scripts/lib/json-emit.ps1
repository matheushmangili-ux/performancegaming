<#
.SYNOPSIS
    ClockReaper streaming protocol helper.

.DESCRIPTION
    Emits one compact JSON object per line on stdout so that the Rust
    orchestrator can parse events in real time via BufReader::lines().
    Every event carries a "type" discriminator and free-form fields.

    Consumed by apps/desktop/src-tauri/src/ps/orchestrator.rs.
#>

$script:ClockReaperStreamStart = [DateTime]::UtcNow

function Emit-Event {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Type,
        [Parameter(ValueFromRemainingArguments=$true)][object[]]$Rest = @()
    )

    $obj = [ordered]@{ type = $Type }

    # Accept either a hashtable or -Key Value pairs.
    if ($Rest.Count -eq 1 -and ($Rest[0] -is [hashtable])) {
        foreach ($k in $Rest[0].Keys) { $obj[$k] = $Rest[0][$k] }
    } elseif ($Rest.Count -gt 0) {
        for ($i = 0; $i -lt $Rest.Count; $i += 2) {
            $key = [string]$Rest[$i]
            if ($key.StartsWith('-')) { $key = $key.Substring(1) }
            $val = if ($i + 1 -lt $Rest.Count) { $Rest[$i + 1] } else { $null }
            $obj[$key] = $val
        }
    }

    $json = $obj | ConvertTo-Json -Compress -Depth 12
    [Console]::Out.WriteLine($json)
    [Console]::Out.Flush()
}

function Emit-Start {
    param([string]$Profile)
    Emit-Event -Type 'start' -Rest @{
        profile = $Profile
        pid     = $PID
        ts      = [DateTime]::UtcNow.ToString('o')
    }
}

function Emit-Progress {
    param([string]$Category, [int]$Pct)
    Emit-Event -Type 'progress' -Rest @{
        category = $Category
        pct      = $Pct
    }
}

function Emit-Hardware {
    param([hashtable]$Inventory)
    Emit-Event -Type 'hw' -Rest $Inventory
}

function Emit-Finding {
    param($Finding)
    # Matches the Add-Finding contract in the audit scripts.
    Emit-Event -Type 'finding' -Rest @{
        id       = [guid]::NewGuid().ToString('N').Substring(0, 10)
        severity = $Finding.Severity
        category = $Finding.Category
        title    = $Finding.Title
        current  = $Finding.Current
        why      = $Finding.Why
        impact   = $Finding.Impact
        fix_cmd  = $Finding.FixCmd
        revert_cmd = $Finding.RevertCmd
    }
}

function Emit-Done {
    param(
        [int]$Score,
        [int]$Critical,
        [int]$High,
        [int]$Medium,
        [int]$Total
    )
    $elapsed = [int]((([DateTime]::UtcNow) - $script:ClockReaperStreamStart).TotalMilliseconds)
    Emit-Event -Type 'done' -Rest @{
        score       = $Score
        critical    = $Critical
        high        = $High
        medium      = $Medium
        total       = $Total
        duration_ms = $elapsed
    }
}

function Emit-Error {
    param([string]$Message, [string]$Where)
    Emit-Event -Type 'error' -Rest @{
        message = $Message
        where   = $Where
    }
}
