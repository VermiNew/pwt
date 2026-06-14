#!/usr/bin/env pwsh
#requires -Version 7.0

function Invoke-PwtCleanup {
<#
.SYNOPSIS
    Remove build artifacts and dependency caches from a project tree.

.DESCRIPTION
    Recursively finds and deletes common build/cache directories:
      node_modules, dist, .next, out, build, .nuxt, .output
      __pycache__, .pytest_cache, .mypy_cache, .ruff_cache, *.egg-info
      .gradle, .kotlin, bin, obj  (C#/Java)
      target  (Rust/Java Maven)

    Runs in dry-run mode by default — shows what would be deleted
    without removing anything. Pass -Force to actually delete.

.PARAMETER Path
    Root directory to scan (default: current directory).

.PARAMETER Force
    Actually delete the matched directories/files. Without this flag
    the command only lists what it would remove.

.PARAMETER Include
    Limit to specific pattern groups: js, python, dotnet, rust.
    Default: all groups.

.PARAMETER Depth
    Maximum directory depth to scan (default: 6).

.EXAMPLE
    pwt cleanup
    Show what would be removed in the current directory (dry run).

.EXAMPLE
    pwt cleanup -Force
    Remove all artifacts in the current directory.

.EXAMPLE
    pwt cleanup D:\Projects -Force -Include js
    Remove only JS artifacts under D:\Projects.

.EXAMPLE
    pwt cleanup -Force -Depth 2
    Remove artifacts, but don't descend more than 2 levels deep.
#>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Position = 0)]
        [string]$Path = '.',

        [switch]$Force,

        [ValidateSet('js', 'python', 'dotnet', 'rust', 'all')]
        [string[]]$Include = @('all'),

        [int]$Depth = 6
    )

    $all = $Include -contains 'all'

    $targets = [System.Collections.Generic.List[PSCustomObject]]::new()

    if ($all -or $Include -contains 'js') {
        foreach ($n in @('node_modules', 'dist', '.next', 'out', 'build', '.nuxt', '.output', '.turbo', '.svelte-kit', '.vite')) {
            $targets.Add([PSCustomObject]@{ Name = $n; Type = 'dir'; Group = 'js' })
        }
    }
    if ($all -or $Include -contains 'python') {
        foreach ($n in @('__pycache__', '.pytest_cache', '.mypy_cache', '.ruff_cache', '.tox', 'htmlcov')) {
            $targets.Add([PSCustomObject]@{ Name = $n; Type = 'dir'; Group = 'python' })
        }
        $targets.Add([PSCustomObject]@{ Name = '*.egg-info'; Type = 'glob-dir'; Group = 'python' })
        $targets.Add([PSCustomObject]@{ Name = '*.pyc';      Type = 'glob-file'; Group = 'python' })
    }
    if ($all -or $Include -contains 'dotnet') {
        foreach ($n in @('bin', 'obj')) {
            $targets.Add([PSCustomObject]@{ Name = $n; Type = 'dir'; Group = 'dotnet' })
        }
    }
    if ($all -or $Include -contains 'rust') {
        $targets.Add([PSCustomObject]@{ Name = 'target'; Type = 'dir'; Group = 'rust' })
    }

    if (-not (Test-Path $Path)) {
        Write-PwtHost "  Path not found: $Path" -Style Error
        return
    }
    $resolved = (Resolve-Path $Path).Path

    Write-PwtHost ""
    Write-PwtHost "  Scanning: " -NoNewline -Style Accent
    Write-PwtHost $resolved -Style Text
    if (-not $Force) {
        Write-PwtHost "  Dry run — pass -Force to actually delete." -Style Warn
    }
    Write-PwtHost ""

    $found   = [System.Collections.Generic.List[PSCustomObject]]::new()
    $totalSz = 0L

    foreach ($t in $targets) {
        $gciArgs = @{
            Path        = $resolved
            Recurse     = $true
            Depth       = $Depth
            ErrorAction = 'SilentlyContinue'
            Force       = $true
        }

        switch ($t.Type) {
            'dir' {
                $gciArgs['Directory'] = $true
                $gciArgs['Filter']    = $t.Name
                Get-ChildItem @gciArgs | ForEach-Object {
                    $sz = (Get-ChildItem $_.FullName -Recurse -File -EA SilentlyContinue |
                           Measure-Object Length -Sum).Sum ?? 0L
                    $found.Add([PSCustomObject]@{ Path = $_.FullName; Size = $sz; Group = $t.Group })
                    $totalSz += $sz
                }
            }
            'glob-dir' {
                $gciArgs['Directory'] = $true
                $gciArgs['Filter']    = $t.Name
                Get-ChildItem @gciArgs | ForEach-Object {
                    $sz = (Get-ChildItem $_.FullName -Recurse -File -EA SilentlyContinue |
                           Measure-Object Length -Sum).Sum ?? 0L
                    $found.Add([PSCustomObject]@{ Path = $_.FullName; Size = $sz; Group = $t.Group })
                    $totalSz += $sz
                }
            }
            'glob-file' {
                $gciArgs['File']   = $true
                $gciArgs['Filter'] = $t.Name
                Get-ChildItem @gciArgs | ForEach-Object {
                    $found.Add([PSCustomObject]@{ Path = $_.FullName; Size = $_.Length; Group = $t.Group })
                    $totalSz += $_.Length
                }
            }
        }
    }

    # Deduplicate — skip entries whose parent is already in the list
    $paths = $found | Select-Object -ExpandProperty Path | Sort-Object
    $deduped = $found | Where-Object {
        $p = $_.Path
        -not ($paths | Where-Object { $_ -ne $p -and $p.StartsWith($_ + '\') })
    }

    if ($deduped.Count -eq 0) {
        Write-PwtHost "  Nothing to clean up." -Style Ok
        Write-PwtHost ""
        return
    }

    # Print grouped
    $byGroup = $deduped | Group-Object Group
    foreach ($g in $byGroup) {
        Write-PwtHost "  $($g.Name.ToUpper())" -Style Heading
        foreach ($item in $g.Group) {
            $sizeStr = Format-PwtSize $item.Size
            Write-PwtHost "    " -NoNewline
            Write-PwtHost ("{0,8}  " -f $sizeStr) -NoNewline -Style Muted
            Write-PwtHost $item.Path -Style Text
        }
    }

    Write-PwtHost ""
    $totalStr = Format-PwtSize $totalSz
    Write-PwtHost "  $($deduped.Count) item(s)  " -NoNewline -Style Muted
    Write-PwtHost $totalStr -Style Warn

    if (-not $Force) {
        Write-PwtHost ""
        Write-PwtHost "  Run with -Force to delete." -Style Muted
        Write-PwtHost ""
        return
    }

    Write-PwtHost ""
    $errors = 0
    foreach ($item in $deduped) {
        try {
            Remove-Item -LiteralPath $item.Path -Recurse -Force -EA Stop
            Write-PwtHost "  ✔ " -NoNewline -Style Ok
            Write-PwtHost $item.Path -Style Muted
        }
        catch {
            Write-PwtHost "  ✘ " -NoNewline -Style Error
            Write-PwtHost "$($item.Path): $($_.Exception.Message)" -Style Error
            $errors++
        }
    }

    Write-PwtHost ""
    if ($errors -eq 0) {
        Write-PwtHost "  Done — $($deduped.Count) item(s) removed, $totalStr freed." -Style Ok
    } else {
        Write-PwtHost "  Done — $errors error(s)." -Style Warn
    }
    Write-PwtHost ""
}

if (Get-Command Register-PwtCommand -ErrorAction SilentlyContinue) {
    Register-PwtCommand -Name 'cleanup' -Category 'dev' `
        -Synopsis 'Remove build artifacts and dependency caches (node_modules, dist, __pycache__, …)' `
        -Function 'Invoke-PwtCleanup'
}
