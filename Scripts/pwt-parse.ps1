#!/usr/bin/env pwsh
#requires -Version 7.0

function Invoke-PwtParse {
<#
.SYNOPSIS
    Sprawdź składnię plików .ps1 (PowerShell AST parser) bez ich uruchamiania.

.DESCRIPTION
    Statyczna walidacja: używa [System.Management.Automation.Language.Parser]
    do parsowania pliku i raportuje błędy składniowe z numerem linii i kolumny.
    Nigdy nie wykonuje kodu — bezpieczne dla nieznanych skryptów.

    Bez argumentów sprawdza wszystkie pwt-*.ps1 w katalogu Scripts.
    Z -Functions wypisuje listę funkcji top-level zdefiniowanych w pliku
    (przydatne do szybkiego przeglądu struktury).

    Status końcowy: $LASTEXITCODE = liczba plików z błędami (0 = wszystko OK).

.PARAMETER Path
    Plik .ps1 albo katalog. Można podać wiele. Domyślnie: cały Scripts/pwt-*.ps1.

.PARAMETER Functions
    Wypisz funkcje top-level zdefiniowane w każdym sprawdzanym pliku.

.PARAMETER Quiet
    Bez wyjścia, tylko exit code (0 = OK, N = liczba plików z błędami).

.PARAMETER Recurse
    Dla katalogów: szukaj rekurencyjnie (domyślnie tylko bezpośrednio).

.EXAMPLE
    pwt parse
    Sprawdź wszystkie pwt-*.ps1 w Scripts/.

.EXAMPLE
    pwt parse .\Scripts\pwt-phone.ps1
    Sprawdź konkretny plik.

.EXAMPLE
    pwt parse .\Scripts\pwt-phone.ps1 -Functions
    Sprawdź składnię + wypisz funkcje top-level.

.EXAMPLE
    pwt parse .\Modules -Recurse
    Sprawdź rekurencyjnie wszystkie .ps1/.psm1 w katalogu.
#>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromRemainingArguments)]
        [string[]]$Path,

        [switch]$Functions,
        [switch]$Quiet,
        [switch]$Recurse
    )

    # ── Resolve target files ──────────────────────────────────────────────────
    $files = [System.Collections.Generic.List[string]]::new()

    if (-not $Path -or $Path.Count -eq 0) {
        $scriptsDir = Split-Path -Parent $PSCommandPath
        Get-ChildItem -Path $scriptsDir -Filter 'pwt-*.ps1' -File |
            ForEach-Object { $files.Add($_.FullName) }
    }
    else {
        foreach ($p in $Path) {
            if (-not (Test-Path -LiteralPath $p)) {
                if (-not $Quiet) {
                    Write-PwtHost "  [MISSING] $p" -ForegroundColor Red
                }
                continue
            }
            $item = Get-Item -LiteralPath $p
            if ($item.PSIsContainer) {
                $opts = @{ Path = $item.FullName; File = $true; Include = '*.ps1', '*.psm1' }
                if ($Recurse) { $opts.Recurse = $true }
                # -Include needs a wildcard in -Path; switch strategy
                $children = if ($Recurse) {
                    Get-ChildItem -Path $item.FullName -Recurse -File |
                        Where-Object { $_.Extension -in '.ps1', '.psm1' }
                } else {
                    Get-ChildItem -Path $item.FullName -File |
                        Where-Object { $_.Extension -in '.ps1', '.psm1' }
                }
                $children | ForEach-Object { $files.Add($_.FullName) }
            }
            else {
                $files.Add($item.FullName)
            }
        }
    }

    if ($files.Count -eq 0) {
        if (-not $Quiet) {
            Write-PwtHost ""
            Write-PwtHost "  Brak plików do sprawdzenia." -ForegroundColor Yellow
            Write-PwtHost ""
        }
        $global:LASTEXITCODE = 0
        return
    }

    # ── Parse each file ───────────────────────────────────────────────────────
    if (-not $Quiet) { Write-PwtHost "" }

    $failed = 0
    $maxName = ($files | ForEach-Object { (Split-Path -Leaf $_).Length } | Measure-Object -Maximum).Maximum

    foreach ($file in $files) {
        $errors = $null
        $tokens = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $file, [ref]$tokens, [ref]$errors
        )

        $name = Split-Path -Leaf $file
        $hasErrors = $errors -and $errors.Count -gt 0

        if ($hasErrors) { $failed++ }

        if ($Quiet) { continue }

        # Status line
        if ($hasErrors) {
            Write-PwtHost "  [FAIL]  " -ForegroundColor Red -NoNewline
        } else {
            Write-PwtHost "  [OK]    " -ForegroundColor Green -NoNewline
        }
        Write-PwtHost $name.PadRight($maxName + 2) -NoNewline -ForegroundColor White
        if ($hasErrors) {
            Write-PwtHost "$($errors.Count) błąd(ów)" -ForegroundColor Red
        } else {
            Write-PwtHost "" -NoNewline
            Write-PwtHost ""
        }

        # Errors
        foreach ($err in $errors) {
            $line = $err.Extent.StartLineNumber
            $col  = $err.Extent.StartColumnNumber
            Write-PwtHost "          " -NoNewline
            Write-PwtHost "L$line" -ForegroundColor Yellow -NoNewline
            Write-PwtHost ":" -NoNewline
            Write-PwtHost "C$col" -ForegroundColor Yellow -NoNewline
            Write-PwtHost "  $($err.Message)" -ForegroundColor Gray
        }

        # Functions list
        if ($Functions -and $ast) {
            $funcs = $ast.FindAll(
                { param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] },
                $false
            )
            if ($funcs.Count -gt 0) {
                foreach ($f in $funcs) {
                    Write-PwtHost "          " -NoNewline
                    Write-PwtHost "fn " -ForegroundColor DarkGray -NoNewline
                    Write-PwtHost $f.Name -ForegroundColor Cyan -NoNewline
                    Write-PwtHost "  L$($f.Extent.StartLineNumber)" -ForegroundColor DarkGray
                }
            }
        }
    }

    if (-not $Quiet) {
        Write-PwtHost ""
        $total = $files.Count
        $ok    = $total - $failed
        if ($failed -eq 0) {
            Write-PwtHost "  $ok/$total OK" -ForegroundColor Green
        } else {
            Write-PwtHost "  $ok/$total OK, $failed z błędami" -ForegroundColor Yellow
        }
        Write-PwtHost ""
    }

    $global:LASTEXITCODE = $failed
}

if (Get-Command Register-PwtCommand -ErrorAction SilentlyContinue) {
    Register-PwtCommand -Name 'parse' -Category 'dev' `
        -Synopsis 'Sprawdź składnię plików .ps1 (AST parser, bez wykonania)' `
        -Function 'Invoke-PwtParse'
}

