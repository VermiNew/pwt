#!/usr/bin/env pwsh
#requires -Version 7.0

function Invoke-PwtYtDlp {
<#
.SYNOPSIS
    Friendly yt-dlp wrapper for video, audio and subtitle downloads.

.DESCRIPTION
    Builds a safe yt-dlp command line for common download modes:
      - Video / OnlyVideo       : video stream only
      - Audio / OnlyAudio       : audio only, extracted with ffmpeg
      - Subtitles / OnlySubtitles: subtitles only, no media download
      - VideoAudio              : best video + best audio merged
      - All                     : video + audio + subtitles

    Run without arguments to print available modes, presets and examples.
    Extra yt-dlp arguments can be passed with -ExtraArgs.

.PARAMETER Status
    Check whether yt-dlp and optional helper tools are available, then exit.

.PARAMETER Url
    One or more URLs to download.

.PARAMETER Mode
    Download mode. Default: VideoAudio.

.PARAMETER Preset
    Ready option set. Presets choose their own mode and should not be combined
    with -Mode.

.PARAMETER OutDir
    Directory for downloaded files. Created if it does not exist.

.PARAMETER OutputTemplate
    yt-dlp output template. Default keeps title and id.

.PARAMETER AudioFormat
    Audio format used for audio-only mode.

.PARAMETER SubLangs
    Subtitle languages for subtitle modes. Default: all,-live_chat.

.PARAMETER SubFormat
    Subtitle format preference. Default: srt/best.

.PARAMETER NoAutoSubtitles
    Do not include automatically generated subtitles in subtitle modes.

.PARAMETER EmbedSubtitles
    Embed subtitles in video files when Mode is All.

.PARAMETER NoRemoteEjs
    Do not add the default '--remote-components ejs:github'.

.PARAMETER PrintCommand
    Print the generated command and do not run yt-dlp.

.EXAMPLE
    pwt yt-dlp

.EXAMPLE
    pwt yt-dlp -Status

.EXAMPLE
    pwt yt-dlp "https://youtu.be/..." -Mode VideoAudio

.EXAMPLE
    pwt yt-dlp "https://youtu.be/..." -Mode OnlyAudio -AudioFormat mp3

.EXAMPLE
    pwt yt-dlp "https://youtu.be/..." -Mode OnlySubtitles -SubLangs "pl,en.*"

.EXAMPLE
    pwt yt-dlp "https://youtu.be/..." -Mode All -EmbedSubtitles

.EXAMPLE
    pwt yt-dlp "https://youtu.be/..." -Preset SubtitlesPl

.EXAMPLE
    pwt yt-dlp "https://youtu.be/..." -NoRemoteEjs
#>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [switch]$Status,

        [Parameter(Position = 0)]
        [string[]]$Url,

        [ValidateSet('Video', 'OnlyVideo', 'Audio', 'OnlyAudio', 'Subtitles', 'OnlySubtitles', 'VideoAudio', 'All')]
        [string]$Mode = 'VideoAudio',

        [ValidateSet('Archive', 'SubtitlesPl', 'Mobile')]
        [string]$Preset,

        [string]$OutDir = '.',

        [string]$OutputTemplate = '%(title).200B [%(id)s].%(ext)s',

        [ValidateSet('best', 'aac', 'alac', 'flac', 'm4a', 'mp3', 'opus', 'vorbis', 'wav')]
        [string]$AudioFormat = 'best',

        [string]$SubLangs = 'all,-live_chat',

        [string]$SubFormat = 'srt/best',

        [string]$MergeFormat = 'mp4/mkv',

        [string]$ArchiveFile = 'yt-dlp-archive.txt',

        [switch]$NoAutoSubtitles,

        [switch]$EmbedSubtitles,

        [switch]$NoPlaylist,

        [switch]$EmbedMetadata,

        [switch]$EmbedThumbnail,

        [switch]$NoRemoteEjs,

        [string[]]$ExtraArgs = @(),

        [switch]$PrintCommand
    )

    if ($Status) {
        $toolsOk = Show-PwtYtDlpStatus -NeedFfmpeg
        $global:LASTEXITCODE = if ($toolsOk) { 0 } else { 1 }
        return
    }

    if (-not $Url -or $Url.Count -eq 0) {
        Show-PwtYtDlpUsage
        $global:LASTEXITCODE = 0
        return
    }

    $normalizedMode = switch ($Mode) {
        'Video'        { 'OnlyVideo' }
        'Audio'        { 'OnlyAudio' }
        'Subtitles'    { 'OnlySubtitles' }
        default        { $Mode }
    }

    $presetArgs = @()
    switch ($Preset) {
        'Archive' {
            $normalizedMode = 'VideoAudio'
            $EmbedMetadata = $true
            $EmbedThumbnail = $true
        }
        'SubtitlesPl' {
            $normalizedMode = 'All'
            $SubLangs = 'pl,en.*'
            $SubFormat = 'srt/best'
            $EmbedSubtitles = $true
        }
        'Mobile' {
            $normalizedMode = 'VideoAudio'
            $MergeFormat = 'mp4'
            $EmbedMetadata = $true
            $presetArgs += @('--remux-video', 'mp4')
        }
    }

    if (-not (Test-PwtYtDlpOptions -Mode $normalizedMode -BoundParameters $PSBoundParameters `
                -MergeFormat $MergeFormat -SubLangs $SubLangs -SubFormat $SubFormat `
                -Preset $Preset -ArchiveFile $ArchiveFile -ExtraArgs $ExtraArgs)) {
        return
    }

    $needsFfmpeg = $normalizedMode -in @('OnlyAudio', 'VideoAudio', 'All')
    $toolsOk = Show-PwtYtDlpStatus -NeedFfmpeg:$needsFfmpeg -Quiet:$PrintCommand
    if (-not $toolsOk -and -not $PrintCommand) { return }

    try {
        $outDirCandidate = if ([System.IO.Path]::IsPathRooted($OutDir)) {
            $OutDir
        } else {
            Join-Path (Get-Location).Path $OutDir
        }
        $resolvedOutDir = [System.IO.Path]::GetFullPath($outDirCandidate)

        if (-not $PrintCommand) {
            if (-not (Test-Path -LiteralPath $resolvedOutDir -PathType Container)) {
                New-Item -ItemType Directory -Path $resolvedOutDir -Force -ErrorAction Stop | Out-Null
            }
            if (Test-Path -LiteralPath $resolvedOutDir -PathType Container) {
                $resolvedOutDir = (Resolve-Path -LiteralPath $resolvedOutDir -ErrorAction Stop).Path
            }
        }
    } catch {
        Write-PwtHost ""
        Write-PwtHost "  Output directory error: $($_.Exception.Message)" -ForegroundColor Red
        Write-PwtHost ""
        return
    }

    if ($Preset -eq 'Archive') {
        $presetArgs += @('--download-archive', (Join-Path $resolvedOutDir $ArchiveFile), '--continue', '--no-overwrites')
    }

    $ytArgs = @(
        '--windows-filenames',
        '-P', $resolvedOutDir,
        '-o', $OutputTemplate
    )

    if ($NoPlaylist) { $ytArgs += '--no-playlist' }

    $subtitleArgs = @(
        '--write-subs',
        '--sub-langs', $SubLangs,
        '--sub-format', $SubFormat
    )
    if (-not $NoAutoSubtitles) {
        $subtitleArgs += '--write-auto-subs'
    }

    switch ($normalizedMode) {
        'OnlyVideo' {
            $ytArgs += @('-f', 'bestvideo')
        }
        'OnlyAudio' {
            $ytArgs += @('-f', 'bestaudio', '-x', '--audio-format', $AudioFormat)
        }
        'OnlySubtitles' {
            $ytArgs += @('--skip-download')
            $ytArgs += $subtitleArgs
        }
        'VideoAudio' {
            $ytArgs += @('-f', 'bestvideo+bestaudio/best', '--merge-output-format', $MergeFormat)
        }
        'All' {
            $ytArgs += @('-f', 'bestvideo+bestaudio/best', '--merge-output-format', $MergeFormat)
            $ytArgs += $subtitleArgs
            if ($EmbedSubtitles) { $ytArgs += '--embed-subs' }
        }
    }

    if ($EmbedMetadata)  { $ytArgs += '--embed-metadata' }
    if ($EmbedThumbnail) { $ytArgs += '--embed-thumbnail' }
    if (-not $NoRemoteEjs) { $ytArgs += @('--remote-components', 'ejs:github') }
    if ($presetArgs)     { $ytArgs += $presetArgs }
    if ($ExtraArgs)      { $ytArgs += $ExtraArgs }

    $allArgs = @($ytArgs + $Url)

    if ($PrintCommand) {
        Write-PwtHost ""
        Write-PwtHost (Join-PwtYtDlpCommandLine -Command 'yt-dlp' -Arguments $allArgs) -ForegroundColor Cyan
        Write-PwtYtDlpOutputPath -Path $resolvedOutDir
        return
    }

    Write-PwtHost ""
    Write-PwtHost "  yt-dlp mode: " -NoNewline -ForegroundColor Cyan
    Write-PwtHost $normalizedMode -ForegroundColor White
    Write-PwtHost "  Output:      " -NoNewline -ForegroundColor Cyan
    Write-PwtHost $resolvedOutDir -ForegroundColor White
    Write-PwtHost ""

    if ($PSCmdlet.ShouldProcess(($Url -join ', '), "yt-dlp $normalizedMode")) {
        & yt-dlp @allArgs
        $global:LASTEXITCODE = $LASTEXITCODE
    }

    Write-PwtYtDlpOutputPath -Path $resolvedOutDir
}

