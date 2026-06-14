#!/usr/bin/env pwsh
# ============================================================================
#  pwt phone  —  Android (ADB) helper  [PowerShell 7+]
#  Streaming · Terminal · Dual-pane file transfer (Total Commander style)
# ============================================================================

#requires -Version 7.0

# ── Palette (24-bit ANSI via $PSStyle) ────────────────────────────────────────
$script:C = @{
    Frame      = $PSStyle.Foreground.FromRgb(0x0E, 0x74, 0x8A)   # teal
    FrameAct   = $PSStyle.Foreground.FromRgb(0x38, 0xBD, 0xF8)   # sky blue
    Header     = $PSStyle.Foreground.FromRgb(0x6B, 0x72, 0x80)   # slate
    OK         = $PSStyle.Foreground.FromRgb(0x4A, 0xD9, 0xA1)   # emerald
    Warn       = $PSStyle.Foreground.FromRgb(0xF7, 0xC9, 0x48)   # amber
    Err        = $PSStyle.Foreground.FromRgb(0xFF, 0x6B, 0x6B)   # coral
    Info       = $PSStyle.Foreground.FromRgb(0x7D, 0xD3, 0xFC)   # light sky
    Muted      = $PSStyle.Foreground.FromRgb(0x6B, 0x72, 0x80)   # slate
    White      = $PSStyle.Foreground.FromRgb(0xE6, 0xEA, 0xF2)   # near-white
    Dir        = $PSStyle.Foreground.FromRgb(0x38, 0xBD, 0xF8)   # sky blue
    File       = $PSStyle.Foreground.FromRgb(0xE6, 0xEA, 0xF2)   # near-white
    DotDot     = $PSStyle.Foreground.FromRgb(0x6B, 0x72, 0x80)   # slate
    SelFg      = $PSStyle.Foreground.FromRgb(0x0F, 0x17, 0x2A)   # near-black
    SelBg      = $PSStyle.Background.FromRgb(0x38, 0xBD, 0xF8)   # sky blue bg
    SelBgInact = $PSStyle.Background.FromRgb(0x4B, 0x55, 0x63)   # mid-gray bg
    FKeyFg     = $PSStyle.Foreground.FromRgb(0x0F, 0x17, 0x2A)   # near-black
    FKeyBg     = $PSStyle.Background.FromRgb(0x38, 0xBD, 0xF8)   # sky blue bg
    FKeyBarBg  = $PSStyle.Background.FromRgb(0x1E, 0x3A, 0x5C)   # navy bg
    FKeyNum    = $PSStyle.Foreground.FromRgb(0xF7, 0xC9, 0x48)   # amber
    Reset      = $PSStyle.Reset
}

# ── Box-drawing ────────────────────────────────────────────────────────────────
$script:B = @{
    # Outer double-line box
    TL = '╔'; TR = '╗'; BL = '╚'; BR = '╝'
    H  = '═'; V  = '║'
    LT = '╠'; RT = '╣'          # ├ ┤ (double)
    TT = '╦'; BT = '╩'; XX = '╬' # T-junctions and cross
    # Misc
    Arr = '▶'; Up = '↑'; Sep = '┄'
}

# ── State ──────────────────────────────────────────────────────────────────────
$script:LastWifi = $null
$script:ScrcpyOk = $false

# =============================================================================
#  CONSOLE PRIMITIVES
# =============================================================================

function script:Set-Cur([int]$X, [int]$Y) { [Console]::SetCursorPosition($X, $Y) }

function script:Write-At {
    param([int]$X, [int]$Y, [string]$Text,
          [string]$Fg = $script:C.White,
          [string]$Bg = '')
    Set-Cur $X $Y
    [Console]::Write("$Fg$Bg$Text$($script:C.Reset)")
}

function script:Fit([string]$S, [int]$Max, [switch]$Pad) {
    if ($S.Length -gt $Max) { $S = $S.Substring(0, [Math]::Max(0, $Max - 1)) + '…' }
    if ($Pad) { $S = $S.PadRight($Max) }
    return $S
}

function script:Cls { [Console]::Write("`e[2J`e[H") }

# ── Styled wrappers ───────────────────────────────────────────────────────────
function script:W-Ansi ([string]$Ansi, [string]$M) {
    [Console]::WriteLine("$Ansi$M$($script:C.Reset)")
}
function script:W-OK   ([string]$M) { W-Ansi $script:C.OK   "  ✔  $M" }
function script:W-Err  ([string]$M) { W-Ansi $script:C.Err  "  ✘  $M" }
function script:W-Warn ([string]$M) { W-Ansi $script:C.Warn "  ⚠  $M" }
function script:W-Info ([string]$M) { W-Ansi $script:C.Info "  ◈  $M" }
function script:W-Dim  ([string]$M) { W-Ansi $script:C.Muted "     $M" }

