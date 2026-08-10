#!/usr/bin/env pwsh
#requires -Version 7.0

function Invoke-PwtUnlock {
<#
.SYNOPSIS
    Unblock files marked as 'downloaded from the Internet' (Zone.Identifier).

.DESCRIPTION
    Wraps Unblock-File with wildcards, multiple paths and recursion. Removes
    the Zone.Identifier alternate data stream so PowerShell execution
    policies (RemoteSigned / AllSigned) stop blocking the files. Reports
    the origin URL (ReferrerUrl) when present and shows running totals.

.PARAMETER Path
    Files to unblock. Accepts wildcards. Default: '*' in current directory.

.PARAMETER Filter
    Get-ChildItem filter (faster than wildcard in Path), e.g. *.ps1.

.PARAMETER Recurse
    Recurse into subdirectories.

.PARAMETER PassThru
    Emit FileInfo objects for each unblocked file.

.PARAMETER Quiet
    Suppress per-file output, show only the summary.

.EXAMPLE
    pwt unlock *.ps1
    Unblock all .ps1 in current directory.

.EXAMPLE
    pwt unlock C:\Downloads -Recurse
    Recursively unblock everything in Downloads.

.EXAMPLE
    pwt unlock C:\Tools -Filter *.dll -Recurse -WhatIf
    Preview unblock for DLLs only.
#>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$Path = @('*'),

        [string]$Filter,

        [switch]$Recurse,

        [switch]$PassThru,

        [switch]$Quiet
    )

    begin {
        $totalUnblocked = 0
        $totalSkipped   = 0
        $totalFailed    = 0
        $totalBytes     = 0L
    }

    process {
        foreach ($entry in $Path) {

            # ----------------------------------------------------------------
            # SAFETY: refuse to unblock an entire drive root (C:\, D:\, etc.)
            # ----------------------------------------------------------------
            $testPath = $entry.TrimEnd('\', '/')
            if ($testPath -match '^[A-Za-z]:$') {
                Write-Error "Blocked: unlocking an entire drive ('$entry') is not allowed. Specify a folder or files, e.g. C:\Downloads\*.ps1"
                continue
            }
            try {
                $resolvedRoot = Get-Item -LiteralPath $testPath -ErrorAction Stop
                if ($resolvedRoot.FullName -match '^[A-Za-z]:\\?$') {
                    Write-Error "Blocked: unlocking an entire drive ('$($resolvedRoot.FullName)') is not allowed. Specify a folder or files."
                    continue
                }
            } catch {}
            # ----------------------------------------------------------------

            $gciParams = @{
                Path        = $entry
                File        = $true
                ErrorAction = 'SilentlyContinue'
            }
            if ($Recurse) { $gciParams['Recurse'] = $true }
            if ($Filter)  { $gciParams['Filter']  = $Filter }

            $files = Get-ChildItem @gciParams
            if (-not $files) {
                Write-Warning "No files found matching: $entry"
                continue
            }

            # ----------------------------------------------------------------
            # CONFIRMATION: show the list of files to be unblocked, then ask
            # ----------------------------------------------------------------
            if (-not $WhatIfPreference) {
                $blockedFiles = $files | Where-Object {
                    Get-Item -LiteralPath $_.FullName -Stream 'Zone.Identifier' -ErrorAction SilentlyContinue
                }

                if (-not $blockedFiles) {
                    Write-PwtHost "  No blocked files found in: $entry" -ForegroundColor Yellow
                    $totalSkipped += @($files).Count
                    continue
                }

                $fileNames = ($blockedFiles | ForEach-Object { $_.Name }) -join ', '
                Write-PwtHost ""
                Write-PwtHost "  Files to unblock ($(@($blockedFiles).Count)):" -ForegroundColor Yellow
                Write-PwtHost "  $fileNames" -ForegroundColor White
                Write-PwtHost ""
                $confirm = Read-Host "  Unblock these files? [Y/N]"
                if ($confirm -notmatch '^[Yy]') {
                    Write-PwtHost "  Cancelled." -ForegroundColor DarkGray
                    Write-PwtHost ""
                    continue
                }
            }
            # ----------------------------------------------------------------

            foreach ($file in $files) {
                $stream = Get-Item -LiteralPath $file.FullName -Stream 'Zone.Identifier' `
                    -ErrorAction SilentlyContinue
                if (-not $stream) {
                    if (-not $Quiet) {
                        Write-Verbose "Already clean: $($file.FullName)"
                    }
                    $totalSkipped++
                    continue
                }

                # Try to extract origin URL from the Zone.Identifier content.
                $origin = $null
                try {
                    $zoneText = Get-Content -LiteralPath $file.FullName `
                        -Stream 'Zone.Identifier' -Raw -ErrorAction SilentlyContinue
                    if ($zoneText -match 'ReferrerUrl\s*=\s*(\S+)') {
                        $origin = $matches[1]
                    } elseif ($zoneText -match 'HostUrl\s*=\s*(\S+)') {
                        $origin = $matches[1]
                    }
                } catch {}

                if ($PSCmdlet.ShouldProcess($file.FullName, 'Unblock-File')) {
                    try {
                        Unblock-File -LiteralPath $file.FullName -ErrorAction Stop
                        $totalUnblocked++
                        $totalBytes += $file.Length

                        if (-not $Quiet) {
                            Write-PwtHost "  + " -NoNewline -ForegroundColor Green
                            Write-PwtHost $file.FullName -ForegroundColor White
                            Write-PwtHost ("      $(Format-PwtSize $file.Length)") `
                                -NoNewline -ForegroundColor DarkGray
                            if ($origin) {
                                Write-PwtHost "  <- $origin" -ForegroundColor DarkCyan
                            } else {
                                Write-PwtHost ""
                            }
                        }

                        if ($PassThru) { $file }
                    } catch {
                        Write-Warning "Failed: $($file.FullName) - $($_.Exception.Message)"
                        $totalFailed++
                    }
                }
            }
        }
    }

    end {
        Write-PwtHost ""
        Write-PwtHost "  Done. " -NoNewline -ForegroundColor Cyan
        Write-PwtHost "Unblocked: " -NoNewline
        Write-PwtHost $totalUnblocked -NoNewline -ForegroundColor Green
        Write-PwtHost "  ($(Format-PwtSize $totalBytes))  |  " -NoNewline -ForegroundColor DarkGray
        Write-PwtHost "Already clean: " -NoNewline
        Write-PwtHost $totalSkipped -NoNewline -ForegroundColor Yellow
        Write-PwtHost "  |  Failed: " -NoNewline
        $failColor = if ($totalFailed -gt 0) { 'Red' } else { 'Green' }
        Write-PwtHost $totalFailed -ForegroundColor $failColor
        Write-PwtHost ""
    }
}

if (Get-Command Register-PwtCommand -ErrorAction SilentlyContinue) {
    Register-PwtCommand -Name 'unlock' -Category 'files' `
        -Synopsis 'Unblock files downloaded from Internet (Zone.Identifier)' `
        -Function 'Invoke-PwtUnlock'
}

