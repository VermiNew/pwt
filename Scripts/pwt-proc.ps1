#!/usr/bin/env pwsh
#requires -Version 7.0

function Invoke-PwtProc {
<#
.SYNOPSIS
    Find and optionally terminate processes by name, PID, or TCP port.

.DESCRIPTION
    Lists processes matching a name pattern or owning a specific TCP port.
    Without -Terminate it is read-only. With -Terminate it stops the matched
    processes (Stop-Process). Add -Force to skip the confirmation prompt.

    Useful for:
      - Finding what holds a port (similar to pwt portcheck, but also terminates)
      - Stopping a stuck dev server, test runner, or build tool by name

.PARAMETER Name
    Process name pattern (wildcards supported, e.g. node, python*, *java*).

.PARAMETER Port
    Find the process listening on this TCP port.

.PARAMETER Terminate
    Stop matched processes. Asks for confirmation unless -Force is set.

.PARAMETER Force
    Skip confirmation when terminating. Implies -Terminate.

.EXAMPLE
    pwt proc node
    List all node.exe processes.

.EXAMPLE
    pwt proc -Port 3000
    Show which process is listening on port 3000.

.EXAMPLE
    pwt proc node -Terminate
    Terminate all node processes (with confirmation).

.EXAMPLE
    pwt proc -Port 8080 -Terminate -Force
    Terminate the process on port 8080 immediately, no confirmation.
#>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Position = 0)]
        [string]$Name,

        [ValidateRange(1, 65535)]
        [int]$Port,

        [switch]$Terminate,

        [switch]$Force
    )

    if (-not $Name -and -not $Port) {
        Write-PwtHost ""
        Write-PwtHost "  Usage: pwt proc <name>  or  pwt proc -Port <port>" -Style Muted
        Write-PwtHost "  Options: -Terminate  -Force" -Style Muted
        Write-PwtHost ""
        return
    }

    if ($Force) { $Terminate = $true }

    $procs = [System.Collections.Generic.List[PSCustomObject]]::new()

    # ── Resolve by port ────────────────────────────────────────────────────────
    if ($Port) {
        $connections = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
        if (-not $connections) {
            Write-PwtHost ""
            Write-PwtHost "  No process listening on port $Port." -Style Warn
            Write-PwtHost ""
            return
        }
        foreach ($conn in $connections) {
            $p = Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue
            if ($p) {
                $procs.Add([PSCustomObject]@{
                    PID     = $p.Id
                    Name    = $p.Name
                    CPU     = [Math]::Round($p.CPU, 1)
                    MemMB   = [Math]::Round($p.WorkingSet64 / 1MB, 1)
                    Port    = $Port
                    Started = $p.StartTime
                    Process = $p
                })
            }
        }
    }

    # ── Resolve by name ────────────────────────────────────────────────────────
    if ($Name) {
        $pattern = $Name -replace '\*', '.*'
        Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "(?i)^$pattern$" -or $_.Name -like $Name } | ForEach-Object {
            $procs.Add([PSCustomObject]@{
                PID     = $_.Id
                Name    = $_.Name
                CPU     = [Math]::Round($_.CPU, 1)
                MemMB   = [Math]::Round($_.WorkingSet64 / 1MB, 1)
                Port    = $null
                Started = $_.StartTime
                Process = $_
            })
        }
    }

    if ($procs.Count -eq 0) {
        Write-PwtHost ""
        Write-PwtHost "  No matching processes found." -Style Warn
        Write-PwtHost ""
        return
    }

    # ── Display ────────────────────────────────────────────────────────────────
    Write-PwtHost ""
    Write-PwtHost ("  {0,-7} {1,-22} {2,7} {3,8}  {4}" -f 'PID', 'Name', 'CPU(s)', 'Mem(MB)', 'Started') -Style Heading
    Write-PwtHost ("  {0,-7} {1,-22} {2,7} {3,8}  {4}" -f '-------', '----------------------', '-------', '--------', '-------------------') -Style Muted

    foreach ($p in $procs) {
        $portStr    = if ($p.Port) { " :$($p.Port)" } else { '' }
        $startedStr = if ($p.Started) { $p.Started.ToString('yyyy-MM-dd HH:mm:ss') } else { '—' }
        Write-PwtHost ("  {0,-7} " -f $p.PID) -NoNewline -Style Muted
        Write-PwtHost ("{0,-22}" -f "$($p.Name)$portStr") -NoNewline -Style Text
        Write-PwtHost (" {0,7}" -f $p.CPU) -NoNewline -Style Muted
        Write-PwtHost (" {0,8}" -f $p.MemMB) -NoNewline -Style Muted
        Write-PwtHost "  $startedStr" -Style Muted
    }
    Write-PwtHost ""

    if (-not $Terminate) { return }

    # ── Terminate ─────────────────────────────────────────────────────────────
    if (-not $Force) {
        Write-PwtHost "  Terminate $($procs.Count) process(es) listed above?" -Style Warn
        $r = Read-Host "  [y/N]"
        if ($r -notin @('y', 'Y')) {
            Write-PwtHost "  Cancelled." -Style Muted
            Write-PwtHost ""
            return
        }
    }

    $terminated = 0
    $errors     = 0
    foreach ($p in $procs) {
        try {
            Stop-Process -Id $p.PID -Force -ErrorAction Stop
            Write-PwtHost "  ✔ Terminated $($p.Name) (PID $($p.PID))" -Style Ok
            $terminated++
        }
        catch {
            Write-PwtHost "  ✘ $($p.Name) (PID $($p.PID)): $($_.Exception.Message)" -Style Error
            $errors++
        }
    }

    Write-PwtHost ""
    if ($errors -eq 0) {
        Write-PwtHost "  $terminated process(es) terminated." -Style Ok
    } else {
        Write-PwtHost "  $terminated terminated, $errors error(s)." -Style Warn
    }
    Write-PwtHost ""
}

if (Get-Command Register-PwtCommand -ErrorAction SilentlyContinue) {
    Register-PwtCommand -Name 'proc' -Category 'system' `
        -Synopsis 'Find and terminate processes by name or TCP port' `
        -Function 'Invoke-PwtProc'
}
