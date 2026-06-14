#!/usr/bin/env pwsh
#requires -Version 7.0

function Invoke-PwtPingMon {
<#
.SYNOPSIS
    Continuous ping with colored latency thresholds and live stats.

.DESCRIPTION
    Pings a host every -Interval seconds and prints each round-trip with a
    color and bar based on latency thresholds. On exit (or after -Count
    iterations) prints aggregated statistics: sent, received, loss%,
    min/avg/max latency.

    Uses System.Net.NetworkInformation.Ping directly (no external tools).

.PARAMETER Target
    Host or IP to ping.

.PARAMETER Interval
    Seconds between pings (default: 1). Alias: -i

.PARAMETER Count
    Stop after N pings (default: 0 = infinite).

.PARAMETER WarnMs
    Latency above this value is yellow (default: 50).

.PARAMETER BadMs
    Latency above this value is red (default: 200).

.PARAMETER Timeout
    Per-ping timeout in milliseconds (default: 1500).

.EXAMPLE
    pwt pingmon google.com
    Continuous ping with default thresholds.

.EXAMPLE
    pwt pingmon 192.168.1.1 -i 2 -Count 30 -WarnMs 20 -BadMs 100
    Tighter thresholds, every 2 seconds, 30 pings.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Target,

        [Alias('i')]
        [double]$Interval = 1,

        [int]$Count = 0,

        [int]$WarnMs = 50,

        [int]$BadMs = 200,

        [int]$Timeout = 1500
    )

    $ping = [System.Net.NetworkInformation.Ping]::new()
    $stats = [PSCustomObject]@{
        Sent  = 0
        Recv  = 0
        Min   = [int]::MaxValue
        Max   = 0
        Total = 0L
    }

    Write-PwtHost ""
    Write-PwtHost "PingMon: " -NoNewline -ForegroundColor Cyan
    Write-PwtHost $Target -ForegroundColor White -NoNewline
    Write-PwtHost "  (Ctrl+C to stop)" -ForegroundColor DarkGray
    Write-PwtHost ""

    try {
        while ($true) {
            $stats.Sent++
            $time = Get-Date -Format 'HH:mm:ss'

            try {
                $reply = $ping.Send($Target, $Timeout)
            } catch {
                $reply = $null
            }

            if ($reply -and $reply.Status -eq 'Success') {
                $latency = [int]$reply.RoundtripTime
                $stats.Recv++
                $stats.Total += $latency
                if ($latency -lt $stats.Min) { $stats.Min = $latency }
                if ($latency -gt $stats.Max) { $stats.Max = $latency }

                $color = if     ($latency -lt $WarnMs) { 'Green' }
                         elseif ($latency -lt $BadMs)  { 'Yellow' }
                         else                          { 'Red' }

                $barLen = [Math]::Min(40, [int]($latency / 5) + 1)
                $bar = '#' * $barLen

                Write-PwtHost "[$time] " -NoNewline -ForegroundColor DarkGray
                Write-PwtHost ("{0,5} ms  " -f $latency) -NoNewline -ForegroundColor $color
                Write-PwtHost $bar -ForegroundColor $color
            } else {
                $reason = if ($reply) { $reply.Status } else { 'Unreachable' }
                Write-PwtHost "[$time]   FAIL   " -NoNewline -ForegroundColor Red
                Write-PwtHost $reason -ForegroundColor DarkGray
            }

            if ($Count -gt 0 -and $stats.Sent -ge $Count) { break }
            Start-Sleep -Seconds $Interval
        }
    } catch [System.Management.Automation.PipelineStoppedException] {
        # Ctrl+C - fall through to summary
    } finally {
        Write-PwtHost ""
        Write-PwtHost "  --- summary ---" -ForegroundColor Cyan
        $loss = if ($stats.Sent) {
            [Math]::Round((1 - $stats.Recv / $stats.Sent) * 100, 1)
        } else { 0 }
        $avg = if ($stats.Recv) { [int]($stats.Total / $stats.Recv) } else { 0 }
        $min = if ($stats.Recv) { $stats.Min } else { 0 }

        Write-PwtHost ("    sent={0}  recv={1}  loss={2}%" -f $stats.Sent, $stats.Recv, $loss)
        Write-PwtHost ("    min={0}ms  avg={1}ms  max={2}ms" -f $min, $avg, $stats.Max)
        Write-PwtHost ""

        $ping.Dispose()
    }
}

if (Get-Command Register-PwtCommand -ErrorAction SilentlyContinue) {
    Register-PwtCommand -Name 'pingmon' -Category 'network' `
        -Synopsis 'Continuous ping with colored latency thresholds and stats' `
        -Function 'Invoke-PwtPingMon'
}

