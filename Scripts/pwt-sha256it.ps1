#!/usr/bin/env pwsh
#requires -Version 7.0

function Invoke-PwtSha256It {
<#
.SYNOPSIS
    Compute SHA-256 (or other) hash of a file and copy it to clipboard.

.DESCRIPTION
    Wraps Get-FileHash with sensible defaults: copies the hash to the
    clipboard, supports comparison against an expected value (great for
    verifying downloaded installers), and accepts pipeline input.

.PARAMETER Path
    File to hash. Accepts pipeline input.

.PARAMETER Algorithm
    Hash algorithm: SHA256 (default), SHA1, SHA384, SHA512, MD5.

.PARAMETER Expected
    Expected hash to compare against. Comparison is case-insensitive.

.PARAMETER NoClipboard
    Do not copy the hash to clipboard.

.EXAMPLE
    pwt sha256it installer.exe
    Hash the file with SHA-256 and copy result to clipboard.

.EXAMPLE
    pwt sha256it installer.exe -Expected 9f8e...
    Verify a download against an expected SHA-256.

.EXAMPLE
    Get-ChildItem *.iso | pwt sha256it -Algorithm SHA512
    Hash multiple files via pipeline.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string[]]$Path,

        [ValidateSet('SHA256','SHA1','SHA384','SHA512','MD5')]
        [string]$Algorithm = 'SHA256',

        [string]$Expected,

        [switch]$NoClipboard
    )

    process {
        foreach ($p in $Path) {
            if (-not (Test-Path $p -PathType Leaf)) {
                Write-PwtHost "  Not a file: $p" -ForegroundColor Red
                continue
            }

            try {
                $result = Get-FileHash -Path $p -Algorithm $Algorithm -ErrorAction Stop
            } catch {
                Write-PwtHost "  Hash failed: $($_.Exception.Message)" -ForegroundColor Red
                continue
            }

            Write-PwtHost ""
            Write-PwtHost "  File:      " -NoNewline -ForegroundColor Cyan
            Write-PwtHost (Resolve-Path $p)
            Write-PwtHost "  Algorithm: " -NoNewline -ForegroundColor Cyan
            Write-PwtHost $result.Algorithm
            Write-PwtHost "  Hash:      " -NoNewline -ForegroundColor Cyan
            Write-PwtHost $result.Hash -ForegroundColor White

            if ($Expected) {
                if ($result.Hash -ieq $Expected.Trim()) {
                    Write-PwtHost "  Match:     " -NoNewline -ForegroundColor Cyan
                    Write-PwtHost "OK - hashes match" -ForegroundColor Green
                } else {
                    Write-PwtHost "  Match:     " -NoNewline -ForegroundColor Cyan
                    Write-PwtHost "MISMATCH" -ForegroundColor Red
                    Write-PwtHost "  Expected:  " -NoNewline -ForegroundColor Cyan
                    Write-PwtHost $Expected -ForegroundColor Yellow
                }
            }

            if (-not $NoClipboard) {
                try {
                    Set-Clipboard -Value $result.Hash -ErrorAction Stop
                    Write-PwtHost "  Clipboard: " -NoNewline -ForegroundColor Cyan
                    Write-PwtHost "copied" -ForegroundColor Green
                } catch {
                    Write-PwtHost "  Clipboard: " -NoNewline -ForegroundColor Cyan
                    Write-PwtHost "unavailable" -ForegroundColor Yellow
                }
            }
            Write-PwtHost ""
        }
    }
}

if (Get-Command Register-PwtCommand -ErrorAction SilentlyContinue) {
    Register-PwtCommand -Name 'sha256it' -Category 'files' `
        -Synopsis 'Hash a file (SHA-256 default), copy to clipboard, optional verify' `
        -Function 'Invoke-PwtSha256It'
}

