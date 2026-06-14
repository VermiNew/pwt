#!/usr/bin/env pwsh
#requires -Version 7.0

function Invoke-PwtClipFile {
<#
.SYNOPSIS
    Read a file's text content into the clipboard.

.DESCRIPTION
    Pastes the contents of a text file into the system clipboard. Useful for
    quickly sharing logs, scripts, or any text into a chat / LLM / editor.
    Binary files are rejected (use Set-Clipboard manually for special needs).

.PARAMETER Path
    Path to the file to read.

.PARAMETER Encoding
    File encoding (default: UTF8).

.EXAMPLE
    pwt clipfile error.log
    Copy the entire log file into clipboard.

.EXAMPLE
    pwt clipfile C:\Project\README.md
    Copy a markdown file into clipboard.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Path,

        [string]$Encoding = 'UTF8'
    )

    if (-not (Test-Path $Path -PathType Leaf)) {
        Write-PwtHost "Not a file: $Path" -ForegroundColor Red
        return
    }

    $resolved = (Resolve-Path $Path).Path
    $info = Get-Item $resolved

    # Crude binary detection: scan first 4KB for null bytes.
    try {
        $stream = [System.IO.File]::OpenRead($resolved)
        $buffer = New-Object byte[] 4096
        $bytes = $stream.Read($buffer, 0, 4096)
        $stream.Dispose()
        if ($bytes -gt 0 -and ([Array]::IndexOf($buffer, [byte]0, 0, $bytes) -ge 0)) {
            Write-PwtHost "Refusing to copy binary file: $resolved" -ForegroundColor Red
            Write-PwtHost "(use Set-Clipboard with -AsHtml or other tooling for binary)" -ForegroundColor DarkGray
            return
        }
    } catch {
        Write-PwtHost "Could not read file: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    try {
        $content = Get-Content -LiteralPath $resolved -Raw -Encoding $Encoding -ErrorAction Stop
    } catch {
        Write-PwtHost "Read failed: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    try {
        Set-Clipboard -Value $content -ErrorAction Stop
    } catch {
        Write-PwtHost "Clipboard not available: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    Write-PwtHost ""
    Write-PwtHost "  Copied to clipboard:" -ForegroundColor Green
    Write-PwtHost "    File:  $resolved"
    Write-PwtHost "    Size:  $(Format-PwtSize $info.Length)"
    Write-PwtHost "    Lines: $(($content -split "`n").Count)"
    Write-PwtHost ""
}

if (Get-Command Register-PwtCommand -ErrorAction SilentlyContinue) {
    Register-PwtCommand -Name 'clipfile' -Category 'clipboard' `
        -Synopsis 'Copy a text file content into the clipboard' `
        -Function 'Invoke-PwtClipFile'
}

