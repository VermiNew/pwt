#!/usr/bin/env pwsh
#requires -Version 7.0

function Invoke-PwtWhichInPath {
<#
.SYNOPSIS
    Locate every occurrence of a command in PATH (and built-ins).

.DESCRIPTION
    Like 'which' on Unix, but lists ALL matches (so you can spot shadowed
    binaries when, e.g., two node.exe live in different folders). Also
    reports aliases and PowerShell functions of the same name.

.PARAMETER Name
    Command name to look up (with or without extension).

.PARAMETER ExternalOnly
    Only show executables/scripts on PATH; skip aliases/functions/cmdlets.

.EXAMPLE
    pwt whichinpath node
    Show all node.exe in PATH plus any alias/function called 'node'.

.EXAMPLE
    pwt whichinpath python -ExternalOnly
    Only show python files found in PATH.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [switch]$ExternalOnly
    )

    $found = @(Get-Command $Name -All -ErrorAction SilentlyContinue)

    if ($ExternalOnly) {
        $found = $found | Where-Object { $_.CommandType -in 'Application','ExternalScript' }
    }

    if (-not $found) {
        Write-PwtHost ""
        Write-PwtHost "  Not found: " -ForegroundColor Yellow -NoNewline
        Write-PwtHost $Name -ForegroundColor White
        Write-PwtHost ""
        return
    }

    Write-PwtHost ""
    Write-PwtHost "  Matches for '" -NoNewline
    Write-PwtHost $Name -ForegroundColor Cyan -NoNewline
    Write-PwtHost "':" -ForegroundColor White
    Write-PwtHost ""

    $i = 0
    foreach ($cmd in $found) {
        $i++
        $marker = if ($i -eq 1) { '*' } else { ' ' }   # active one is first
        $type   = $cmd.CommandType.ToString().PadRight(15)

        $location = switch ($cmd.CommandType) {
            'Application'    { $cmd.Source }
            'ExternalScript' { $cmd.Source }
            'Alias'          { "-> $($cmd.Definition)" }
            'Function'       { "(function)" }
            'Cmdlet'         { "(cmdlet from $($cmd.ModuleName))" }
            default          { $cmd.Source }
        }

        Write-PwtHost "  $marker " -NoNewline -ForegroundColor Green
        Write-PwtHost $type      -NoNewline -ForegroundColor Magenta
        Write-PwtHost $location
    }
    Write-PwtHost ""
    Write-PwtHost "  (* = the one that runs when you type the name)" -ForegroundColor DarkGray
    Write-PwtHost ""
}

if (Get-Command Register-PwtCommand -ErrorAction SilentlyContinue) {
    Register-PwtCommand -Name 'whichinpath' -Category 'system' `
        -Synopsis 'Show every match for a command (PATH + aliases + functions)' `
        -Function 'Invoke-PwtWhichInPath'
}

