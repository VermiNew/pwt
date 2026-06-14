#!/usr/bin/env pwsh
#requires -Version 7.0

function Invoke-PwtDiffray {
<#
.SYNOPSIS
    Run Diffray code review presets for the current Git repository.

.DESCRIPTION
    Provides a small pwt wrapper around diffray review:
      - pwt diffray review quick : changed, staged and untracked files
      - pwt diffray review full  : all tracked files

    The wrapper filters common generated folders, lockfiles and binary/media
    assets, verifies required tools, and runs diffray with the opencode-cli
    executor.

.PARAMETER Command
    Subcommand. Currently only: review.

.PARAMETER Mode
    Review scope: quick or full.

.PARAMETER IncludeLocks
    Include lockfiles in the review file list.

.PARAMETER IncludeAssets
    Include binary/media assets in the review file list. SVG is treated as
    reviewable source by default and is not excluded.

.PARAMETER ListOnly
    Print the selected files without running diffray.

.EXAMPLE
    pwt diffray review quick

.EXAMPLE
    pwt diffray review full

.EXAMPLE
    pwt diffray review quick -ListOnly
#>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [ValidateSet('review', 'status', 'help')]
        [string]$Command = 'help',

        [Parameter(Position = 1)]
        [ValidateSet('quick', 'full')]
        [string]$Mode = 'quick',

        [switch]$IncludeLocks,
        [switch]$IncludeAssets,
        [switch]$ListOnly
    )

    switch ($Command) {
        'help' {
            Show-PwtDiffrayUsage
            return
        }
        'status' {
            Test-PwtDiffrayTools -VerboseStatus | Out-Null
            return
        }
        'review' {
            Invoke-PwtDiffrayReview -Mode $Mode -IncludeLocks:$IncludeLocks `
                -IncludeAssets:$IncludeAssets -ListOnly:$ListOnly
            return
        }
    }
}

function script:Invoke-PwtDiffrayReview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('quick', 'full')]
        [string]$Mode,

        [switch]$IncludeLocks,
        [switch]$IncludeAssets,
        [switch]$ListOnly
    )

    if (-not (Test-PwtDiffrayTools -VerboseStatus)) { return }

    try {
        $root = Get-PwtDiffrayGitRoot
    } catch {
        Write-PwtHost $_.Exception.Message -ForegroundColor Red
        return
    }

    Push-Location $root
    try {
        $changedOnly = $Mode -eq 'quick'
        $files = @(Get-PwtDiffrayReviewFiles -ChangedOnly:$changedOnly `
            -IncludeLocks:$IncludeLocks -IncludeAssets:$IncludeAssets)

        if ($files.Count -eq 0) {
            $msg = if ($changedOnly) {
                'Brak zmienionych plików do sprawdzenia.'
            } else {
                'Brak plików do sprawdzenia.'
            }
            Write-PwtHost $msg -ForegroundColor Yellow
            return
        }

        $fileArg = Join-PwtDiffrayFilesArgument -Files $files
        if (-not $fileArg) { return }

        $model = if ($Mode -eq 'quick') {
            'opencode-go/deepseek-v4-pro'
        } else {
            'opencode-go/kimi-k2.6'
        }

        Write-PwtHost ""
        Write-PwtHost ("  Diffray {0} review: {1} file(s)" -f $Mode, $files.Count) -ForegroundColor Cyan
        Write-PwtHost "  Repository: " -NoNewline -ForegroundColor Cyan
        Write-PwtHost $root -ForegroundColor White
        Write-PwtHost "  Executor:   " -NoNewline -ForegroundColor Cyan
        Write-PwtHost 'opencode-cli' -ForegroundColor White
        Write-PwtHost "  Model:      " -NoNewline -ForegroundColor Cyan
        Write-PwtHost $model -ForegroundColor White
        Write-PwtHost ""

        if ($ListOnly) {
            $files | ForEach-Object { Write-PwtHost "  $_" }
            Write-PwtHost ""
            return
        }

        $argv = @(
            'review',
            '--executor', 'opencode-cli',
            '--model', $model,
            '--full',
            '--files', $fileArg
        )

        & diffray @argv
        $global:LASTEXITCODE = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }
}

function script:Get-PwtDiffrayGitRoot {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw 'Git nie jest dostępny w PATH.'
    }

    $root = git rev-parse --show-toplevel 2>$null
    if (-not $root) {
        throw 'Nie jesteś w repozytorium Git.'
    }

    return "$root".Trim()
}

