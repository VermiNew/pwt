#!/usr/bin/env pwsh
#requires -Version 7.0
<#
.SYNOPSIS
    PowerShell Tools (pwt) - core registry and dispatcher.

.DESCRIPTION
    Provides:
      - Command registry (Register-PwtCommand)
      - Tool dependency check helper (Test-PwtTool)
      - Main 'pwt' dispatcher with built-ins: list, help, edit, reload
      - Tab-completion for sub-commands and topics

    Each pwt-*.ps1 script in Scripts/ should call Register-PwtCommand to
    appear in 'pwt list' / 'pwt help'.
#>

# ============================================================================
# REGISTRY (global so it survives across dot-sourced files & reloads)
# ============================================================================

# Reset on every load so 'pwt reload' yields a clean state.
$global:PwtCommands = [ordered]@{}

# PowerShell 7+ gives us ANSI rendering and truecolor via $PSStyle. Keep this
# central so future tools can use one palette instead of scattered ConsoleColor
# choices.
if ($PSStyle -and $PSStyle.OutputRendering -ne 'PlainText') {
    $PSStyle.OutputRendering = 'Ansi'
}

$global:PwtTheme = @{
    Reset   = $PSStyle.Reset
    Accent  = $PSStyle.Foreground.FromRgb(0x38, 0xBD, 0xF8)
    Info    = $PSStyle.Foreground.FromRgb(0x7D, 0xD3, 0xFC)
    Ok      = $PSStyle.Foreground.FromRgb(0x4A, 0xD9, 0xA1)
    Warn    = $PSStyle.Foreground.FromRgb(0xF7, 0xC9, 0x48)
    Error   = $PSStyle.Foreground.FromRgb(0xFF, 0x6B, 0x6B)
    Muted   = $PSStyle.Foreground.FromRgb(0x8A, 0x94, 0xA7)
    Heading = $PSStyle.Foreground.FromRgb(0xC0, 0x8C, 0xFF)
    Text    = $PSStyle.Foreground.FromRgb(0xE6, 0xEA, 0xF2)
}

function Get-PwtAnsiColor {
    [CmdletBinding()]
    param(
        [AllowNull()]
        $Color,

        [switch]$Background
    )

    if ($null -eq $Color) { return $null }

    $name = if ($Color -is [ConsoleColor]) { $Color.ToString() } else { [string]$Color }
    $rgb = switch ($name) {
        'Black'       { @(0x00, 0x00, 0x00) }
        'DarkBlue'    { @(0x1E, 0x3A, 0x8A) }
        'DarkGreen'   { @(0x16, 0x65, 0x34) }
        'DarkCyan'    { @(0x0E, 0x74, 0x8A) }
        'DarkRed'     { @(0x99, 0x1B, 0x1B) }
        'DarkMagenta' { @(0x86, 0x1A, 0xA8) }
        'DarkYellow'  { @(0xA1, 0x62, 0x07) }
        'Gray'        { @(0x9C, 0xA3, 0xAF) }
        'DarkGray'    { @(0x6B, 0x72, 0x80) }
        'Blue'        { @(0x60, 0xA5, 0xFA) }
        'Green'       { @(0x4A, 0xD9, 0xA1) }
        'Cyan'        { @(0x38, 0xBD, 0xF8) }
        'Red'         { @(0xFF, 0x6B, 0x6B) }
        'Magenta'     { @(0xC0, 0x8C, 0xFF) }
        'Yellow'      { @(0xF7, 0xC9, 0x48) }
        'White'       { @(0xE6, 0xEA, 0xF2) }
        default       { return $null }
    }

    if ($Background) {
        return $PSStyle.Background.FromRgb($rgb[0], $rgb[1], $rgb[2])
    }
    return $PSStyle.Foreground.FromRgb($rgb[0], $rgb[1], $rgb[2])
}

