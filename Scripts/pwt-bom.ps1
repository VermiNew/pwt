#!/usr/bin/env pwsh
#requires -Version 7.0

function Invoke-PwtBom {
<#
.SYNOPSIS
    Sprawdź (i opcjonalnie napraw) UTF-8 BOM (EF BB BF) w plikach .ps1 / .psm1.

.DESCRIPTION
    Skanuje wskazaną ścieżkę rekurencyjnie w poszukiwaniu plików .ps1 i .psm1,
    raportuje obecność / brak UTF-8 BOM. Z flagą -Fix dopisuje brakujący BOM
    na początek pliku (oryginalna treść jest zachowywana bajt-po-bajcie).

    Bez argumentów skanuje katalog bieżący. Można wskazać pojedynczy plik
    lub katalog.

    Status końcowy: $LASTEXITCODE = liczba plików bez BOM (0 = wszystko OK).

.PARAMETER Path
    Plik .ps1/.psm1 albo katalog (rekurencyjnie). Domyślnie: katalog bieżący.

.PARAMETER Fix
    Dopisz brakujący BOM do plików, w których go nie ma.

.PARAMETER Quiet
    Bez wyjścia, tylko exit code (0 = wszystkie OK, N = liczba bez BOM).

.EXAMPLE
    pwt bom
    Raport BOM dla wszystkich .ps1/.psm1 w katalogu bieżącym.

.EXAMPLE
    pwt bom -Fix
    Raport + dopisanie brakującego BOM.

.EXAMPLE
    pwt bom .\Scripts\pwt-phone.ps1
    Sprawdź pojedynczy plik.

.EXAMPLE
    pwt bom $PSScriptRoot -Fix
    Napraw cały katalog profilu PowerShell.
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
            Write-PwtHost "  Brak plików .ps1 / .psm1 w: $resolved" -ForegroundColor Yellow
            Write-PwtHost ""
        }
        $global:LASTEXITCODE = 0
        return
    }

    if (-not $Quiet) {
        Write-PwtHost ""
        Write-PwtHost "  Skanowanie: $resolved" -ForegroundColor White
        Write-PwtHost "  Plików: $($files.Count)" -ForegroundColor DarkGray
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
                        Write-PwtHost "Dodano BOM: $rel"
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
        Write-PwtHost ("  OK: $ok   bez BOM: $missing" + $(if ($Fix) { "   naprawione: $fixed" }) + $(if ($errors) { "   błędy: $errors" })) -ForegroundColor White
        if ($missing -gt 0 -and -not $Fix) {
            Write-PwtHost "  Uruchom 'pwt bom -Fix' aby dopisać brakujące BOM." -ForegroundColor DarkYellow
        }
        Write-PwtHost ""
    }

    # Po -Fix liczymy "remaining missing", nie pierwotne missing
    $remaining = if ($Fix) { $missing - $fixed } else { $missing }
    $global:LASTEXITCODE = $remaining + $errors
}

if (Get-Command Register-PwtCommand -ErrorAction SilentlyContinue) {
    Register-PwtCommand -Name 'bom' -Category 'dev' `
        -Synopsis 'Sprawdź / napraw UTF-8 BOM w plikach .ps1 i .psm1' `
        -Function 'Invoke-PwtBom'
}