function Show-PwtYtDlpUsage {
    Write-PwtHost ""
    Write-PwtHost "  pwt yt-dlp - YouTube/media downloader presets" -ForegroundColor Cyan
    Write-PwtHost "  ---------------------------------------------" -ForegroundColor DarkGray
    Write-PwtHost ""
    Write-PwtHost "  Usage:" -ForegroundColor Magenta
    Write-PwtHost "    pwt yt-dlp <url> [options]"
    Write-PwtHost "    pwt yt-dlp -Status"
    Write-PwtHost ""
    Write-PwtHost "  Modes:" -ForegroundColor Magenta
    Write-PwtHost "    OnlyVideo       - video stream only: bestvideo"
    Write-PwtHost "    OnlyAudio       - audio only: bestaudio + extract audio"
    Write-PwtHost "    OnlySubtitles   - subtitles only, no media download"
    Write-PwtHost "    VideoAudio      - bestvideo+bestaudio/best merged"
    Write-PwtHost "    All             - VideoAudio plus subtitles"
    Write-PwtHost ""
    Write-PwtHost "  Presets:" -ForegroundColor Magenta
    Write-PwtHost "    Archive         - VideoAudio + metadata + thumbnail + download archive"
    Write-PwtHost "    SubtitlesPl     - All + pl/en subtitles + embedded subtitles"
    Write-PwtHost "    Mobile          - VideoAudio + mp4 remux + metadata"
    Write-PwtHost ""
    Write-PwtHost "  Common options:" -ForegroundColor Magenta
    Write-PwtHost "    -OutDir <path>              Output directory"
    Write-PwtHost "    -OutputTemplate <template>  yt-dlp output template"
    Write-PwtHost "    -AudioFormat <format>       best, mp3, m4a, opus, flac, wav..."
    Write-PwtHost "    -SubLangs <langs>           e.g. pl,en.*,all,-live_chat"
    Write-PwtHost "    -SubFormat <format>         e.g. srt/best"
    Write-PwtHost "    -MergeFormat <format>       e.g. mp4, mkv, mp4/mkv"
    Write-PwtHost "    -ArchiveFile <file>         Archive preset file name"
    Write-PwtHost "    -NoPlaylist                 Download single item only"
    Write-PwtHost "    -EmbedMetadata              Embed metadata"
    Write-PwtHost "    -EmbedThumbnail             Embed thumbnail"
    Write-PwtHost "    -EmbedSubtitles             Embed subtitles with -Mode All"
    Write-PwtHost "    -NoRemoteEjs                Do not add --remote-components ejs:github"
    Write-PwtHost "    -PrintCommand               Show generated yt-dlp command"
    Write-PwtHost "    -ExtraArgs <args[]>         Pass through extra yt-dlp args"
    Write-PwtHost ""
    Write-PwtHost "  Examples:" -ForegroundColor Magenta
    Write-PwtHost "    pwt yt-dlp ""https://youtu.be/..."" -Mode VideoAudio"
    Write-PwtHost "    pwt yt-dlp ""https://youtu.be/..."" -Mode OnlyAudio -AudioFormat mp3"
    Write-PwtHost "    pwt yt-dlp ""https://youtu.be/..."" -Mode OnlySubtitles -SubLangs ""pl,en.*"""
    Write-PwtHost "    pwt yt-dlp ""https://youtu.be/..."" -Preset Archive"
    Write-PwtHost "    pwt yt-dlp ""https://youtu.be/..."" -Preset SubtitlesPl"
    Write-PwtHost "    pwt yt-dlp ""https://youtu.be/..."" -Preset Mobile -PrintCommand"
    Write-PwtHost "    pwt yt-dlp ""https://youtu.be/..."" -NoRemoteEjs"
    Write-PwtHost ""
}