function Write-PwtHost {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true)]
        [AllowNull()]
        [object]$Object = '',

        [ValidateSet('Accent', 'Info', 'Ok', 'Warn', 'Error', 'Muted', 'Heading', 'Text')]
        [string]$Style,

        [AllowNull()]
        $ForegroundColor,

        [AllowNull()]
        $BackgroundColor,

        [object]$Separator = ' ',

        [switch]$NoNewline
    )

    process {
        $text = if ($Object -is [array]) {
            $Object -join [string]$Separator
        } else {
            [string]$Object
        }

        $prefix = ''
        if ($Style) {
            $prefix += $global:PwtTheme[$Style]
        }
        if ($PSBoundParameters.ContainsKey('ForegroundColor')) {
            $prefix += Get-PwtAnsiColor -Color $ForegroundColor
        }
        if ($PSBoundParameters.ContainsKey('BackgroundColor')) {
            $prefix += Get-PwtAnsiColor -Color $BackgroundColor -Background
        }

        $reset = if ($prefix) { $global:PwtTheme.Reset } else { '' }
        Microsoft.PowerShell.Utility\Write-Host "$prefix$text$reset" -NoNewline:$NoNewline
    }
}

$script:PwtCategoryOrder = @(
    'system', 'network', 'files', 'clipboard',
    'download', 'dev', 'phone', 'printer', 'misc'
)

function Register-PwtCommand {
<#
.SYNOPSIS
    Registers a command with the pwt dispatcher.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Synopsis,
        [Parameter(Mandatory)][string]$Function,
        [string]$Category = 'misc',
        [string[]]$Requires = @(),
        [string]$ScriptPath
    )

    # Auto-detect caller script path if not supplied
    if (-not $ScriptPath) {
        $caller = (Get-PSCallStack)[1]
        if ($caller -and $caller.ScriptName) {
            $ScriptPath = $caller.ScriptName
        }
    }

    $global:PwtCommands[$Name] = [PSCustomObject]@{
        Name       = $Name
        Synopsis   = $Synopsis
        Function   = $Function
        Category   = $Category
        Requires   = $Requires
        ScriptPath = $ScriptPath
        Loaded     = $true   # loaded immediately when called from dot-sourced script
    }
}

# ============================================================================
# TOOL DEPENDENCY CHECK
# ============================================================================

function Test-PwtTool {
<#
.SYNOPSIS
    Verifies an external tool is on PATH; if missing, prints install hints.
.OUTPUTS
    [bool] - $true if tool is available, $false otherwise.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$Description,
        [string]$Winget,
        [string]$Module,
        [string]$Url
    )

    if (Get-Command $Name -ErrorAction SilentlyContinue) {
        return $true
    }

    Write-PwtHost ""
    Write-PwtHost "  [MISSING] " -ForegroundColor Red -NoNewline
    Write-PwtHost "Tool not found: " -NoNewline
    Write-PwtHost $Name -ForegroundColor White
    if ($Description) {
        Write-PwtHost "  $Description" -ForegroundColor Gray
    }
    Write-PwtHost ""
    Write-PwtHost "  Install via:" -ForegroundColor Yellow
    if ($Winget)  { Write-PwtHost "    winget install $Winget" -ForegroundColor Cyan }
    if ($Module)  { Write-PwtHost "    Install-Module $Module -Scope CurrentUser" -ForegroundColor Cyan }
    if ($Url)     { Write-PwtHost "    More info: $Url" -ForegroundColor Cyan }
    Write-PwtHost ""

    return $false
}

# ============================================================================
# SHARED HELPERS
# ============================================================================

