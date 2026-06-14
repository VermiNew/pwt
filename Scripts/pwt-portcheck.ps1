#!/usr/bin/env pwsh
#requires -Version 7.0

function Invoke-PwtPortCheck {
<#
.SYNOPSIS
    Show what process is listening on a TCP port.

.DESCRIPTION
    Inspects local TCP listeners on a given port and returns the owning
    process name, PID, listening address, and state. Uses Get-NetTCPConnection
    (built into Windows) - no external tools required.

.PARAMETER Port
    TCP port number to inspect (1-65535).

.PARAMETER All
    Also list ports in non-LISTEN states (Established, TimeWait, etc.).

.EXAMPLE
    pwt portcheck 3000
    Show what is listening on port 3000.

.EXAMPLE
    pwt portcheck 5173 -All
    Show every connection on port 5173, not only LISTEN.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateRange(1, 65535)]
        [int]$Port,

        [switch]$All
    )

    try {
        $conns = Get-NetTCPConnection -LocalPort $Port -ErrorAction Stop
    } catch {
        Write-PwtHost ""
        Write-PwtHost "  Nothing listening on port " -ForegroundColor Yellow -NoNewline
        Write-PwtHost $Port -ForegroundColor White
        Write-PwtHost ""
        return
    }

    if (-not $All) {
        $conns = $conns | Where-Object { $_.State -eq 'Listen' }
    }

    if (-not $conns) {
        Write-PwtHost ""
        Write-PwtHost "  Nothing in LISTEN state on port " -ForegroundColor Yellow -NoNewline
        Write-PwtHost $Port -ForegroundColor White
        Write-PwtHost "  (use -All to include other states)" -ForegroundColor DarkGray
        Write-PwtHost ""
        return
    }

    $rows = foreach ($c in $conns) {
        $proc = try { Get-Process -Id $c.OwningProcess -ErrorAction Stop } catch { $null }
        [PSCustomObject]@{
            Port    = $c.LocalPort
            Address = $c.LocalAddress
            State   = $c.State
            PID     = $c.OwningProcess
            Process = if ($proc) { $proc.ProcessName } else { '<unknown>' }
            Path    = if ($proc) { $proc.Path }        else { '' }
        }
    }

    Write-PwtHost ""
    $rows | Format-Table Port, Address, State, PID, Process, Path -AutoSize
}

if (Get-Command Register-PwtCommand -ErrorAction SilentlyContinue) {
    Register-PwtCommand -Name 'portcheck' -Category 'network' `
        -Synopsis 'Show what process is listening on a TCP port' `
        -Function 'Invoke-PwtPortCheck'
}

