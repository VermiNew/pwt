#!/usr/bin/env pwsh
#requires -Version 7.0

$script:ParseScriptsDir = $PSScriptRoot

function Invoke-PwtParse {
<#
.SYNOPSIS
    Check the syntax of .ps1 files (PowerShell AST parser) without executing them.

.DESCRIPTION
    Static validation: uses [System.Management.Automation.Language.Parser]
    to parse a file and reports syntax errors with line and column numbers.
    Never executes code — safe for unknown scripts.

    Without arguments, checks all pwt-*.ps1 files in the Scripts directory.
    With -Functions, lists the top-level functions defined in each file
    (useful for a quick structural overview).

    Exit status: $LASTEXITCODE = number of files with errors (0 = all OK).

.PARAMETER Path
    A .ps1 file or directory. Multiple values accepted. Default: all Scripts/pwt-*.ps1.

.PARAMETER Functions
    List top-level functions defined in each checked file.

.PARAMETER Quiet
    No output, exit code only (0 = OK, N = number of files with errors).

.PARAMETER Recurse
    For directories: search recursively (default: top-level only).

.EXAMPLE
    pwt parse
    Check all pwt-*.ps1 files in Scripts/.

.EXAMPLE
    pwt parse .\Scripts\pwt-phone.ps1
    Check a specific file.

.EXAMPLE
    pwt parse .\Scripts\pwt-phone.ps1 -Functions
    Check syntax and list top-level functions.

.EXAMPLE
    pwt parse .\Modules -Recurse
    Recursively check all .ps1/.psm1 files in a directory.
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
        Get-ChildItem -Path $script:ParseScriptsDir -Filter 'pwt-*.ps1' -File |
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
            Write-PwtHost "  No files to check." -ForegroundColor Yellow
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
            Write-PwtHost "$($errors.Count) error(s)" -ForegroundColor Red
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
            Write-PwtHost "  $ok/$total OK, $failed with errors" -ForegroundColor Yellow
        }
        Write-PwtHost ""
    }

    $global:LASTEXITCODE = $failed
}

if (Get-Command Register-PwtCommand -ErrorAction SilentlyContinue) {
    Register-PwtCommand -Name 'parse' -Category 'dev' `
        -Synopsis 'Check .ps1 file syntax (AST parser, no execution)' `
        -Function 'Invoke-PwtParse'
}
