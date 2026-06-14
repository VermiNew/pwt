#!/usr/bin/env pwsh
#requires -Version 7.0

function Invoke-PwtClipSave {
<#
.SYNOPSIS
    Save the current clipboard content to a file (auto-detects type).

.DESCRIPTION
    Detects what is on the clipboard and persists it:
      - Text     -> .txt
      - Image    -> .png
      - File list -> .txt with one path per line

    If you don't pass -Path a timestamped file name is generated in the
    current directory (or -OutDir if specified).

.PARAMETER Path
    Output file path. Extension is added if missing. If omitted a name like
    'clip-20260509-153045.png' is generated.

.PARAMETER OutDir
    Directory to write into when -Path is omitted (default: current dir).

.PARAMETER Force
    Overwrite if the destination file already exists.

.EXAMPLE
    pwt clipsave
    Auto-detect clipboard type, save with timestamped name in current dir.

.EXAMPLE
    pwt clipsave note.txt
    Save text clipboard explicitly to note.txt.

.EXAMPLE
    pwt clipsave -OutDir C:\Temp
    Auto-named save into C:\Temp.
#>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Path,

        [string]$OutDir = '.',

        [switch]$Force
    )

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

    function Resolve-OutPath([string]$Suggested, [string]$DefaultExtension) {
        if ($Path) {
            $target = if ([System.IO.Path]::IsPathRooted($Path)) {
                $Path
            } else {
                Join-Path $OutDir $Path
            }
            if ($DefaultExtension -and -not [System.IO.Path]::GetExtension($target)) {
                $target = [System.IO.Path]::ChangeExtension($target, $DefaultExtension)
            }
            return $target
        }
        return Join-Path $OutDir $Suggested
    }

    function Test-Overwrite([string]$Target) {
        if ((Test-Path $Target) -and -not $Force) {
            Write-PwtHost "File already exists: $Target" -ForegroundColor Red
            Write-PwtHost "Use -Force to overwrite." -ForegroundColor Yellow
            return $false
        }
        return $true
    }

    # 1) Image takes priority (matches user expectations - screenshots)
    $img = Get-Clipboard -Format Image -ErrorAction SilentlyContinue
    if ($img) {
        $target = Resolve-OutPath "clip-$stamp.png" '.png'
        if (-not (Test-Overwrite $target)) { return }
        try {
            $img.Save($target, [System.Drawing.Imaging.ImageFormat]::Png)
            $info = Get-Item $target
            Write-PwtHost ""
            Write-PwtHost "  Saved IMAGE to: $target" -ForegroundColor Green
            Write-PwtHost "    Dimensions: $($img.Width)x$($img.Height)"
            Write-PwtHost "    Size:       $(Format-PwtSize $info.Length)"
            Write-PwtHost ""
        } finally {
            $img.Dispose()
        }
        return
    }

    # 2) File drop list (Copy in Explorer)
    $files = Get-Clipboard -Format FileDropList -ErrorAction SilentlyContinue
    if ($files -and $files.Count -gt 0) {
        $target = Resolve-OutPath "clip-files-$stamp.txt" '.txt'
        if (-not (Test-Overwrite $target)) { return }
        $files | ForEach-Object { $_.FullName } | Set-Content -LiteralPath $target -Encoding UTF8
        Write-PwtHost ""
        Write-PwtHost "  Saved FILE LIST to: $target" -ForegroundColor Green
        Write-PwtHost "    Items: $($files.Count)"
        Write-PwtHost ""
        return
    }

    # 3) Plain text
    $text = Get-Clipboard -Format Text -ErrorAction SilentlyContinue
    if ($text) {
        $target = Resolve-OutPath "clip-$stamp.txt" '.txt'
        if (-not (Test-Overwrite $target)) { return }
        Set-Content -LiteralPath $target -Value $text -Encoding UTF8
        $info = Get-Item $target
        Write-PwtHost ""
        Write-PwtHost "  Saved TEXT to: $target" -ForegroundColor Green
        Write-PwtHost "    Size:  $(Format-PwtSize $info.Length)"
        Write-PwtHost "    Lines: $(($text -split "`n").Count)"
        Write-PwtHost ""
        return
    }

    Write-PwtHost "Clipboard is empty (no text, image, or files)." -ForegroundColor Yellow
}

if (Get-Command Register-PwtCommand -ErrorAction SilentlyContinue) {
    Register-PwtCommand -Name 'clipsave' -Category 'clipboard' `
        -Synopsis 'Save clipboard content to a file (auto-detect text/image/files)' `
        -Function 'Invoke-PwtClipSave'
}

