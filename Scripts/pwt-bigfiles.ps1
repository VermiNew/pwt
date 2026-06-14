#!/usr/bin/env pwsh
#requires -Version 7.0

function Invoke-PwtBigFiles {
<#
.SYNOPSIS
    Find the largest files in a directory tree.

.DESCRIPTION
    Recursively scans a path and returns the top N largest files, sorted
    by size with human-readable units. Handy when a drive is suddenly full.

.PARAMETER Path
    Directory to scan (default: current directory).

.PARAMETER Top
    How many entries to return (default: 20).

.PARAMETER Filter
    Optional Get-ChildItem -Filter expression (e.g. *.log).

.PARAMETER MinSizeMB
    Skip files smaller than this many MB (default: 0).

.EXAMPLE
    pwt bigfiles
    Top 20 largest files in current directory.

.EXAMPLE
    pwt bigfiles C:\Users\Michael\Downloads -Top 50
    Top 50 in Downloads.

.EXAMPLE
    pwt bigfiles -Filter *.iso -MinSizeMB 100
    Only ISOs at least 100 MB.
#>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Path = '.',

        [int]$Top = 20,

        [string]$Filter,

        [double]$MinSizeMB = 0
    )

    if (-not (Test-Path $Path)) {
        Write-PwtHost "Path not found: $Path" -ForegroundColor Red
        return
    }

    $resolved = (Resolve-Path $Path).Path
    Write-PwtHost ""
    Write-PwtHost "  Scanning: " -NoNewline -ForegroundColor Cyan
    Write-PwtHost $resolved -ForegroundColor White
    Write-PwtHost "  (this may take a while on large trees...)" -ForegroundColor DarkGray
    Write-PwtHost ""

    $gciParams = @{
        Path        = $resolved
        File        = $true
        Recurse     = $true
        ErrorAction = 'SilentlyContinue'
    }
    if ($Filter) { $gciParams['Filter'] = $Filter }

    $minBytes = $MinSizeMB * 1MB

    $files = Get-ChildItem @gciParams |
        Where-Object { $_.Length -ge $minBytes } |
        Sort-Object Length -Descending |
        Select-Object -First $Top

    if (-not $files) {
        Write-PwtHost "  No files matched." -ForegroundColor Yellow
        Write-PwtHost ""
        return
    }

    $rows = $files | ForEach-Object {
        [PSCustomObject]@{
            Size     = (Format-PwtSize $_.Length)
            Modified = $_.LastWriteTime.ToString('yyyy-MM-dd HH:mm')
            Path     = $_.FullName
        }
    }

    $rows | Format-Table -AutoSize

    $total = ($files | Measure-Object Length -Sum).Sum
    Write-PwtHost "  Total of top $($files.Count): " -NoNewline -ForegroundColor Cyan
    Write-PwtHost (Format-PwtSize $total) -ForegroundColor White
    Write-PwtHost ""
}

if (Get-Command Register-PwtCommand -ErrorAction SilentlyContinue) {
    Register-PwtCommand -Name 'bigfiles' -Category 'files' `
        -Synopsis 'List the largest files in a directory tree' `
        -Function 'Invoke-PwtBigFiles'
}