function script:Get-PwtDiffrayReviewFiles {
    param(
        [switch]$ChangedOnly,
        [switch]$IncludeLocks,
        [switch]$IncludeAssets
    )

    if ($ChangedOnly) {
        $files = @(
            git diff --name-only --diff-filter=ACMR
            git diff --cached --name-only --diff-filter=ACMR
            git ls-files --others --exclude-standard
        )
    } else {
        $files = git ls-files
    }

    $excludeDirs = '(^|/)(node_modules|vendor|dist|build|out|coverage|\.next|\.nuxt|\.svelte-kit|target|bin|obj|\.git)(/|$)'
    $excludeLocks = '(^|/)(package-lock\.json|pnpm-lock\.yaml|yarn\.lock|bun\.lockb|composer\.lock|Pipfile\.lock|poetry\.lock|Cargo\.lock)$'
    $excludeAssets = '\.(png|jpe?g|gif|webp|ico|mp3|wav|ogg|flac|mp4|mov|avi|mkv|zip|7z|rar|tar|gz|pdf|woff2?|ttf|otf|eot|wasm|dll|exe|bin)$'

    $files |
        Sort-Object -Unique |
        Where-Object {
            $_ -and
            (Test-Path -LiteralPath $_ -PathType Leaf) -and
            $_ -notmatch $excludeDirs -and
            $_ -notmatch '\.gitkeep$' -and
            ($IncludeLocks -or $_ -notmatch $excludeLocks) -and
            ($IncludeAssets -or $_ -notmatch $excludeAssets)
        }
}

function script:Join-PwtDiffrayFilesArgument {
    param([Parameter(Mandatory)][string[]]$Files)

    $bad = @($Files | Where-Object { $_ -match ',' })
    if ($bad.Count -gt 0) {
        Write-PwtHost ""
        Write-PwtHost "  Diffray przyjmuje --files jako listę rozdzielaną przecinkami." -ForegroundColor Red
        Write-PwtHost "  Te ścieżki zawierają przecinek i nie mogą być przekazane jednoznacznie:" -ForegroundColor Yellow
        $bad | ForEach-Object { Write-PwtHost "    $_" -ForegroundColor White }
        Write-PwtHost ""
        return $null
    }

    return ($Files -join ',')
}

function script:Test-PwtDiffrayTools {
    param([switch]$VerboseStatus)

    $checks = @(
        [PSCustomObject]@{ Name = 'git';      Command = 'git';      Required = $true; Hint = 'Install Git for Windows.' }
        [PSCustomObject]@{ Name = 'diffray';  Command = 'diffray';  Required = $true; Hint = 'Install diffray CLI.' }
        [PSCustomObject]@{ Name = 'opencode'; Command = 'opencode'; Required = $true; Hint = 'Install OpenCode CLI.' }
    )

    $ok = $true
    if ($VerboseStatus) {
        Write-PwtHost ""
        Write-PwtHost "  pwt diffray status" -ForegroundColor Cyan
        Write-PwtHost "  ------------------" -ForegroundColor DarkGray
    }

    foreach ($check in $checks) {
        $cmd = Get-Command $check.Command -ErrorAction SilentlyContinue
        if (-not $cmd) { $ok = $false }

        if ($VerboseStatus) {
            Write-PwtHost ("    {0,-8} " -f $check.Name) -NoNewline
            if ($cmd) {
                Write-PwtHost "[OK]      " -NoNewline -ForegroundColor Green
                Write-PwtHost $cmd.Source -ForegroundColor White
            } else {
                Write-PwtHost "[MISSING] " -NoNewline -ForegroundColor Red
                Write-PwtHost $check.Hint -ForegroundColor Yellow
            }
        }
    }

    if ($VerboseStatus) { Write-PwtHost "" }

    if (-not $ok -and -not $VerboseStatus) {
        Write-PwtHost ""
        Write-PwtHost "  Missing required tools for pwt diffray." -ForegroundColor Red
        Write-PwtHost "  Run: pwt diffray status" -ForegroundColor Yellow
        Write-PwtHost ""
    }

    return $ok
}

function script:Show-PwtDiffrayUsage {
    Write-PwtHost ""
    Write-PwtHost "  pwt diffray - Diffray review presets" -ForegroundColor Cyan
    Write-PwtHost "  ------------------------------------" -ForegroundColor DarkGray
    Write-PwtHost ""
    Write-PwtHost "  Usage:" -ForegroundColor Magenta
    Write-PwtHost "    pwt diffray review quick"
    Write-PwtHost "    pwt diffray review full"
    Write-PwtHost "    pwt diffray status"
    Write-PwtHost ""
    Write-PwtHost "  Options:" -ForegroundColor Magenta
    Write-PwtHost "    -IncludeLocks   Include lockfiles"
    Write-PwtHost "    -IncludeAssets  Include binary/media assets"
    Write-PwtHost "    -ListOnly       Print selected files without running diffray"
    Write-PwtHost ""
}

if (Get-Command Register-PwtCommand -ErrorAction SilentlyContinue) {
    Register-PwtCommand -Name 'diffray' -Category 'dev' `
        -Synopsis 'Run Diffray review presets for Git repositories' `
        -Function 'Invoke-PwtDiffray' `
        -Requires @('git', 'diffray', 'opencode')
}

