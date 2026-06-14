#!/usr/bin/env pwsh
#requires -Version 7.0
# NOTE: do NOT use '#Requires -RunAsAdministrator' here - it would prevent
# the file from being dot-sourced into a non-admin profile. Admin check is
# performed inside the function instead.

function Invoke-PwtCleanSpool {
<#
.SYNOPSIS
    Clear stuck printer jobs by restarting Spooler and wiping the queue folder.

.DESCRIPTION
    1. Verifies the session is elevated (admin).
    2. Checks for active print jobs across all printers and warns if any
       exist (they will be lost).
    3. Stops the Print Spooler service.
    4. Removes every file in %SystemRoot%\System32\spool\PRINTERS.
    5. Restarts the service with retry/timeout logic.

    Run as Administrator. Supports -WhatIf and -Confirm.

.PARAMETER Force
    Skip the confirmation prompt before deleting spool files.

.EXAMPLE
    pwt cleanspool
    Interactive: lists files, asks for confirmation, then clears.

.EXAMPLE
    pwt cleanspool -Force
    Clear the queue without prompting.

.EXAMPLE
    pwt cleanspool -WhatIf
    Show what would happen without changing anything.
#>
    [CmdletBinding(SupportsShouldProcess)]
    param([switch]$Force)

    # --- 0. Admin check (auto-elevate via sudo if available) -------------
    if (-not (Test-PwtAdmin)) {
        # Try Windows 11 sudo for a seamless re-launch.
        $relaunchArgs = @()
        if ($Force)            { $relaunchArgs += '-Force' }
        if ($WhatIfPreference) { $relaunchArgs += '-WhatIf' }
        $relaunchCmd = ". '$PROFILE'; Invoke-PwtCleanSpool $($relaunchArgs -join ' ')"

        if (Invoke-PwtElevated -Command $relaunchCmd) {
            return
        }

        Write-PwtHost ""
        Write-PwtHost "  [ERROR] cleanspool requires Administrator privileges." -ForegroundColor Red
        Write-PwtHost "  Windows 11 'sudo' was not found or is disabled." -ForegroundColor Yellow
        Write-PwtHost ""
        Write-PwtHost "  Options:" -ForegroundColor Yellow
        Write-PwtHost "    1. Enable sudo: Settings -> System -> For developers -> Enable sudo" -ForegroundColor Gray
        Write-PwtHost "    2. Or re-launch PowerShell with 'Run as administrator'" -ForegroundColor Gray
        Write-PwtHost ""
        return
    }

    $printerFolder = Join-Path $env:SystemRoot 'System32\spool\PRINTERS'

    try {
        # --- 1. Active jobs check ----------------------------------------
        $activeJobs = @()
        try {
            $printers = Get-Printer -ErrorAction SilentlyContinue
            foreach ($p in $printers) {
                $jobs = Get-PrintJob -PrinterName $p.Name -ErrorAction SilentlyContinue
                if ($jobs) { $activeJobs += $jobs }
            }
        } catch {
            Write-Verbose "Could not enumerate print jobs: $($_.Exception.Message)"
        }

        if ($activeJobs.Count -gt 0) {
            Write-PwtHost ""
            Write-PwtHost "  WARNING: $($activeJobs.Count) active print job(s) found:" -ForegroundColor Yellow
            $activeJobs | ForEach-Object {
                Write-PwtHost ("    [{0}] {1} on {2} ({3})" -f $_.Id, $_.DocumentName, $_.PrinterName, $_.JobStatus) `
                    -ForegroundColor DarkYellow
            }
            Write-PwtHost "  These jobs WILL BE LOST if you continue." -ForegroundColor Yellow
            Write-PwtHost ""
        }

        # --- 2. Stop service ---------------------------------------------
        Write-PwtHost "Stopping Print Spooler service..." -ForegroundColor Cyan
        $svc = Get-Service -Name Spooler -ErrorAction Stop
        if ($svc.Status -eq 'Running') {
            if ($PSCmdlet.ShouldProcess('Spooler', 'Stop service')) {
                Stop-Service -Name Spooler -Force -ErrorAction Stop
                Write-PwtHost "  [OK] Stopped" -ForegroundColor Green
            }
        } else {
            Write-PwtHost "  [INFO] Already stopped" -ForegroundColor Yellow
        }

        # --- 3. Remove spool files ---------------------------------------
        if (-not (Test-Path $printerFolder)) {
            Write-Warning "Spool folder not found: $printerFolder"
        } else {
            $files = Get-ChildItem -Path $printerFolder -File -Force -ErrorAction SilentlyContinue
            if (-not $files) {
                Write-PwtHost ""
                Write-PwtHost "[INFO] No spool files to remove." -ForegroundColor Yellow
            } else {
                Write-PwtHost ""
                Write-PwtHost "Files in spool folder ($($files.Count)):" -ForegroundColor Cyan
                $totalBytes = 0L
                $files | ForEach-Object {
                    $totalBytes += $_.Length
                    Write-PwtHost ("  {0,-40} {1,10}  {2}" -f $_.Name,
                        (Format-PwtSize $_.Length),
                        $_.CreationTime.ToString('yyyy-MM-dd HH:mm:ss')) -ForegroundColor Gray
                }
                Write-PwtHost ("  Total: $(Format-PwtSize $totalBytes)") -ForegroundColor DarkGray
                Write-PwtHost ""

                if (-not $Force -and -not $WhatIfPreference) {
                    $ans = Read-Host "Remove these $($files.Count) file(s)? [Y/N]"
                    if ($ans -notmatch '^[Yy]') {
                        Write-PwtHost "[INFO] Cancelled by user." -ForegroundColor Yellow
                        # Still try to restart the service before bailing.
                        Start-Service -Name Spooler -ErrorAction SilentlyContinue
                        return
                    }
                }

                if ($PSCmdlet.ShouldProcess("$($files.Count) file(s) in $printerFolder", 'Remove')) {
                    $files | Remove-Item -Force -ErrorAction SilentlyContinue
                    Write-PwtHost "  [OK] Removed $($files.Count) file(s)" -ForegroundColor Green
                }
            }
        }

        # --- 4. Restart service with retry --------------------------------
        Write-PwtHost ""
        Write-PwtHost "Starting Print Spooler service..." -ForegroundColor Cyan

        if ($PSCmdlet.ShouldProcess('Spooler', 'Start service')) {
            $maxRetries = 3
            $timeoutSec = 30
            $started = $false

            for ($i = 1; $i -le $maxRetries -and -not $started; $i++) {
                Write-PwtHost "  [INFO] Attempt $i of $maxRetries..." -ForegroundColor DarkCyan
                try {
                    Start-Service -Name Spooler -ErrorAction Stop
                    $sw = [System.Diagnostics.Stopwatch]::StartNew()
                    $svc = Get-Service -Name Spooler
                    while ($sw.Elapsed.TotalSeconds -lt $timeoutSec) {
                        $svc.Refresh()
                        if ($svc.Status -eq 'Running') { $started = $true; break }
                        Start-Sleep -Milliseconds 500
                    }
                    $sw.Stop()
                    if (-not $started) {
                        Write-PwtHost "  [WARN] Timed out waiting for service" -ForegroundColor Yellow
                    }
                } catch {
                    Write-PwtHost "  [WARN] $($_.Exception.Message)" -ForegroundColor Yellow
                    if ($i -lt $maxRetries) { Start-Sleep -Seconds 2 }
                }
            }

            if ($started) {
                Write-PwtHost "  [OK] Service running" -ForegroundColor Green
            } else {
                Write-PwtHost "  [ERROR] Service did not start after $maxRetries attempts" -ForegroundColor Red
                return
            }
        }

        Write-PwtHost ""
        Write-PwtHost "[DONE] Printer queue cleared." -ForegroundColor Green
        Write-PwtHost ""

    } catch {
        Write-PwtHost ""
        Write-PwtHost "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
        # Best-effort recovery: try to bring the service back.
        try {
            $svc = Get-Service -Name Spooler -ErrorAction SilentlyContinue
            if ($svc -and $svc.Status -ne 'Running') {
                Write-PwtHost "Attempting recovery: starting Spooler..." -ForegroundColor Yellow
                Start-Service -Name Spooler -ErrorAction SilentlyContinue
            }
        } catch {
            Write-Warning "Could not auto-restore Spooler service."
        }
    }
}

if (Get-Command Register-PwtCommand -ErrorAction SilentlyContinue) {
    Register-PwtCommand -Name 'cleanspool' -Category 'printer' `
        -Synopsis 'Clear stuck printer queue (Spooler restart + wipe)' `
        -Function 'Invoke-PwtCleanSpool'
}

