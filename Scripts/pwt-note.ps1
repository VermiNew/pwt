#!/usr/bin/env pwsh
#requires -Version 7.0

function Invoke-PwtNote {
<#
.SYNOPSIS
    Quick timestamped notes appended to ~/Documents/notes.md.

.DESCRIPTION
    Appends a markdown entry with a timestamp header to one rolling notes
    file. Without arguments, opens the file in edit.exe (fallback: notepad)
    so you can browse/edit existing notes.

    File location: $env:USERPROFILE\Documents\notes.md

.PARAMETER Text
    Note text. Multiple words are joined with spaces. Omit to open the file
    in the editor instead.

.PARAMETER Tag
    Optional tag suffix appended after the timestamp (e.g. -Tag idea).

.PARAMETER Show
    Print the entire notes file to the terminal (no append).

.PARAMETER Tail
    Print only the last N lines of the notes file.

.EXAMPLE
    pwt note "Remember to refactor pinggy auth tomorrow"
    Append a note with current timestamp.

.EXAMPLE
    pwt note -Tag idea "use SSE instead of polling for updates"
    Append a tagged note.

.EXAMPLE
    pwt note
    Open notes.md in edit.exe.

.EXAMPLE
    pwt note -Tail 30
    Show last 30 lines.
#>
    [CmdletBinding(DefaultParameterSetName = 'Append')]
    param(
        [Parameter(Position = 0, ValueFromRemainingArguments, ParameterSetName = 'Append')]
        [string[]]$Text,

        [Parameter(ParameterSetName = 'Append')]
        [string]$Tag,

        [Parameter(ParameterSetName = 'Show')]
        [switch]$Show,

        [Parameter(ParameterSetName = 'Tail')]
        [int]$Tail
    )

    $notesPath = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'notes.md'

    # Ensure the file exists with a header.
    if (-not (Test-Path $notesPath)) {
        Set-Content -LiteralPath $notesPath `
            -Value "# Notes`n`n_Created $(Get-Date -Format 'yyyy-MM-dd HH:mm')_`n" `
            -Encoding UTF8
    }

    if ($Show) {
        Get-Content -LiteralPath $notesPath -Encoding UTF8 | Write-PwtHost
        return
    }

    if ($Tail -gt 0) {
        Get-Content -LiteralPath $notesPath -Encoding UTF8 -Tail $Tail | Write-PwtHost
        return
    }

    if (-not $Text -or $Text.Count -eq 0) {
        # Open the file in the editor.
        if (Get-Command edit.exe -ErrorAction SilentlyContinue) {
            & edit.exe $notesPath
        } else {
            Write-PwtHost "edit.exe not found, opening in notepad." -ForegroundColor Yellow
            & notepad $notesPath
        }
        return
    }

    $body = ($Text -join ' ').Trim()
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm'
    $header = if ($Tag) { "## $timestamp [$Tag]" } else { "## $timestamp" }
    $entry = "`n$header`n`n$body`n"

    Add-Content -LiteralPath $notesPath -Value $entry -Encoding UTF8

    Write-PwtHost ""
    Write-PwtHost "  Note saved to: $notesPath" -ForegroundColor Green
    if ($Tag) {
        Write-PwtHost "  Tag:  $Tag" -ForegroundColor Cyan
    }
    Write-PwtHost "  Time: $timestamp" -ForegroundColor DarkGray
    Write-PwtHost ""
}

if (Get-Command Register-PwtCommand -ErrorAction SilentlyContinue) {
    Register-PwtCommand -Name 'note' -Category 'misc' `
        -Synopsis 'Append timestamped notes to ~/Documents/notes.md' `
        -Function 'Invoke-PwtNote'
}

