#!/usr/bin/env pwsh
#requires -Version 7.0

function Invoke-PwtQr {
<#
.SYNOPSIS
    Render a QR code in the terminal (or save as PNG).

.DESCRIPTION
    Generates a QR code from text or a URL. By default the code is rendered
    as ASCII directly into the terminal via qrenco.de (no installation
    required). With -Save the QR is saved as PNG via api.qrserver.com.

    Both endpoints are public services and require Internet access.

    Synergy tip: pair this with 'pwt pinggy' to instantly share the public
    URL by scanning a QR with your phone.

.PARAMETER Text
    Text or URL to encode. Optional if -FromClipboard is used.

.PARAMETER FromClipboard
    Take the text to encode from the clipboard.

.PARAMETER Save
    Save the QR as a PNG file instead of rendering in the terminal.

.PARAMETER OutFile
    Output file when -Save is used (default: qr-<timestamp>.png).

.PARAMETER SizePx
    PNG size in pixels when -Save is used (default: 400).

.EXAMPLE
    pwt qr "https://example.com"
    Render an ASCII QR in the terminal.

.EXAMPLE
    pwt qr -FromClipboard
    Encode whatever URL is currently on the clipboard.

.EXAMPLE
    pwt qr "wifi:T:WPA;S:MyNet;P:secret;;" -Save -OutFile wifi.png
    Save a QR for Wi-Fi config to wifi.png.
#>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Text,

        [switch]$FromClipboard,

        [switch]$Save,

        [string]$OutFile,

        [int]$SizePx = 400
    )

    if ($FromClipboard) {
        $clip = Get-Clipboard -Format Text -ErrorAction SilentlyContinue
        if (-not $clip) {
            Write-PwtHost "Clipboard is empty (no text)." -ForegroundColor Red
            return
        }
        $Text = $clip.Trim()
    }

    if (-not $Text) {
        Write-PwtHost "Provide text to encode (positional or -FromClipboard)." -ForegroundColor Red
        return
    }

    $encoded = [Uri]::EscapeDataString($Text)

    if ($Save) {
        if (-not $OutFile) {
            $OutFile = "qr-$(Get-Date -Format 'yyyyMMdd-HHmmss').png"
        }
        $url = "https://api.qrserver.com/v1/create-qr-code/?size=${SizePx}x${SizePx}&data=$encoded"
        try {
            Invoke-WebRequest -Uri $url -OutFile $OutFile -ErrorAction Stop
            $info = Get-Item $OutFile
            Write-PwtHost ""
            Write-PwtHost "  Saved QR to: $OutFile" -ForegroundColor Green
            Write-PwtHost "    Size: $(Format-PwtSize $info.Length)  ($SizePx x $SizePx px)"
            Write-PwtHost ""
        } catch {
            Write-PwtHost "QR save failed: $($_.Exception.Message)" -ForegroundColor Red
        }
        return
    }

    # Terminal ASCII via qrenco.de - it inspects User-Agent and serves
    # plain text when called by curl/wget/etc.
    $url = "https://qrenco.de/$encoded"
    try {
        $response = Invoke-WebRequest -Uri $url -Headers @{ 'User-Agent' = 'curl/7.0' } `
            -UseBasicParsing -ErrorAction Stop
        Write-PwtHost ""
        Write-PwtHost $response.Content
        Write-PwtHost ""
        Write-PwtHost "  Encoded: " -NoNewline -ForegroundColor Cyan
        Write-PwtHost $Text -ForegroundColor White
        Write-PwtHost ""
    } catch {
        Write-PwtHost "QR generation failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-PwtHost "Check your Internet connection." -ForegroundColor Yellow
    }
}

if (Get-Command Register-PwtCommand -ErrorAction SilentlyContinue) {
    Register-PwtCommand -Name 'qr' -Category 'network' `
        -Synopsis 'Generate a QR code (ASCII in terminal or PNG file)' `
        -Function 'Invoke-PwtQr'
}