function script:W-Box {
    param([string[]]$Lines, [string]$Title = '', [string]$Col = $script:C.Frame)
    $R      = $script:C.Reset
    $W      = $script:C.White
    $maxLen = ($Lines | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum ?? 0
    $inner  = [Math]::Max($maxLen, $Title.Length) + 2
    $bar    = $script:B.H * $inner
    [Console]::WriteLine("  $Col$($script:B.TL)$bar$($script:B.TR)$R")
    if ($Title) {
        $padL = [int][Math]::Floor(($inner - $Title.Length) / 2)
        $padR = $inner - $Title.Length - $padL
        [Console]::WriteLine("  $Col$($script:B.V)$(' ' * $padL)$Title$(' ' * $padR)$($script:B.V)$R")
        [Console]::WriteLine("  $Col$($script:B.LT)$bar$($script:B.RT)$R")
    }
    foreach ($l in $Lines) {
        [Console]::WriteLine("  $Col$($script:B.V) $R$($l.PadRight($inner - 2))$Col $($script:B.V)$R")
    }
    [Console]::WriteLine("  $Col$($script:B.BL)$bar$($script:B.BR)$R")
}

function script:W-Section([string]$T) {
    [Console]::WriteLine("")
    [Console]::WriteLine("  $($script:C.FrameAct)$($script:B.Sep)$($script:B.Sep) $T$($script:C.Reset)")
}

function script:Prompt-Choice {
    param([string]$Question, [string[]]$Options, [int]$Default = 1)
    $R = $script:C.Reset
    [Console]::WriteLine("")
    [Console]::WriteLine("  $($script:C.Warn)$Question$R")
    for ($i = 0; $i -lt $Options.Count; $i++) {
        $marker = if ($i + 1 -eq $Default) { $script:B.Arr } else { ' ' }
        [Console]::WriteLine("    $($script:C.White)$marker $($i+1)) $($Options[$i])$R")
    }
    [Console]::WriteLine("")
    do {
        $r  = Read-Host "  Wybór [Enter=$Default]"
        if ([string]::IsNullOrWhiteSpace($r)) { return $Default }
        $n  = 0
        $ok = [int]::TryParse($r, [ref]$n) -and $n -ge 1 -and $n -le $Options.Count
        if (-not $ok) { W-Err "Podaj liczbę 1–$($Options.Count)" }
    } while (-not $ok)
    return $n
}

function script:Prompt-YN([string]$Q, [bool]$Default = $true) {
    $hint = if ($Default) { 'T/n' } else { 't/N' }
    [Console]::Write("  $($script:C.Warn)$Q $($script:C.Muted)($hint) $($script:C.Reset)")
    $r = Read-Host
    if ([string]::IsNullOrWhiteSpace($r)) { return $Default }
    return $r -in @('t', 'T', 'y', 'Y')
}

# =============================================================================
#  TOOL CHECK
# =============================================================================

function script:Test-Tool {
    param([string]$Name, [string]$Description, [string]$Winget, [string]$Url)
    if (Get-Command $Name -ErrorAction SilentlyContinue) { return $true }
    [Console]::WriteLine("")
    W-Err "$Name nie znaleziono w PATH."
    W-Dim $Description
    if ($Winget) { W-Dim "  Instalacja:  winget install $Winget" }
    if ($Url)    { W-Dim "  Pobierz: $Url" }
    [Console]::WriteLine("")
    return $false
}

function script:Write-PhoneToolStatus {
    param(
        [Parameter(Mandatory)][string]$Name,
        $CommandInfo,
        [switch]$Required
    )
    $R     = $script:C.Reset
    $label = if ($Required) { 'required' } else { 'optional' }
    if ($CommandInfo) {
        [Console]::WriteLine("    $($script:C.White){0,-8} $R$($script:C.OK)[OK]      $R$($script:C.Muted)$label  $R$($script:C.White)$($CommandInfo.Source)$R" -f $Name)
    } else {
        $color = if ($Required) { $script:C.Err } else { $script:C.Warn }
        $text  = if ($Required) { '[MISSING]' } else { '[missing]' }
        [Console]::WriteLine("    $($script:C.White){0,-8} $R${color}{1,-9}$R$($script:C.Muted)$label$R" -f $Name, $text)
    }
}

function script:Get-AdbPropValue {
    param([string]$Serial, [string]$Name)
    $r = Invoke-Adb -Argv @('-s', $Serial, 'shell', 'getprop', $Name) -AllowFail
    if (-not $r.OK) { return $null }
    $value = $r.Out | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1
    if ($value) { return "$value".Trim() }
    return $null
}

function script:Show-PwtPhoneStatus {
    $adb = Get-Command 'adb' -ErrorAction SilentlyContinue
    $scrcpy = Get-Command 'scrcpy' -ErrorAction SilentlyContinue

    [Console]::WriteLine("")
    [Console]::WriteLine("  $($script:C.FrameAct)pwt phone status$($script:C.Reset)")
    [Console]::WriteLine("  $($script:C.Muted)----------------$($script:C.Reset)")
    Write-PhoneToolStatus -Name 'adb' -CommandInfo $adb -Required
    Write-PhoneToolStatus -Name 'scrcpy' -CommandInfo $scrcpy
    [Console]::WriteLine("")

    if (-not $adb) {
        Test-Tool -Name 'adb' `
            -Description 'Android Debug Bridge — wymagany dla wszystkich operacji.' `
            -Winget 'Google.PlatformTools' `
            -Url 'https://developer.android.com/studio/releases/platform-tools' | Out-Null
        $global:LASTEXITCODE = 1
        return
    }

    Invoke-Adb -Argv @('start-server') -AllowFail | Out-Null
    $devices = @(Get-AdbDevices)

    if ($devices.Count -eq 0) {
        W-Warn "Brak urządzeń w adb devices."
        $global:LASTEXITCODE = 0
        return
    }

    [Console]::WriteLine("  $($script:C.FrameAct)Devices:$($script:C.Reset)")
    foreach ($d in $devices) {
        $type = if ($d.IsUSB) { 'USB' } else { 'Wi-Fi' }
        $stateColor = if ($d.Ready) { $script:C.OK } elseif ($d.Unauthorized) { $script:C.Warn } else { $script:C.Err }
        $R = $script:C.Reset
        [Console]::WriteLine("    $($script:C.White){0,-28}$R $($script:C.Info){1,-5}$R $stateColor{2}$R" -f $d.Serial, $type, $d.State)

        if ($d.Ready) {
            $model = Get-AdbPropValue -Serial $d.Serial -Name 'ro.product.model'
            $android = Get-AdbPropValue -Serial $d.Serial -Name 'ro.build.version.release'
            $sdk = Get-AdbPropValue -Serial $d.Serial -Name 'ro.build.version.sdk'
            $details = @()
            if ($model) { $details += "model=$model" }
            if ($android) { $details += "android=$android" }
            if ($sdk) { $details += "sdk=$sdk" }
            if ($details.Count -gt 0) {
                W-Dim ("  " + ($details -join '  '))
            }
        }
        elseif ($d.Unauthorized) {
            W-Dim "  Autoryzuj debugowanie USB na ekranie telefonu."
        }
    }
    [Console]::WriteLine("")
    $global:LASTEXITCODE = 0
}

# =============================================================================
#  ADB WRAPPERS
# =============================================================================

function script:Invoke-Adb {
    param([string[]]$Argv, [switch]$AllowFail)
    $out = & adb @Argv 2>&1
    $ec  = $LASTEXITCODE
    if (-not $AllowFail -and $ec -ne 0) {
        throw "adb $($Argv -join ' ') → exit $ec`n$($out -join "`n")"
    }
    return [PSCustomObject]@{ Out = $out; Code = $ec; OK = ($ec -eq 0) }
}

function script:Get-AdbDevices {
    $r    = Invoke-Adb -Argv @('devices', '-l') -AllowFail
    $list = @()
    $r.Out | Select-Object -Skip 1 | Where-Object { $_.Trim() } | ForEach-Object {
        if ($_ -match '^(\S+)\s+(\S+)') {
            $list += [PSCustomObject]@{
                Serial       = $Matches[1]
                State        = $Matches[2]
                Ready        = ($Matches[2] -eq 'device')
                Unauthorized = ($Matches[2] -eq 'unauthorized')
                Offline      = ($Matches[2] -eq 'offline')
                IsUSB        = ($Matches[1] -notmatch ':\d+$')
            }
        }
    }
    return $list
}

function script:Get-PhoneIP([string]$Serial) {
    W-Info "Wykrywam adres IP telefonu…"
    $base = if ($Serial) { @('-s', $Serial, 'shell') } else { @('shell') }
    # FIX: added sed-based fallbacks for Android without grep -P
    $cmds = @(
        "ip route get 1.1.1.1 2>/dev/null | grep -oE 'src [0-9.]+' | awk '{print \$2}'"
        "ip addr show wlan0 2>/dev/null | grep -oE 'inet [0-9.]+' | awk '{print \$2}'"
        "ip addr show wlan1 2>/dev/null | grep -oE 'inet [0-9.]+' | awk '{print \$2}'"
        "ifconfig wlan0 2>/dev/null | grep -oE 'addr:[0-9.]+' | sed 's/addr://'"
        "getprop dhcp.wlan0.ipaddress 2>/dev/null"
    )
    foreach ($cmd in $cmds) {
        try {
            $r  = Invoke-Adb -Argv ($base + @($cmd)) -AllowFail
            $ip = $r.Out | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1
            if ($ip -and (Test-ValidIP $ip.Trim())) { return $ip.Trim() }
        }
        catch { continue }
    }
    return $null
}

function script:Test-ValidIP([string]$IP) {
    if ($IP -notmatch '^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$') { return $false }
    foreach ($o in @($Matches[1], $Matches[2], $Matches[3], $Matches[4])) {
        if ([int]$o -gt 255) { return $false }
    }
    return $true
}

function script:Quote-AdbShellArg([string]$Value) {
    if ($null -eq $Value) { return "''" }
    $quote = [char]39
    $escaped = $Value.Replace([string]$quote, ($quote + '\' + $quote + $quote))
    return ($quote + $escaped + $quote)
}

# =============================================================================
#  DEVICE SELECTION UI
# =============================================================================

function script:Show-Unauthorized {
    [Console]::WriteLine("")
    W-Box -Title ' USB Debugging — Brak autoryzacji ' -Col $script:C.Warn -Lines @(
        "Telefon wyświetla okno autoryzacji."
        ""
        "  1. Spójrz na ekran telefonu"
        "  2. Kliknij  Zezwól  na 'Zezwolić na debugowanie USB?'"
        "  3. Zaznacz 'Zawsze zezwalaj z tego komputera'"
        ""
        "Jeśli okno nie pojawia się:"
        "  Ustawienia → Opcje programisty →"
        "  Cofnij autoryzacje debugowania USB"
        "  i ponownie podłącz kabel."
    )
    [Console]::WriteLine("")
}

# =============================================================================
#  MODE 1 — STREAMING  (scrcpy)
# =============================================================================

function script:Get-ScrcpyConfig {
    Cls
    W-Section "scrcpy Streaming — Konfiguracja"

    $maxSizeChoice = Prompt-Choice "Maksymalna rozdzielczość (dłuższy bok):" @(
        'Natywna (bez limitu)'
        '1920 px'
        '1280 px'
        '1024 px'
        '800 px'
        'Własna…'
    ) -Default 1
    $maxSize = switch ($maxSizeChoice) {
        2 { '1920' } 3 { '1280' } 4 { '1024' } 5 { '800' }
        6 { $v = Read-Host "  Rozmiar (px)"; if ($v -match '^\d+$') { $v } else { '0' } }
        default { '0' }
    }

    $brChoice = Prompt-Choice "Bitrate video:" @('2 Mbps', '4 Mbps', '8 Mbps (domyślnie)', '16 Mbps', '32 Mbps', 'Własny…') -Default 3
    $bitrate  = switch ($brChoice) {
        1 { '2M' } 2 { '4M' } 4 { '16M' } 5 { '32M' }
        6 { $v = Read-Host "  Własny (np. 6M)"; if ($v) { $v } else { '8M' } }
        default { '8M' }
    }

    $audio     = (Prompt-Choice "Przekazywanie dźwięku:" @('Włączone (domyślnie)', 'Wyłączone') -Default 1) -eq 1
    $noControl = (Prompt-Choice "Tryb sterowania:" @('Pełna kontrola (domyślnie)', 'Tylko podgląd') -Default 1) -eq 2
    $stayAwake = (Prompt-Choice "Ekran aktywny podczas połączenia:" @('Tak (domyślnie)', 'Nie') -Default 1) -eq 1
    $alwaysTop = (Prompt-Choice "Okno zawsze na wierzchu:" @('Nie (domyślnie)', 'Tak') -Default 1) -eq 2

    $recordPath = $null
    if ((Prompt-Choice "Nagrywaj sesję:" @('Nie (domyślnie)', 'Tak') -Default 1) -eq 2) {
        $def        = "scrcpy-$(Get-Date -Format 'yyyyMMdd-HHmmss').mp4"
        $p          = Read-Host "  Ścieżka zapisu [$def]"
        $recordPath = if ([string]::IsNullOrWhiteSpace($p)) { $def } else { $p }
    }

    return [PSCustomObject]@{
        MaxSize     = $maxSize
        Bitrate     = $bitrate
        Audio       = $audio
        NoControl   = $noControl
        StayAwake   = $stayAwake
        AlwaysOnTop = $alwaysTop
        RecordPath  = $recordPath
    }
}

function script:Start-Streaming([string]$Serial) {
    if (-not $script:ScrcpyOk) {
        [Console]::WriteLine("")
        W-Err "scrcpy nie jest zainstalowane — streaming niedostępny."
        W-Dim "Instalacja: winget install Genymobile.scrcpy"
        return
    }
    $cfg  = Get-ScrcpyConfig
    $argv = @('-s', $Serial)
    if ($cfg.MaxSize -ne '0') { $argv += @('--max-size', $cfg.MaxSize) }
    $argv += @('--video-bit-rate', $cfg.Bitrate)
    if (-not $cfg.Audio)     { $argv += '--no-audio' }
    if ($cfg.NoControl)      { $argv += '--no-control' }
    if ($cfg.StayAwake)      { $argv += '--stay-awake' }
    if ($cfg.AlwaysOnTop)    { $argv += '--always-on-top' }
    if ($cfg.RecordPath)     { $argv += @('--record', $cfg.RecordPath) }

    [Console]::WriteLine("")
    W-Info "Uruchamiam scrcpy…"
    W-Dim  "scrcpy $($argv -join ' ')"
    [Console]::WriteLine("")
    & scrcpy @argv
}

# =============================================================================
#  MODE 2 — TERMINAL  (adb shell)
# =============================================================================

function script:Get-ShellConfig {
    Cls
    W-Section "ADB Shell — Konfiguracja"
    $root   = (Prompt-Choice "Użytkownik powłoki:" @('Domyślny (shell)', 'Root (su)') -Default 1) -eq 2
    [Console]::WriteLine("")
    $preCmd = Read-Host "  Polecenie wstępne (opcjonalnie, puste = zwykła powłoka)"
    $cwd    = Read-Host "  Katalog startowy [Enter=/sdcard]"
    if ([string]::IsNullOrWhiteSpace($cwd)) { $cwd = '/sdcard' }
    return [PSCustomObject]@{ Root = $root; PreCmd = $preCmd; Cwd = $cwd }
}

function script:Start-Terminal([string]$Serial) {
    $cfg   = Get-ShellConfig
    $parts = @()
    if ($cfg.Cwd)    { $parts += "cd $(Quote-AdbShellArg $cfg.Cwd)" }
    if ($cfg.PreCmd) { $parts += $cfg.PreCmd }
    $parts += 'exec sh -i'
    $inner = $parts -join ' && '

    [Console]::WriteLine("")
    W-Info "Uruchamiam powłokę ADB…"
    W-Dim  "Wpisz 'exit' aby wrócić."
    [Console]::WriteLine("")

    if ($cfg.Root) {
        # 'su 0 sh -c' działa zarówno z AOSP-su (emulator) jak i Magisk-su.
        # Składnia 'su -c' bywa niekompatybilna (AOSP traktuje '-c' jako UID).
        & adb -s $Serial shell -t "su 0 sh -c `"$inner`""
    }
    elseif ($cfg.PreCmd -or $cfg.Cwd) {
        & adb -s $Serial shell -t $inner
    }
    else {
        & adb -s $Serial shell
    }
}

# =============================================================================
#  MODE 3 — FILE MANAGER  (dual-pane TUI, Total Commander style)
# =============================================================================

# ── Format helpers ─────────────────────────────────────────────────────────────

function script:Fmt-Bytes([long]$Bytes) {
    if ($Bytes -lt 0)    { return '       ?' }
    if ($Bytes -lt 1KB)  { return ('{0,6} B'  -f $Bytes) }
    if ($Bytes -lt 1MB)  { return ('{0,5:0.0}K' -f ($Bytes / 1KB)) }
    if ($Bytes -lt 1GB)  { return ('{0,5:0.0}M' -f ($Bytes / 1MB)) }
    return                        ('{0,5:0.1}G' -f ($Bytes / 1GB))
}

function script:Fmt-Date($D) {
    if ($null -eq $D) { return '                ' }
    return $D.ToString('yyyy-MM-dd HH:mm')
}

# ── Filesystem ────────────────────────────────────────────────────────────────

function script:Get-LocalEntries([string]$Path) {
    $items = [System.Collections.Generic.List[object]]::new()
    $items.Add([PSCustomObject]@{ Name = '..'; IsDir = $true; Size = 0L; Modified = $null; IsParent = $true })
    try {
        Get-ChildItem -LiteralPath $Path -Force -EA Stop |
            Sort-Object @{ e = 'PSIsContainer'; d = $true }, Name |
            ForEach-Object {
                $items.Add([PSCustomObject]@{
                    Name     = $_.Name
                    IsDir    = $_.PSIsContainer
                    Size     = if ($_.PSIsContainer) { -1L } else { [long]$_.Length }
                    Modified = $_.LastWriteTime
                    IsParent = $false
                })
            }
    }
    catch { <# permission denied #> }
    return , $items.ToArray()
}

function script:Get-RemoteEntries([string]$Serial, [string]$Path) {
    $items = [System.Collections.Generic.List[object]]::new()
    $items.Add([PSCustomObject]@{ Name = '..'; IsDir = $true; Size = 0L; Modified = $null; IsParent = $true })
    $esc = Quote-AdbShellArg $Path
    $r   = Invoke-Adb -Argv @('-s', $Serial, 'shell', "ls -la --color=never $esc 2>/dev/null") -AllowFail
    if (-not $r.OK) { return , $items.ToArray() }
    foreach ($line in $r.Out) {
        $s = "$line"
        if ($s -match '^total\s' -or [string]::IsNullOrWhiteSpace($s)) { continue }
        if ($s -match '^(?<p>[\-dlcbsp])\S{9}\s+\d+\s+\S+\s+\S+\s+(?<sz>\d+)\s+(?<dt>\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2})\s+(?<nm>.+)$') {
            $nm = $Matches['nm'].Trim()
            if ($nm -in @('.', '..')) { continue }
            if ($nm -match '^(.*?)\s+->\s+') { $nm = $Matches[1].Trim() }
            $dt = $null; try { $dt = [datetime]::Parse($Matches['dt']) } catch {}
            $items.Add([PSCustomObject]@{
                Name     = $nm
                IsDir    = ($Matches['p'] -eq 'd')
                Size     = [long]$Matches['sz']
                Modified = $dt
                IsParent = $false
            })
        }
    }
    if ($items.Count -gt 1) {
        $rest = @($items[1..($items.Count - 1)] | Sort-Object @{ e = 'IsDir'; d = $true }, Name)
        return , (@($items[0]) + $rest)
    }
    return , $items.ToArray()
}

# ── Pane state ────────────────────────────────────────────────────────────────

function script:New-Pane([string]$Label, [bool]$IsRemote, [string]$Path, [string]$Serial) {
    $p = [PSCustomObject]@{
        Label    = $Label
        IsRemote = $IsRemote
        Path     = $Path
        Serial   = $Serial
        Entries  = @()
        Cursor   = 0
        ScrollTop= 0
        Error    = $null
    }
    Update-Pane $p
    return $p
}

function script:Update-Pane($P) {
    $P.Error = $null
    try {
        $P.Entries = if ($P.IsRemote) {
            Get-RemoteEntries -Serial $P.Serial -Path $P.Path
        }
        else {
            Get-LocalEntries -Path $P.Path
        }
    }
    catch {
        $P.Error   = $_.Exception.Message
        $P.Entries = @([PSCustomObject]@{ Name = '..'; IsDir = $true; Size = 0L; Modified = $null; IsParent = $true })
    }
    $max = $P.Entries.Count - 1
    if ($P.Cursor -gt $max) { $P.Cursor = [Math]::Max(0, $max) }
}

function script:Fix-Scroll($P, [int]$Vis) {
    if ($P.Cursor -lt $P.ScrollTop) { $P.ScrollTop = $P.Cursor }
    if ($P.Cursor -ge $P.ScrollTop + $Vis) { $P.ScrollTop = $P.Cursor - $Vis + 1 }
    if ($P.ScrollTop -lt 0) { $P.ScrollTop = 0 }
}

function script:Nav-Into($P, $Entry) {
    if ($Entry.IsParent) { Nav-Up $P; return }
    if (-not $Entry.IsDir) { return }
    if ($P.IsRemote) {
        $base   = $P.Path.TrimEnd('/')
        $P.Path = if ($base) { "$base/$($Entry.Name)" } else { "/$($Entry.Name)" }
    }
    else { $P.Path = Join-Path $P.Path $Entry.Name }
    $P.Cursor = 0; $P.ScrollTop = 0; Update-Pane $P
}

function script:Nav-Up($P) {
    if ($P.IsRemote) {
        $p2 = $P.Path.TrimEnd('/')
        if (-not $p2.Contains('/')) { $P.Path = '/' }
        else {
            $P.Path = $p2.Substring(0, $p2.LastIndexOf('/'))
            if ($P.Path -eq '') { $P.Path = '/' }
        }
    }
    else {
        $par = Split-Path $P.Path -Parent
        if ($par) { $P.Path = $par }
    }
    $P.Cursor = 0; $P.ScrollTop = 0; Update-Pane $P
}

# ── Layout ────────────────────────────────────────────────────────────────────
# Row layout (Total Commander style):
#   0          : ╔══ Left title ════╦══ Right title ══╗
#   1          : ║ col headers      ║ col headers     ║
#   2          : ╠══════════════════╬═════════════════╣
#   3..(H-7)   : ║ list entries     ║ list entries    ║    (ListH = H-9)
#   H-6        : ╠══════════════════╬═════════════════╣
#   H-5        : ║ footer           ║ footer          ║
#   H-4        : ╚══════════════════╩═════════════════╝
#   H-3        : (gap)
#   H-2        : status bar
#   H-1        : function key bar

$script:FM = @{ W = 0; H = 0; PW = 0; ListH = 0; MinW = 72; MinH = 15 }

function script:Test-FMConsoleSize {
    param([switch]$ShowMessage)

    try {
        $w = [Console]::WindowWidth
        $h = [Console]::WindowHeight
    }
    catch {
        if ($ShowMessage) { W-Err "Nie można odczytać rozmiaru terminala." }
        return $false
    }

    if ($w -ge $script:FM.MinW -and $h -ge $script:FM.MinH) { return $true }

    if ($ShowMessage) {
        Cls
        W-Box -Title ' Terminal za mały ' -Col $script:C.Warn -Lines @(
            "Menedżer plików wymaga minimum $($script:FM.MinW)x$($script:FM.MinH)."
            "Aktualny rozmiar terminala: ${w}x${h}."
            "Powiększ okno i uruchom ponownie tryb Transfer."
        )
    }
    return $false
}

function script:Measure-FM {
    $script:FM.W     = [Console]::WindowWidth
    $script:FM.H     = [Console]::WindowHeight
    $script:FM.PW    = [int][Math]::Floor($script:FM.W / 2)
    $script:FM.ListH = [Math]::Max(2, $script:FM.H - 9)
}

# ── Rendering ──────────────────────────────────────────────────────────────────

function script:Draw-FMFrame([bool]$LeftActive) {
    $W  = $script:FM.W
    $PW = $script:FM.PW
    $H  = $script:FM.H
    $LH = $script:FM.ListH
    $R  = $script:C.Reset

    $colL = if ($LeftActive)      { $script:C.FrameAct } else { $script:C.Frame }
    $colR = if (-not $LeftActive) { $script:C.FrameAct } else { $script:C.Frame }

    function HBar([int]$Len, [string]$Col) {
        [Console]::Write("$Col$($script:B.H * $Len)$($script:C.Reset)")
    }

    # Row 0: top border  ╔══...══╦══...══╗
    Set-Cur 0 0
    [Console]::Write("$colL$($script:B.TL)$R")
    HBar ($PW - 1) $colL
    [Console]::Write("$($script:C.Frame)$($script:B.TT)$R")
    HBar ($W - $PW - 2) $colR
    [Console]::Write("$colR$($script:B.TR)$R")

    # Row 2: separator  ╠══╬══╣
    Set-Cur 0 2
    [Console]::Write("$colL$($script:B.LT)$R")
    HBar ($PW - 1) $colL
    [Console]::Write("$($script:C.Frame)$($script:B.XX)$R")
    HBar ($W - $PW - 2) $colR
    [Console]::Write("$colR$($script:B.RT)$R")

    # Rows 3..(2+LH): side borders
    for ($y = 3; $y -lt 3 + $LH; $y++) {
        Set-Cur 0 $y;        [Console]::Write("$colL$($script:B.V)$R")
        Set-Cur $PW $y;      [Console]::Write("$($script:C.Frame)$($script:B.V)$R")
        Set-Cur ($W - 1) $y; [Console]::Write("$colR$($script:B.V)$R")
    }

    # Row H-6: footer separator  ╠══╬══╣
    $sepY = $H - 6
    Set-Cur 0 $sepY
    [Console]::Write("$colL$($script:B.LT)$R")
    HBar ($PW - 1) $colL
    [Console]::Write("$($script:C.Frame)$($script:B.XX)$R")
    HBar ($W - $PW - 2) $colR
    [Console]::Write("$colR$($script:B.RT)$R")

    # Row H-5: footer line (sides + divider)
    $footY = $H - 5
    Set-Cur 0 $footY;        [Console]::Write("$colL$($script:B.V)$R")
    Set-Cur $PW $footY;      [Console]::Write("$($script:C.Frame)$($script:B.V)$R")
    Set-Cur ($W - 1) $footY; [Console]::Write("$colR$($script:B.V)$R")

    # Row H-4: bottom border  ╚══╩══╝
    $botY = $H - 4
    Set-Cur 0 $botY
    [Console]::Write("$colL$($script:B.BL)$R")
    HBar ($PW - 1) $colL
    [Console]::Write("$($script:C.Frame)$($script:B.BT)$R")
    HBar ($W - $PW - 2) $colR
    [Console]::Write("$colR$($script:B.BR)$R")
}

function script:Draw-FMPane($P, [int]$X, [bool]$Active) {
    $W   = $script:FM.W
    $PW  = $script:FM.PW
    $H   = $script:FM.H
    $LH  = $script:FM.ListH
    $col = if ($Active) { $script:C.FrameAct } else { $script:C.Frame }

    # Panel content width (inside borders)
    $pw = if ($X -eq 0) { $PW - 1 } else { $W - $PW - 2 }  # excl. left+right borders
    $cx = $X + 1  # content start column

    # Row 0: title embedded in top border
    $icon  = if ($P.IsRemote) { ' ☎ ' } else { ' ⊞ ' }
    $title = Fit "$icon$($P.Label): $($P.Path)" ($pw - 4)
    $pad   = $pw - $title.Length - 2
    $padL  = [int][Math]::Floor($pad / 2)
    $padR  = $pad - $padL
    Write-At $cx 0 ($script:B.H * $padL) $col
    $titleFg = if ($Active) { $script:C.White } else { $script:C.Muted }
    Write-At ($cx + $padL) 0 " $title " $titleFg
    Write-At ($cx + $padL + $title.Length + 2) 0 ($script:B.H * $padR) $col

    # Row 1: column headers
    $nw  = $pw - 27; if ($nw -lt 4) { $nw = 4 }
    $hdr = ('{0,-' + $nw + '} {1,8}  {2,16}') -f 'Nazwa', 'Rozmiar', 'Data modyfikacji'
    Write-At $cx 1 ($hdr.PadRight($pw).Substring(0, $pw)) $script:C.Header

    # Error state
    if ($P.Error) {
        Write-At $cx 3 (Fit " ⚠  $($P.Error)" $pw -Pad) $script:C.Err
        for ($i = 1; $i -lt $LH; $i++) { Write-At $cx (3 + $i) (' ' * $pw) }
    }
    else {
        Fix-Scroll -P $P -Vis $LH
        for ($i = 0; $i -lt $LH; $i++) {
            $idx  = $P.ScrollTop + $i
            $rowY = 3 + $i
            if ($idx -ge $P.Entries.Count) { Write-At $cx $rowY (' ' * $pw); continue }
            $e     = $P.Entries[$idx]
            $isCur = ($idx -eq $P.Cursor)
            $ico   = if ($e.IsParent) { "$($script:B.Up) " } elseif ($e.IsDir) { "$($script:B.Arr) " } else { '  ' }
            $nm    = Fit ($ico + $e.Name) $nw -Pad
            $sz    = if ($e.IsParent) { '        ' } elseif ($e.IsDir) { '  <DIR> ' } else { Fmt-Bytes $e.Size }
            $dt    = Fmt-Date $e.Modified
            $line  = ('{0} {1,8}  {2,16}') -f $nm, $sz, $dt
            $line  = $line.PadRight($pw).Substring(0, $pw)

            if ($isCur -and $Active)  { Write-At $cx $rowY $line $script:C.SelFg $script:C.SelBg }
            elseif ($isCur)           { Write-At $cx $rowY $line $script:C.White $script:C.SelBgInact }
            elseif ($e.IsParent)      { Write-At $cx $rowY $line $script:C.DotDot }
            elseif ($e.IsDir)         { Write-At $cx $rowY $line $script:C.Dir }
            else                      { Write-At $cx $rowY $line $script:C.File }
        }
    }

    # Footer (row H-5): item count + total size
    $footY  = $H - 5
    $cnt    = $P.Entries.Count - 1
    $total  = ($P.Entries | Where-Object { -not $_.IsParent -and -not $_.IsDir } |
               Measure-Object -Property Size -Sum).Sum ?? 0
    $ftext  = " $cnt element$(if($cnt -ne 1){'ów'})  $(Fmt-Bytes $total) "
    Write-At $cx $footY (Fit $ftext $pw -Pad) $col
}

function script:Draw-FMStatus([string]$Msg = '', [string]$Fg = $script:C.Muted) {
    $y   = $script:FM.H - 2
    $bar = (' ' + $Msg).PadRight($script:FM.W).Substring(0, $script:FM.W)
    Set-Cur 0 $y
    [Console]::Write("$Fg$bar$($script:C.Reset)")
}

function script:Draw-FMFkeyBar {
    $W    = $script:FM.W
    $y    = $script:FM.H - 1
    $keys = @(
        @('F1', 'Help'), @('F2', '    '), @('F3', 'View'), @('F4', 'Edit'),
        @('F5', 'Copy'), @('F6', 'Move'), @('F7', 'MkDir'), @('F8', 'Del '),
        @('F9', '    '), @('F10', 'Quit')
    )
    $R   = $script:C.Reset
    $BB  = $script:C.FKeyBarBg
    $Num = $script:C.FKeyNum
    $Lbl = $script:C.FKeyFg
    $LBg = $script:C.FKeyBg
    Set-Cur 0 $y
    [Console]::Write("$BB$(' ' * $W)$R")
    Set-Cur 0 $y
    foreach ($k in $keys) {
        [Console]::Write("$BB$Num$($k[0])$R$LBg$Lbl$($k[1])$R$BB $R")
    }
}

function script:Draw-FMAll($L, $R, [bool]$LA) {
    [Console]::CursorVisible = $false
    Cls; Measure-FM
    Draw-FMFrame $LA
    Draw-FMPane -P $L -X 0             -Active $LA
    Draw-FMPane -P $R -X $script:FM.PW -Active (-not $LA)
    Draw-FMFkeyBar
    Draw-FMStatus ' Gotowy  ·  Tab=przełącz panel  ·  F1=pomoc  ·  Q=wyjście' $script:C.Muted
}

# ── Status helpers (in-TUI) ───────────────────────────────────────────────────

function script:FM-OK  ([string]$M) { Draw-FMStatus " ✔  $M" $script:C.OK }
function script:FM-Err ([string]$M) { Draw-FMStatus " ✘  $M" $script:C.Err; Start-Sleep -Milliseconds 1600 }
function script:FM-Info([string]$M) { Draw-FMStatus " ◈  $M" $script:C.Info }

function script:FM-Prompt([string]$Msg) {
    Draw-FMStatus $Msg $script:C.Warn
    Set-Cur ($Msg.Length + 1) ($script:FM.H - 2)
    [Console]::CursorVisible = $true
    $r = Read-Host
    [Console]::CursorVisible = $false
    return $r
}

# ── File operations ───────────────────────────────────────────────────────────

function script:Get-CurEntry($P) {
    $e = if ($P.Cursor -ge 0 -and $P.Cursor -lt $P.Entries.Count) { $P.Entries[$P.Cursor] } else { $null }
    if ($null -eq $e -or $e.IsParent) { return $null }
    return $e
}

function script:Do-Transfer([string]$Op, $From, $To, $Entry) {
    if ($From.IsRemote -eq $To.IsRemote) {
        FM-Err "Obydwa panele po tej samej stronie — nie można $Op."
        return $false
    }
    $name = $Entry.Name
    if ($From.IsRemote) {
        $src = ($From.Path.TrimEnd('/')) + '/' + $name
        $dst = Join-Path $To.Path $name
        FM-Info "Pobieranie  $name …"
        $r = Invoke-Adb -Argv @('-s', $From.Serial, 'pull', $src, $dst) -AllowFail
        if (-not $r.OK) { FM-Err "Pull nieudany: $($r.Out | Select-Object -Last 1)"; return $false }
        if ($Op -eq 'Przeniesienie') {
            $rm = if ($Entry.IsDir) { 'rm -rf' } else { 'rm -f' }
            Invoke-Adb -Argv @('-s', $From.Serial, 'shell', "$rm $(Quote-AdbShellArg $src)") -AllowFail | Out-Null
        }
    }
    else {
        $src = Join-Path $From.Path $name
        $dst = ($To.Path.TrimEnd('/')) + '/' + $name
        FM-Info "Wysyłanie  $name …"
        $r = Invoke-Adb -Argv @('-s', $To.Serial, 'push', $src, $dst) -AllowFail
        if (-not $r.OK) { FM-Err "Push nieudany: $($r.Out | Select-Object -Last 1)"; return $false }
        if ($Op -eq 'Przeniesienie') {
            if ($Entry.IsDir) { Remove-Item -LiteralPath $src -Recurse -Force -EA SilentlyContinue }
            else               { Remove-Item -LiteralPath $src -Force -EA SilentlyContinue }
        }
    }
    FM-OK "$Op zakończony: $name"
    return $true
}

function script:Do-Delete($P, $Entry) {
    $conf = FM-Prompt " Usunąć '$($Entry.Name)' ? (t/N)  "
    if ($conf -notin @('t', 'T', 'y', 'Y')) {
        Draw-FMStatus ' Anulowano' $script:C.Muted
        return $false
    }
    if ($P.IsRemote) {
        $path = ($P.Path.TrimEnd('/')) + '/' + $Entry.Name
        $rm   = if ($Entry.IsDir) { 'rm -rf' } else { 'rm -f' }
        $r    = Invoke-Adb -Argv @('-s', $P.Serial, 'shell', "$rm $(Quote-AdbShellArg $path)") -AllowFail
        if (-not $r.OK) { FM-Err "Usuwanie nieudane"; return $false }
    }
    else {
        $path = Join-Path $P.Path $Entry.Name
        try {
            if ($Entry.IsDir) { Remove-Item -LiteralPath $path -Recurse -Force }
            else               { Remove-Item -LiteralPath $path -Force }
        }
        catch { FM-Err $_.Exception.Message; return $false }
    }
    FM-OK "Usunięto: $($Entry.Name)"; return $true
}

function script:Do-MkDir($P) {
    $name = FM-Prompt ' Nazwa nowego folderu:  '
    if (-not $name) { Draw-FMStatus ' Anulowano' $script:C.Muted; return $false }
    if ($P.IsRemote) {
        $path = ($P.Path.TrimEnd('/')) + '/' + $name
        $r    = Invoke-Adb -Argv @('-s', $P.Serial, 'shell', "mkdir -p $(Quote-AdbShellArg $path)") -AllowFail
        if (-not $r.OK) { FM-Err "mkdir nieudany"; return $false }
    }
    else {
        try { New-Item -ItemType Directory -Path (Join-Path $P.Path $name) -Force | Out-Null }
        catch { FM-Err $_.Exception.Message; return $false }
    }
    FM-OK "Utworzono: $name"; return $true
}

# ── Help overlay ──────────────────────────────────────────────────────────────

function script:Show-FMHelp {
    Cls
    [Console]::WriteLine("")
    W-Box -Title '  ADB Transfer — Skróty klawiszowe  ' -Col $script:C.FrameAct -Lines @(
        "  NAWIGACJA"
        "    ↑ / ↓          Przesuń kursor"
        "    PgUp / PgDn    Przewiń o jedną stronę"
        "    Home / End     Pierwszy / ostatni element"
        "    Enter          Otwórz folder (lub '..' — wyjdź)"
        "    Backspace      Wyjdź o jeden poziom wyżej"
        "    Tab            Przełącz aktywny panel (Lokalny ↔ Telefon)"
        ""
        "  OPERACJE NA PLIKACH"
        "    F5             Kopiuj do drugiego panelu"
        "    F6             Przenieś do drugiego panelu"
        "    F7             Utwórz nowy folder"
        "    F8             Usuń (z potwierdzeniem)"
        ""
        "  INNE"
        "    R              Odśwież aktywny panel"
        "    F1             Ten ekran pomocy"
        "    Q / Esc        Wyjdź z menedżera plików"
        ""
        "  UWAGI"
        "    F5/F6 działają tylko między panelami PC i Telefon."
        "    Element '..' nigdy nie jest kopiowany ani usuwany."
    )
    [Console]::WriteLine("")
    [Console]::WriteLine("  $($script:C.Muted)Naciśnij dowolny klawisz…$($script:C.Reset)")
    [Console]::ReadKey($true) | Out-Null
}

# ── Main file-manager loop ─────────────────────────────────────────────────────

function script:Start-FileManager([string]$Serial, [string]$LocalPath, [string]$RemotePath) {
    if (-not (Test-FMConsoleSize -ShowMessage)) { return }

    $oldVis = $true
    try { $oldVis = [Console]::CursorVisible } catch {}

    try {
        $L  = New-Pane -Label 'Lokalny PC'  -IsRemote $false -Path $LocalPath  -Serial $Serial
        $R  = New-Pane -Label 'Telefon'     -IsRemote $true  -Path $RemotePath -Serial $Serial
        $LA = $true

        Draw-FMAll $L $R $LA

        while ($true) {
            $A = if ($LA) { $L } else { $R }
            $O = if ($LA) { $R } else { $L }

            $key     = [Console]::ReadKey($true)
            $redraw  = $true

            switch ($key.Key) {
                'UpArrow'   { if ($A.Cursor -gt 0) { $A.Cursor-- } }
                'DownArrow' { if ($A.Cursor -lt $A.Entries.Count - 1) { $A.Cursor++ } }
                'PageUp'    { $A.Cursor = [Math]::Max(0, $A.Cursor - $script:FM.ListH) }
                'PageDown'  { $A.Cursor = [Math]::Min($A.Entries.Count - 1, $A.Cursor + $script:FM.ListH) }
                'Home'      { $A.Cursor = 0 }
                'End'       { $A.Cursor = $A.Entries.Count - 1 }
                'Tab'       { $LA = -not $LA }
                'Enter' {
                    $e = $A.Entries[$A.Cursor]
                    if ($null -ne $e -and $e.IsDir) { Nav-Into -P $A -Entry $e }
                }
                'Backspace' { Nav-Up -P $A }
                'F5' {
                    $e = Get-CurEntry $A
                    if ($e) { if (Do-Transfer -Op 'Kopia' -From $A -To $O -Entry $e) { Update-Pane $O } }
                    else    { FM-Err 'Brak zaznaczonego elementu.' }
                }
                'F6' {
                    $e = Get-CurEntry $A
                    if ($e) {
                        if (Do-Transfer -Op 'Przeniesienie' -From $A -To $O -Entry $e) {
                            Update-Pane $A; Update-Pane $O
                        }
                    }
                    else { FM-Err 'Brak zaznaczonego elementu.' }
                }
                'F7' { if (Do-MkDir -P $A) { Update-Pane $A } }
                'F8' {
                    $e = Get-CurEntry $A
                    if ($e) { if (Do-Delete -P $A -Entry $e) { Update-Pane $A } }
                    else    { FM-Err 'Brak zaznaczonego elementu.' }
                }
                'R'  { FM-Info 'Odświeżanie…'; Update-Pane $A }
                'F1' { Show-FMHelp }
                { $_ -in @('Q', 'Escape', 'F10') } { return }
                default { $redraw = $false }
            }

            if ($redraw) {
                if (-not (Test-FMConsoleSize -ShowMessage)) { return }
                Measure-FM
                Draw-FMAll $L $R $LA
            }
        }
    }
    finally {
        try { [Console]::CursorVisible = $oldVis } catch {}
        Cls
    }
}

# =============================================================================
#  MODE MENU
# =============================================================================

function script:Select-Mode {
    [Console]::WriteLine("")
    $opts = @(
        "Streaming    — podgląd ekranu przez scrcpy"
        "Terminal     — powłoka adb shell"
        "Transfer     — dwupanelowy menedżer plików  (PC ↔ /sdcard)"
    )
    if (-not $script:ScrcpyOk) { $opts[0] += '  [scrcpy nie zainstalowane]' }
    $choice = Prompt-Choice "Co chcesz zrobić?" $opts -Default 3
    return @('Streaming', 'Terminal', 'Files')[$choice - 1]
}

function script:Resolve-PhoneLocalPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "LocalPath nie może być pusty."
    }

    try {
        $resolved = Resolve-Path -LiteralPath $Path -ErrorAction Stop | Select-Object -First 1
        $item = Get-Item -LiteralPath $resolved.Path -ErrorAction Stop
    }
    catch {
        throw "LocalPath nie istnieje: $Path"
    }

    if (-not $item.PSIsContainer) {
        throw "LocalPath nie jest folderem: $($item.FullName)"
    }

    return $item.FullName
}

function script:Start-Mode([string]$ModeName, [string]$Serial, [string]$LocalPath, [string]$RemotePath) {
    switch ($ModeName) {
        'Streaming' { Start-Streaming  -Serial $Serial }
        'Terminal'  { Start-Terminal   -Serial $Serial }
        'Files'     {
            try {
                $resolvedLocalPath = Resolve-PhoneLocalPath -Path $LocalPath
            }
            catch {
                W-Err $_.Exception.Message
                return
            }
            Start-FileManager -Serial $Serial -LocalPath $resolvedLocalPath -RemotePath $RemotePath
        }
    }
}

# =============================================================================
#  MAIN ENTRY POINT
# =============================================================================

function Invoke-PwtPhone {
<#
.SYNOPSIS
    Android (ADB) helper — streaming, terminal, dwupanelowy transfer plików.

.DESCRIPTION
    Łączy się z urządzeniem Android przez USB lub Wi-Fi i oferuje trzy tryby:
      1. Streaming  — scrcpy (mirror ekranu z konfiguracją)
      2. Terminal   — adb shell (z opcjonalnym rootem / poleceniem / katalogiem)
      3. Transfer   — dwupanelowy TUI w stylu Total Commander (PC ↔ /sdcard)
                      F5=Kopiuj  F6=Przenieś  F7=MkDir  F8=Usuń

    Skrypt nie zapisuje żadnych plików konfiguracyjnych — IP, port i tryb
    wybierasz każdorazowo interaktywnie (lub przez parametry).

.PARAMETER Mode
    Tryb połączenia: Usb lub Wifi. Pytany interaktywnie jeśli pominięty.

.PARAMETER ModeAction
    Uruchom od razu: Streaming, Terminal lub Files. Menu jeśli pominięty.

.PARAMETER Ip
    Adres IP telefonu dla trybu Wi-Fi. Wykrywany automatycznie jeśli pominięty.

.PARAMETER Port
    Port TCP ADB (domyślnie 5555).

.PARAMETER DeviceId
    Numer seryjny konkretnego urządzenia. Pomija interaktywny wybór.

.PARAMETER LocalPath
    Startowy katalog lokalny dla trybu Transfer. Domyślnie: bieżący katalog.

.PARAMETER RemotePath
    Startowy katalog na telefonie. Domyślnie: /sdcard.

.PARAMETER NoCleanup
    Nie rozłączaj sesji ADB Wi-Fi po zakończeniu.

.PARAMETER Status
    Sprawdź adb, scrcpy i aktualnie widoczne urządzenia bez uruchamiania menu.

.EXAMPLE
    pwt phone
    Interaktywny — pyta o typ połączenia, potem o tryb.

.EXAMPLE
    pwt phone -Status
    Szybki raport narzędzi i urządzeń ADB.

.EXAMPLE
    pwt phone -Mode Usb -ModeAction Terminal
    Otwórz adb shell na telefonie USB, bez menu.

.EXAMPLE
    pwt phone -Mode Wifi -Ip 192.168.1.100 -ModeAction Streaming
    Połącz przez Wi-Fi i uruchom menu konfiguracji scrcpy.

.EXAMPLE
    pwt phone -Mode Wifi -Ip 192.168.1.100 -ModeAction Files -LocalPath D:\Zdjęcia -RemotePath /sdcard/DCIM
    Wi-Fi + menedżer plików Zdjęcia ↔ DCIM.
#>
    [CmdletBinding()]
    param(
        [ValidateSet('Usb', 'Wifi')][string]$Mode,
        [ValidateSet('Streaming', 'Terminal', 'Files')][string]$ModeAction,
        [string]$Ip,
        [ValidateRange(1, 65535)][int]$Port = 5555,
        [string]$DeviceId,
        [string]$LocalPath  = (Get-Location).Path,
        [string]$RemotePath = '/sdcard',
        [switch]$NoCleanup,
        [switch]$Status
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if ($Status) {
        Show-PwtPhoneStatus
        return
    }

    $FA = $script:C.FrameAct; $R = $script:C.Reset
    [Console]::WriteLine("")
    [Console]::WriteLine("  $FA╔══════════════════════════╗$R")
    [Console]::WriteLine("  $FA║   ◈  pwt  phone  ◈       ║$R")
    [Console]::WriteLine("  $FA╚══════════════════════════╝$R")
    [Console]::WriteLine("")

    if (-not (Test-Tool -Name 'adb' `
            -Description 'Android Debug Bridge — wymagany dla wszystkich operacji.' `
            -Winget 'Google.PlatformTools' `
            -Url 'https://developer.android.com/studio/releases/platform-tools')) { return }

    $script:ScrcpyOk = Test-Tool -Name 'scrcpy' `
        -Description 'Mirror ekranu — wymagany tylko dla trybu Streaming.' `
        -Winget 'Genymobile.scrcpy' `
        -Url 'https://github.com/Genymobile/scrcpy'

    Invoke-Adb -Argv @('start-server') -AllowFail | Out-Null
    Start-Sleep -Milliseconds 400
    $script:LastWifi = $null

    try {

        # ── TYP POŁĄCZENIA ────────────────────────────────────────────────────
        if (-not $Mode) {
            $connectionChoice = Prompt-Choice "Typ połączenia:" @(
                'USB  (zalecany przy pierwszej konfiguracji)'
                'Wi-Fi  (ADB przez TCP/IP)'
            ) -Default 1
            $Mode = @('Usb', 'Wifi')[$connectionChoice - 1]
        }

        # ── USB ───────────────────────────────────────────────────────────────
        if ($Mode -eq 'Usb') {
            W-Section "USB"
            W-Info "Szukam urządzeń USB…"

            $devs = @(Get-AdbDevices | Where-Object { $_.IsUSB })
            if ($devs.Count -eq 0) {
                W-Err "Nie wykryto urządzenia USB."
                W-Box -Col $script:C.Warn -Title ' Lista kontrolna ' -Lines @(
                    "Kabel USB obsługuje transfer danych (nie tylko ładowanie)"
                    "Debugowanie USB włączone w Opcjach programisty"
                    "Zaakceptowano 'Zezwolić na debugowanie USB?' na telefonie"
                    "Tryb USB ustawiony na Transfer plików / MTP"
                )
                return
            }

            $unauth = @($devs | Where-Object { $_.Unauthorized })
            if ($unauth.Count -gt 0 -and @($devs | Where-Object { $_.Ready }).Count -eq 0) {
                Show-Unauthorized; return
            }

            $ready = @($devs | Where-Object { $_.Ready })
            if ($ready.Count -eq 0) {
                W-Err "Brak gotowych urządzeń USB. Znalezione:"
                $devs | ForEach-Object { W-Dim "$($_.Serial)  ($($_.State))" }
                return
            }

            $picked = if ($DeviceId) {
                $ready | Where-Object { $_.Serial -eq $DeviceId } | Select-Object -First 1
            }
            elseif ($ready.Count -eq 1) { $ready[0] }
            else {
                $idx = (Prompt-Choice "Wybierz urządzenie:" ($ready | ForEach-Object { $_.Serial }) -Default 1) - 1
                $ready[$idx]
            }
            if (-not $picked) { W-Err "Nie znaleziono urządzenia."; return }
            W-OK "Używam urządzenia: $($picked.Serial)"

            $sel = if ($ModeAction) { $ModeAction } else { Select-Mode }
            Start-Mode -ModeName $sel -Serial $picked.Serial -LocalPath $LocalPath -RemotePath $RemotePath
            return
        }

        # ── WI-FI ─────────────────────────────────────────────────────────────
        if ($Mode -eq 'Wifi') {
            W-Section "Wi-Fi"
            [Console]::WriteLine("")
            W-Warn "ADB przez Wi-Fi otwiera port sieciowy na telefonie."
            W-Warn "Używaj tylko w zaufanych sieciach!"
            [Console]::WriteLine("")
            W-Info "Szukam urządzenia USB do konfiguracji Wi-Fi…"

            $usb = @(Get-AdbDevices | Where-Object { $_.IsUSB -and $_.Ready })
            if ($usb.Count -eq 0) {
                W-Err "Nie znaleziono urządzenia USB."
                W-Dim "Najpierw podłącz telefon przez USB, aby włączyć ADB Wi-Fi."
                return
            }

            $picked = if ($DeviceId) {
                $usb | Where-Object { $_.Serial -eq $DeviceId } | Select-Object -First 1
            }
            elseif ($usb.Count -eq 1) { $usb[0] }
            else {
                $idx = (Prompt-Choice "Wybierz urządzenie:" ($usb | ForEach-Object { $_.Serial }) -Default 1) - 1
                $usb[$idx]
            }
            if (-not $picked) { W-Err "Nie znaleziono urządzenia."; return }
            W-OK "Używam urządzenia: $($picked.Serial)"
            [Console]::WriteLine("")

            $tgtIp = if ($Ip) { $Ip } else { Get-PhoneIP -Serial $picked.Serial }
            if (-not $tgtIp) {
                W-Warn "Nie udało się automatycznie wykryć IP."
                W-Dim  "Znajdź je w: Ustawienia → Wi-Fi → Szczegóły sieci"
                $tgtIp = Read-Host "  Podaj adres IP telefonu"
            }
            else {
                W-OK "Wykryty IP: $tgtIp"
                if (-not (Prompt-YN "Użyć $tgtIp ?" $true)) {
                    $tgtIp = Read-Host "  Podaj adres IP telefonu"
                }
            }
            if (-not (Test-ValidIP $tgtIp)) { W-Err "Nieprawidłowy adres IP: $tgtIp"; return }

            [Console]::WriteLine("")
            W-Info "Przełączam urządzenie na tryb TCP/IP (port $Port)…"
            $r = Invoke-Adb -Argv @('-s', $picked.Serial, 'tcpip', $Port.ToString()) -AllowFail
            [Console]::WriteLine("$($script:C.Muted)$($r.Out -join "`n")$($script:C.Reset)")
            # Give the phone a moment to restart ADB in TCP mode
            Start-Sleep -Seconds 3

            $tgt = "${tgtIp}:${Port}"
            W-Info "Łączę z $tgt …"
            $r   = Invoke-Adb -Argv @('connect', $tgt) -AllowFail
            [Console]::WriteLine("$($script:C.Muted)$($r.Out -join "`n")$($script:C.Reset)")

            $out = $r.Out -join ''
            if (-not ($out -match 'connected to')) {
                W-Err "Nie udało się połączyć przez Wi-Fi."
                W-Box -Col $script:C.Warn -Title ' Rozwiązywanie problemów ' -Lines @(
                    "Sprawdź czy adres IP jest poprawny"
                    "Telefon i PC muszą być w tej samej sieci"
                    "Brak firewalla blokującego port $Port"
                    "Spróbuj odłączyć i ponownie podłączyć USB"
                )
                return
            }

            $script:LastWifi = $tgt
            [Console]::WriteLine("")
            W-OK "Możesz teraz odłączyć kabel USB."

            $sel = if ($ModeAction) { $ModeAction } else { Select-Mode }
            Start-Mode -ModeName $sel -Serial $tgt -LocalPath $LocalPath -RemotePath $RemotePath
            return
        }

    }
    finally {
        if (-not $NoCleanup -and $script:LastWifi) {
            [Console]::WriteLine("")
            W-Info "Przywracam ADB USB i rozłączam Wi-Fi ($($script:LastWifi))…"
            Invoke-Adb -Argv @('-s', $script:LastWifi, 'usb') -AllowFail | Out-Null
            Start-Sleep -Milliseconds 500
            Invoke-Adb -Argv @('disconnect', $script:LastWifi) -AllowFail | Out-Null
        }
    }
}

# ── pwt integration ────────────────────────────────────────────────────────────
if (Get-Command Register-PwtCommand -ErrorAction SilentlyContinue) {
    Register-PwtCommand -Name 'phone' -Category 'phone' `
        -Synopsis 'Android (ADB): streaming, terminal, dwupanelowy transfer plików' `
        -Function  'Invoke-PwtPhone' `
        -Requires  @('adb')
}