function Show-PwtYtDlpStatus {
    param(
        [switch]$NeedFfmpeg,
        [switch]$Quiet
    )

    $ytDlp = Get-Command 'yt-dlp' -ErrorAction SilentlyContinue
    $ffmpeg = Get-Command 'ffmpeg' -ErrorAction SilentlyContinue
    $ffprobe = Get-Command 'ffprobe' -ErrorAction SilentlyContinue

    $ok = [bool]$ytDlp
    if ($NeedFfmpeg) {
        $ok = $ok -and [bool]$ffmpeg -and [bool]$ffprobe
    }

    if (-not $Quiet) {
        Write-PwtHost ""
        Write-PwtHost "  yt-dlp status" -ForegroundColor Cyan
        Write-PwtHost "  ------------" -ForegroundColor DarkGray
        Write-PwtYtDlpToolStatus -Name 'yt-dlp' -CommandInfo $ytDlp -Required
        Write-PwtYtDlpToolStatus -Name 'ffmpeg' -CommandInfo $ffmpeg -Required:$NeedFfmpeg
        Write-PwtYtDlpToolStatus -Name 'ffprobe' -CommandInfo $ffprobe -Required:$NeedFfmpeg
        Write-PwtHost ""
    }

    if (-not $ytDlp) {
        Test-PwtTool -Name 'yt-dlp' `
            -Description 'Required downloader.' `
            -Winget 'yt-dlp.yt-dlp' `
            -Url 'https://github.com/yt-dlp/yt-dlp' | Out-Null
    }
    if ($NeedFfmpeg -and -not $ffmpeg) {
        Test-PwtTool -Name 'ffmpeg' `
            -Description 'Required for audio extraction and merging separate video/audio streams.' `
            -Winget 'Gyan.FFmpeg' `
            -Url 'https://ffmpeg.org/download.html' | Out-Null
    }
    if ($NeedFfmpeg -and -not $ffprobe) {
        Test-PwtTool -Name 'ffprobe' `
            -Description 'Required by yt-dlp/ffmpeg post-processing.' `
            -Winget 'Gyan.FFmpeg' `
            -Url 'https://ffmpeg.org/download.html' | Out-Null
    }

    return $ok
}

function Write-PwtYtDlpToolStatus {
    param(
        [Parameter(Mandatory)][string]$Name,
        $CommandInfo,
        [switch]$Required
    )

    $label = if ($Required) { 'required' } else { 'optional' }
    if ($CommandInfo) {
        Write-PwtHost ("    {0,-8} " -f $Name) -NoNewline
        Write-PwtHost "[OK]      " -NoNewline -ForegroundColor Green
        Write-PwtHost "$label  " -NoNewline -ForegroundColor DarkGray
        Write-PwtHost $CommandInfo.Source -ForegroundColor White
    } else {
        $color = if ($Required) { 'Red' } else { 'Yellow' }
        $text = if ($Required) { '[MISSING]' } else { '[missing]' }
        Write-PwtHost ("    {0,-8} " -f $Name) -NoNewline
        Write-PwtHost ("{0,-9}" -f $text) -NoNewline -ForegroundColor $color
        Write-PwtHost "$label" -ForegroundColor DarkGray
    }
}

function Write-PwtYtDlpOutputPath {
    param([Parameter(Mandatory)][string]$Path)

    Write-PwtHost ""
    Write-PwtHost "  Output folder: " -NoNewline -ForegroundColor Cyan
    Write-PwtHost $Path -ForegroundColor White
    Write-PwtHost ""
}

function Test-PwtYtDlpOptions {
    param(
        [Parameter(Mandatory)][string]$Mode,
        [Parameter(Mandatory)][hashtable]$BoundParameters,
        [string]$MergeFormat,
        [string]$SubLangs,
        [string]$SubFormat,
        [string]$Preset,
        [string]$ArchiveFile,
        [string[]]$ExtraArgs
    )

    $errors = [System.Collections.Generic.List[string]]::new()
    $subtitleMode = $Mode -in @('OnlySubtitles', 'All')
    $mergeMode = $Mode -in @('VideoAudio', 'All')

    if ($BoundParameters.ContainsKey('AudioFormat') -and $Mode -ne 'OnlyAudio') {
        $errors.Add("-AudioFormat only works with -Mode OnlyAudio.")
    }
    if ($BoundParameters.ContainsKey('Preset') -and $BoundParameters.ContainsKey('Mode')) {
        $errors.Add("-Preset selects the mode on its own; do not combine it with -Mode.")
    }
    if ($BoundParameters.ContainsKey('ArchiveFile') -and $Preset -ne 'Archive') {
        $errors.Add("-ArchiveFile only works with -Preset Archive.")
    }
    if ($Preset -eq 'Archive' -and [string]::IsNullOrWhiteSpace($ArchiveFile)) {
        $errors.Add("-ArchiveFile cannot be empty for -Preset Archive.")
    }
    if ($BoundParameters.ContainsKey('MergeFormat') -and -not $mergeMode) {
        $errors.Add("-MergeFormat only works with -Mode VideoAudio or -Mode All.")
    }
    if ($BoundParameters.ContainsKey('SubLangs') -and -not $subtitleMode) {
        $errors.Add("-SubLangs only works with -Mode OnlySubtitles or -Mode All.")
    }
    if ($BoundParameters.ContainsKey('SubFormat') -and -not $subtitleMode) {
        $errors.Add("-SubFormat only works with -Mode OnlySubtitles or -Mode All.")
    }
    if ($BoundParameters.ContainsKey('NoAutoSubtitles') -and -not $subtitleMode) {
        $errors.Add("-NoAutoSubtitles only works with -Mode OnlySubtitles or -Mode All.")
    }
    if ($BoundParameters.ContainsKey('EmbedSubtitles') -and $Mode -ne 'All') {
        $errors.Add("-EmbedSubtitles only works with -Mode All.")
    }
    if ($Mode -eq 'OnlySubtitles' -and $BoundParameters.ContainsKey('EmbedMetadata')) {
        $errors.Add("-EmbedMetadata has no effect with -Mode OnlySubtitles.")
    }
    if ($Mode -eq 'OnlySubtitles' -and $BoundParameters.ContainsKey('EmbedThumbnail')) {
        $errors.Add("-EmbedThumbnail has no effect with -Mode OnlySubtitles.")
    }
    if ($mergeMode -and $MergeFormat -notmatch '^[A-Za-z0-9]+(/[A-Za-z0-9]+)*$') {
        $errors.Add("-MergeFormat should look like e.g. mp4, mkv or mp4/mkv.")
    }
    if ($subtitleMode -and [string]::IsNullOrWhiteSpace($SubLangs)) {
        $errors.Add("-SubLangs cannot be empty in subtitle modes.")
    }
    if ($subtitleMode -and [string]::IsNullOrWhiteSpace($SubFormat)) {
        $errors.Add("-SubFormat cannot be empty in subtitle modes.")
    }
    if ($ExtraArgs | Where-Object { [string]::IsNullOrWhiteSpace($_) }) {
        $errors.Add("-ExtraArgs contains an empty argument.")
    }

    if ($errors.Count -eq 0) {
        return $true
    }

    Write-PwtHost ""
    Write-PwtHost "  Invalid yt-dlp options:" -ForegroundColor Red
    foreach ($err in $errors) {
        Write-PwtHost "    - $err" -ForegroundColor Yellow
    }
    Write-PwtHost ""
    return $false
}

function Join-PwtYtDlpCommandLine {
    param(
        [Parameter(Mandatory)][string]$Command,
        [Parameter(Mandatory)][string[]]$Arguments
    )

    $parts = @($Command)
    foreach ($arg in $Arguments) {
        if ($arg -match '^[A-Za-z0-9_./:=,+@%[\]-]+$') {
            $parts += $arg
        } else {
            $parts += "'" + ($arg -replace "'", "''") + "'"
        }
    }
    return ($parts -join ' ')
}

if (Get-Command Register-PwtCommand -ErrorAction SilentlyContinue) {
    Register-PwtCommand -Name 'yt-dlp' -Category 'download' `
        -Synopsis 'Download video/audio/subtitles with yt-dlp presets' `
        -Function 'Invoke-PwtYtDlp' `
        -Requires @('yt-dlp')
}