function Format-PwtSize {
<#
.SYNOPSIS
    Convert a byte count to a short human-readable string (KB/MB/GB/TB).
#>
    [CmdletBinding()]
    param([Parameter(Mandatory)][long]$Bytes)

    switch ($Bytes) {
        { $_ -ge 1TB } { return ('{0:N2} TB' -f ($Bytes / 1TB)) }
        { $_ -ge 1GB } { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
        { $_ -ge 1MB } { return ('{0:N2} MB' -f ($Bytes / 1MB)) }
        { $_ -ge 1KB } { return ('{0:N2} KB' -f ($Bytes / 1KB)) }
        default        { return "$Bytes B" }
    }
}

function Test-PwtAdmin {
<#
.SYNOPSIS
    Returns $true if the current PowerShell session is running elevated.
#>
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [System.Security.Principal.WindowsPrincipal]::new($id)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-PwtSudoPath {
<#
.SYNOPSIS
    Returns the path to Microsoft's Windows 11 sudo.exe if available
    AND enabled, else $null. Only the official System32 sudo is honored
    (gsudo, scoop sudo, etc. are intentionally ignored to avoid surprises).
#>
    $sudo = Join-Path $env:SystemRoot 'System32\sudo.exe'
    if (-not (Test-Path $sudo)) { return $null }

    # Check enabled state in registry. Value 'Enabled' = 0 means disabled.
    try {
        $key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Sudo'
        if (Test-Path $key) {
            $val = (Get-ItemProperty -Path $key -Name 'Enabled' -ErrorAction SilentlyContinue).Enabled
            # 0 = disabled, anything else (1/2/3 = different modes) = enabled
            if ($null -ne $val -and $val -eq 0) { return $null }
        }
    } catch {}

    return $sudo
}

function Invoke-PwtElevated {
<#
.SYNOPSIS
    Re-runs a script-block in an elevated pwsh session via Windows 11 sudo.
.DESCRIPTION
    If sudo.exe is available and enabled, launches:
        sudo pwsh -NoProfile -Command "<script>"
    Returns $true if elevation was attempted, $false if sudo is unavailable
    (caller should print a manual-relaunch hint).
.PARAMETER Command
    Either a script block or a string with the PowerShell command to run.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Command
    )

    $sudo = Get-PwtSudoPath
    if (-not $sudo) { return $false }

    $cmdText = if ($Command -is [scriptblock]) { $Command.ToString() } else { [string]$Command }

    Write-PwtHost ""
    Write-PwtHost "  Re-launching elevated via sudo..." -ForegroundColor Yellow
    Write-PwtHost ""

    & $sudo pwsh -NoProfile -Command $cmdText
    return $true
}

# ============================================================================
# LAZY REGISTRY — scan pwt-*.ps1 files with regex, no execution at startup
# ============================================================================

function Initialize-PwtLazyRegistry {
<#
.SYNOPSIS
    Scans pwt-*.ps1 scripts for Register-PwtCommand metadata without executing them.
    Commands are registered as stubs (Loaded = $false) and dot-sourced on first use.
#>
    param([Parameter(Mandatory)][string]$ScriptsDir)

    Get-ChildItem "$ScriptsDir\pwt-*.ps1" -ErrorAction SilentlyContinue | ForEach-Object {
        $scriptPath = $_.FullName
        $content = Get-Content $scriptPath -Raw -ErrorAction SilentlyContinue
        if (-not $content) { return }

        # Match the Register-PwtCommand block (may span multiple lines via backtick)
        if ($content -notmatch '(?s)Register-PwtCommand\b(.+?)(?=\n[^\s`]|\Z)') { return }
        $block = $matches[0]

        $name     = if ($block -match "-Name\s+'([^']+)'")     { $matches[1] } else { return }
        $synopsis = if ($block -match "-Synopsis\s+'([^']+)'") { $matches[1] } else { '' }
        $function = if ($block -match "-Function\s+'([^']+)'") { $matches[1] } else { return }
        $category = if ($block -match "-Category\s+'([^']+)'") { $matches[1] } else { 'misc' }
        $requires = @()
        if ($block -match "-Requires\s+@\(([^)]+)\)") {
            $requires = $matches[1] -split ',\s*' | ForEach-Object { $_.Trim().Trim("'`"") }
        }

        # Only register if not already loaded (dot-sourced scripts register themselves with Loaded=$true)
        if (-not $global:PwtCommands.Contains($name)) {
            $global:PwtCommands[$name] = [PSCustomObject]@{
                Name       = $name
                Synopsis   = $synopsis
                Function   = $function
                Category   = $category
                Requires   = $requires
                ScriptPath = $scriptPath
                Loaded     = $false   # will be dot-sourced on first use
            }
        }
    }
}

# ============================================================================
# BUILT-INS: list / help / edit / reload
# ============================================================================

function script:Show-PwtList {
    param([string]$Category)

    Write-PwtHost ""
    Write-PwtHost "  pwt - PowerShell Tools" -ForegroundColor Cyan
    Write-PwtHost "  -----------------------------------------------------" -ForegroundColor DarkGray
    Write-PwtHost ""

    Write-PwtHost "  BUILT-IN" -ForegroundColor Magenta
    Write-PwtHost ("    {0,-14} {1}" -f 'list',   'List all available commands')
    Write-PwtHost ("    {0,-14} {1}" -f 'help',   'Show help for a command (or all)')
    Write-PwtHost ("    {0,-14} {1}" -f 'edit',   'Open command source in edit.exe')
    Write-PwtHost ("    {0,-14} {1}" -f 'reload', 'Reload PowerShell profile')
    Write-PwtHost ""

    if ($global:PwtCommands.Count -eq 0) {
        Write-PwtHost "  (no commands registered yet)" -ForegroundColor DarkGray
        Write-PwtHost ""
        return
    }

    $commands = $global:PwtCommands.Values
    if ($Category) {
        $commands = $commands | Where-Object { $_.Category -eq $Category }
    }

    $groups = $commands | Group-Object Category
    $ordered = @()
    foreach ($cat in $script:PwtCategoryOrder) {
        $g = $groups | Where-Object { $_.Name -eq $cat }
        if ($g) { $ordered += $g }
    }
    foreach ($g in $groups) {
        if ($script:PwtCategoryOrder -notcontains $g.Name) { $ordered += $g }
    }

    foreach ($group in $ordered) {
        Write-PwtHost "  $($group.Name.ToUpper())" -ForegroundColor Magenta
        $group.Group | Sort-Object Name | ForEach-Object {
            Write-PwtHost ("    {0,-14} {1}" -f $_.Name, $_.Synopsis)
        }
        Write-PwtHost ""
    }

    Write-PwtHost "  Use 'pwt help <name>' for details." -ForegroundColor DarkGray
    Write-PwtHost ""
}

function script:Show-PwtHelp {
    param([string]$Name)

    if (-not $Name) {
        Show-PwtList
        return
    }

    $cmd = $global:PwtCommands[$Name]
    if (-not $cmd) {
        Write-PwtHost "Unknown command: $Name" -ForegroundColor Red
        Write-PwtHost "Try 'pwt list'." -ForegroundColor Yellow
        return
    }

    if (Get-Command $cmd.Function -ErrorAction SilentlyContinue) {
        Get-Help $cmd.Function -Detailed
    } else {
        Write-PwtHost "Function not loaded: $($cmd.Function)" -ForegroundColor Red
    }
}

function script:Invoke-PwtEdit {
    param([string]$Name)

    if (-not $Name) {
        Write-PwtHost "Usage: pwt edit <command>" -ForegroundColor Yellow
        return
    }

    $cmd = $global:PwtCommands[$Name]
    if (-not $cmd) {
        Write-PwtHost "Unknown command: $Name" -ForegroundColor Red
        return
    }

    if (-not $cmd.ScriptPath -or -not (Test-Path $cmd.ScriptPath)) {
        Write-PwtHost "Script path not found for: $Name" -ForegroundColor Red
        return
    }

    if (Get-Command edit.exe -ErrorAction SilentlyContinue) {
        & edit.exe $cmd.ScriptPath
    } else {
        Write-PwtHost "edit.exe not found, falling back to notepad." -ForegroundColor Yellow
        & notepad $cmd.ScriptPath
    }
}

function script:Invoke-PwtReload {
    if (-not $PROFILE -or -not (Test-Path $PROFILE)) {
        Write-PwtHost "No profile found at: $PROFILE" -ForegroundColor Red
        return
    }
    Write-PwtHost "Reloading profile: $PROFILE" -ForegroundColor Cyan
    . $PROFILE
    Write-PwtHost "Done." -ForegroundColor Green
}

# ============================================================================
# MAIN DISPATCHER
# ============================================================================

function pwt {
<#
.SYNOPSIS
    PowerShell Tools - main dispatcher.

.DESCRIPTION
    Run 'pwt list' to see all available commands.
    Run 'pwt help <name>' for detailed help on a command.

.EXAMPLE
    pwt list
.EXAMPLE
    pwt help portcheck
.EXAMPLE
    pwt portcheck 3000
#>
    # NOTE: no [CmdletBinding] on purpose so $args preserves -Param/value pairs
    # for forwarding via splat to the underlying tool function.
    begin {
        $pwtArgs = @($args)
        $pipelineInput = [System.Collections.Generic.List[object]]::new()
        $hasPipelineInput = $MyInvocation.ExpectingInput
    }

    process {
        if ($hasPipelineInput) {
            $pipelineInput.Add($_)
        }
    }

    end {
        if ($pwtArgs.Count -eq 0) { Show-PwtList; return }

        $Command = [string]$pwtArgs[0]
        # @() wrapper guarantees an array even when only one arg follows
        # (PowerShell unwraps single-element slices, which would make @rest
        # splat a string char-by-char).
        $rest = @(if ($pwtArgs.Count -gt 1) { $pwtArgs[1..($pwtArgs.Count - 1)] })

        switch ($Command) {
            'list'   { Show-PwtList   @rest; return }
            'help'   { Show-PwtHelp   @rest; return }
            'edit'   { Invoke-PwtEdit @rest; return }
            'reload' { Invoke-PwtReload;     return }
        }

        $entry = $global:PwtCommands[$Command]
        if (-not $entry) {
            Write-PwtHost "Unknown command: $Command" -ForegroundColor Red
            Write-PwtHost "Try 'pwt list'." -ForegroundColor Yellow
            return
        }

        # Lazy-load: import as temporary module with -Global so functions land in
        # global scope and survive beyond this dispatcher invocation.
        # (plain dot-source inside a function is local-scoped — functions vanish on return)
        if (-not $entry.Loaded) {
            if (-not $entry.ScriptPath -or -not (Test-Path $entry.ScriptPath)) {
                Write-PwtHost "Script not found: $($entry.ScriptPath)" -ForegroundColor Red
                return
            }
            $p = $entry.ScriptPath
            $modName = "pwt_lazy_$($entry.Name -replace '[^a-zA-Z0-9]', '_')"
            $mod = New-Module -Name $modName `
                -ScriptBlock ([scriptblock]::Create(". '$($p -replace "'", "''")'" ))
            Import-Module $mod -Global -Force -ErrorAction Stop
            $entry.Loaded = $true
        }

        if (-not (Get-Command $entry.Function -ErrorAction SilentlyContinue)) {
            Write-PwtHost "Function not loaded: $($entry.Function)" -ForegroundColor Red
            return
        }

        if ($pipelineInput.Count -gt 0) {
            $pipelineInput | & $entry.Function @rest
        } else {
            & $entry.Function @rest
        }
    }
}

# ============================================================================
# TAB COMPLETION
# ============================================================================

# A single completer that looks at position. Argument 0 = sub-command,
# argument 1 (when sub-command is help/edit) = registered command name.
Register-ArgumentCompleter -CommandName pwt -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    $tokens = @($commandAst.CommandElements)
    # tokens[0] is 'pwt' itself.
    $position = $tokens.Count
    # If the user is mid-typing a token, that token already exists in
    # $tokens, so the position to complete is the last index.
    if ($wordToComplete) { $position = $tokens.Count - 1 }
    # 1 = sub-command, 2 = topic for help/edit
    $relative = $position  # 1-based: 1 = first arg after 'pwt'

    if ($relative -eq 1) {
        $builtins   = @('list', 'help', 'edit', 'reload')
        $registered = @($global:PwtCommands.Keys)
        ($builtins + $registered) | Sort-Object -Unique | Where-Object {
            $_ -like "$wordToComplete*"
        } | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
        return
    }

    if ($relative -eq 2) {
        $sub = $tokens[1].Value
        if ($sub -in @('help', 'edit')) {
            $global:PwtCommands.Keys | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
            }
        }
    }
}

