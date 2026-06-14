#!/usr/bin/env pwsh
#requires -Version 7.0

function Invoke-PwtWatch {
<#
.SYNOPSIS
    Re-run a command at a fixed interval (like Linux 'watch').

.DESCRIPTION
    Repeatedly executes a script block (or string command) every N seconds,
    clearing the screen between runs. Multi-line script blocks are fully
    supported. Press Ctrl+C to stop.

.PARAMETER Cmd
    Script block OR string to execute. A script block is preferred -
    it handles multi-line code, types and quoting natively.

.PARAMETER Interval
    Seconds between iterations (default: 2). Alias: -i

.PARAMETER Count
    Stop after N iterations (default: 0 = infinite).

.PARAMETER NoClear
    Don't clear the screen between iterations (append output).

.EXAMPLE
    pwt watch -i 2 -cmd { ping -n 1 google.com }
    Re-run a single ping every 2 seconds.

.EXAMPLE
    pwt watch -i 5 -cmd {
        Get-Process | Sort-Object CPU -Descending | Select-Object -First 5
    }
    Multi-line script block.

.EXAMPLE
    pwt watch -cmd 'date /t' -Count 3
    String command, only 3 iterations.
#>
    [CmdletBinding()]
    param(
        # NOTE: param name is 'Cmd' so '-cmd' / '-c' bind by prefix; no
        # explicit alias needed (and case-insensitive aliases that match
        # the parameter name itself are rejected by PowerShell).
        [Parameter(Mandatory, Position = 0)]
        $Cmd,

        [Alias('i', 'n')]
        [int]$Interval = 2,

        [int]$Count = 0,

        [switch]$NoClear
    )

    if ($Cmd -is [scriptblock]) {
        $display = $Cmd.ToString().Trim()
        $invoker = $Cmd
    } else {
        $cmdStr = [string]$Cmd
        $display = $cmdStr
        $invoker = [scriptblock]::Create($cmdStr)
    }

    $iter = 0
    try {
        while ($true) {
            $iter++
            if (-not $NoClear) {
                # Clear-Host fails in non-interactive hosts (no console
                # handle). Fall back to ANSI clear-screen, then newlines.
                try { Clear-Host }
                catch {
                    try { [Console]::Write("`e[2J`e[H") }
                    catch { Write-PwtHost ("`n" * 3) }
                }
            }

            $now = Get-Date -Format 'HH:mm:ss'
            Write-PwtHost "Every ${Interval}s | iter=$iter | $now | Ctrl+C to stop" -ForegroundColor DarkGray
            Write-PwtHost "> $display" -ForegroundColor Cyan
            Write-PwtHost ("-" * 60) -ForegroundColor DarkGray
            Write-PwtHost ""

            try {
                & $invoker
            } catch {
                Write-PwtHost "ERROR: $($_.Exception.Message)" -ForegroundColor Red
            }

            if ($Count -gt 0 -and $iter -ge $Count) { break }
            Start-Sleep -Seconds $Interval
        }
    } catch [System.Management.Automation.PipelineStoppedException] {
        # Ctrl+C - normal exit
    }
}

if (Get-Command Register-PwtCommand -ErrorAction SilentlyContinue) {
    Register-PwtCommand -Name 'watch' -Category 'system' `
        -Synopsis 'Run a command repeatedly at fixed intervals' `
        -Function 'Invoke-PwtWatch'
}

