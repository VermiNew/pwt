#!/usr/bin/env pwsh
#requires -Version 7.0

function Invoke-PwtBom {
<#
.SYNOPSIS
    Check (and optionally fix) UTF-8 BOM (EF BB BF) in .ps1 / .psm1 files.

.DESCRIPTION
    Recursively scans the specified path for .ps1 and .psm1 files,
    reporting the presence / absence of UTF-8 BOM. With the -Fix flag, appends
    the missing BOM to the beginning of the file (original content is preserved
    byte-by-byte).

    Without arguments, scans the current directory. You can specify a single
    file or a directory.

    Exit status: $LASTEXITCODE = number of files without BOM (0 = all OK).

.PARAMETER Path
    A .ps1/.psm1 file or directory (recursively). Default: current directory.

.PARAMETER Fix
    Add missing BOM to files that are missing it.

.PARAMETER Quiet
    No output, exit code only (0 = all OK, N = number without BOM).

.EXAMPLE
    pwt bom
    BOM report for all .ps1/.psm1 in the current directory.

.EXAMPLE
    pwt bom -Fix
    Report + add missing BOM.

.EXAMPLE
    pwt bom .\Scripts\pwt-phone.ps1
    Check a single file.

.EXAMPLE
    pwt bom $PSScriptRoot -Fix
    Fix the entire PowerShell profile directory.
#>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Position = 0)]
        [string]$Path = '.',

        [switch]$Fix,
        [switch]$Quiet
    )

    $BOM = [byte[]]@(0xEF, 0xBB, 0xBF)

    # ── Resolve target ────────────────────────────────────────────────────────
    $resolved = Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $resolved) {
        if (-not $Quiet) { Write-PwtHost "  [MISSING] $Path" -ForegroundColor Red }
        $global:LASTEXITCODE = 1
        return
    }

    if (Test-Path -LiteralPath $resolved -PathType Leaf) {
        $files = @(Get-Item -LiteralPath $resolved)
    } else {
        $files = Get-ChildItem -Path $resolved -Include '*.ps1', '*.psm1' -Recurse -File |
                 Sort-Object FullName
    }

    if ($files.Count -eq 0) {
        if (-not $Quiet) {
            Write-PwtHost ""
            Write-PwtHost "  No .ps1 / .psm1 files found in: $resolved" -ForegroundColor Yellow
            Write-PwtHost ""
        }
        $global:LASTEXITCODE = 0
        return
    }

    if (-not $Quiet) {
        Write-PwtHost ""
        Write-PwtHost "  Scanning: $resolved" -ForegroundColor White
        Write-PwtHost "  Files: $($files.Count)" -ForegroundColor DarkGray
        Write-PwtHost ""
    }

    # ── Scan ──────────────────────────────────────────────────────────────────
    $ok      = 0
    $missing = 0
    $fixed   = 0
    $errors  = 0
    $base    = if ($resolved.Path) { $resolved.Path } else { [string]$resolved }

    foreach ($f in $files) {
        $rel = $f.FullName.Replace($base, '').TrimStart('\', '/')
        if (-not $rel) { $rel = $f.Name }

        try {
            $bytes  = [System.IO.File]::ReadAllBytes($f.FullName)
            $hasBom = ($bytes.Length -ge 3) -and
                      ($bytes[0] -eq 0xEF) -and
                      ($bytes[1] -eq 0xBB) -and
                      ($bytes[2] -eq 0xBF)

            if ($hasBom) {
                $ok++
                if (-not $Quiet) {
                    Write-PwtHost "  [OK]    " -ForegroundColor Green -NoNewline
                    Write-PwtHost $rel
                }
                continue
            }

            $missing++
            if (-not $Quiet) {
                Write-PwtHost "  [NOBOM] " -ForegroundColor Yellow -NoNewline
                Write-PwtHost $rel
            }

            if (-not $Fix) { continue }

            if ($PSCmdlet.ShouldProcess($f.FullName, 'Add UTF-8 BOM')) {
                try {
                    $withBom = $BOM + $bytes
                    [System.IO.File]::WriteAllBytes($f.FullName, $withBom)
                    $fixed++
                    if (-not $Quiet) {
                        Write-PwtHost "  [FIX]   " -ForegroundColor Cyan -NoNewline
                        Write-PwtHost "BOM added: $rel"
                    }
                } catch {
                    $errors++
                    if (-not $Quiet) {
                        Write-PwtHost "  [ERR]   " -ForegroundColor Red -NoNewline
                        Write-PwtHost "$rel : $($_.Exception.Message)"
                    }
                }
            }
        } catch {
            $errors++
            if (-not $Quiet) {
                Write-PwtHost "  [ERR]   " -ForegroundColor Red -NoNewline
                Write-PwtHost "$rel : $($_.Exception.Message)"
            }
        }
    }

    # ── Summary ───────────────────────────────────────────────────────────────
    if (-not $Quiet) {
        Write-PwtHost ""
        Write-PwtHost ("  OK: $ok   missing BOM: $missing" + $(if ($Fix) { "   fixed: $fixed" }) + $(if ($errors) { "   errors: $errors" })) -ForegroundColor White
        if ($missing -gt 0 -and -not $Fix) {
            Write-PwtHost "  Run 'pwt bom -Fix' to add missing BOM." -ForegroundColor DarkYellow
        }
        Write-PwtHost ""
    }

    # After -Fix, count "remaining missing", not original missing
    $remaining = if ($Fix) { $missing - $fixed } else { $missing }
    $global:LASTEXITCODE = $remaining + $errors
}

if (Get-Command Register-PwtCommand -ErrorAction SilentlyContinue) {
    Register-PwtCommand -Name 'bom' -Category 'dev' `
        -Synopsis 'Check / fix UTF-8 BOM in .ps1 and .psm1 files' `
        -Function 'Invoke-PwtBom'
}
