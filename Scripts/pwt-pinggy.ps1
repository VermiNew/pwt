#!/usr/bin/env pwsh
#requires -Version 7.0

function Invoke-PwtPinggy {
<#
.SYNOPSIS
    Expose a local TCP port over HTTPS using a Pinggy SSH tunnel.

.DESCRIPTION
    Builds the canonical Pinggy SSH command line and streams its output,
    automatically copying the generated public URL to the clipboard.
    Useful for sharing a local dev server (Vite, webpack-dev-server, etc.)
    behind a public HTTPS endpoint.

    Credentials are read from -Login / -Password parameters or the
    PINGGY_USER / PINGGY_PASSWORD environment variables. If neither is
    set, the command prompts interactively.

.PARAMETER Port
    Local port to tunnel (default: 5173). Prompts if not provided.

.PARAMETER Login
    Pinggy account login. Default: $env:PINGGY_USER or an interactive prompt.

.PARAMETER Password
    Pinggy account password. Default: $env:PINGGY_PASSWORD or an interactive prompt.

.PARAMETER KeepAlive
    SSH ServerAliveInterval seconds (default: 30).

.PARAMETER ShowPassword
    Print the password verbatim in the info banner (off by default).

.EXAMPLE
    pwt pinggy 3000
    Tunnel localhost:3000.

.EXAMPLE
    pwt pinggy -Port 8080 -KeepAlive 60
    Custom port and keep-alive.

.EXAMPLE
    $env:PINGGY_USER = 'me'; $env:PINGGY_PASSWORD = 's3cret'; pwt pinggy 5173
    Provide credentials via environment variables.
#>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [ValidateRange(0, 65535)]
        [int]$Port = 0,

        [string]$Login,

        [string]$Password,

        [ValidateRange(1, 300)]
        [int]$KeepAlive = 30,

        [switch]$ShowPassword
    )

    if (-not (Test-PwtTool -Name 'ssh' `
        -Description 'Pinggy needs an SSH client (OpenSSH).' `
        -Winget 'Microsoft.OpenSSH.Beta' `
        -Url 'https://learn.microsoft.com/windows-server/administration/openssh/openssh_install_firstuse')) {
        return
    }

    if (-not $Login) {
        $Login = if ($env:PINGGY_USER) { $env:PINGGY_USER } else { Read-Host "Pinggy login" }
    }
    if (-not $Password) {
        if ($env:PINGGY_PASSWORD) {
            $Password = $env:PINGGY_PASSWORD
        } else {
            $secure = Read-Host "Pinggy password" -AsSecureString
            $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
            try {
                $Password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
            } finally {
                if ($bstr -ne [IntPtr]::Zero) {
                    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
                }
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($Login) -or [string]::IsNullOrWhiteSpace($Password)) {
        Write-PwtHost "Pinggy login and password are required." -ForegroundColor Red
        return
    }

    if ($Port -eq 0) {
        $portInput = Read-Host "Local port to expose (default 5173)"
        if ([string]::IsNullOrWhiteSpace($portInput)) {
            $Port = 5173
        } elseif (-not [int]::TryParse($portInput, [ref]$Port) -or $Port -lt 1 -or $Port -gt 65535) {
            Write-PwtHost "Invalid port." -ForegroundColor Red
            return
        }
    }

    $maskedPwd = if ($ShowPassword) { $Password } else { '*' * 8 }

    Write-PwtHost ""
    Write-PwtHost "  +-------------------------------+" -ForegroundColor Cyan
    Write-PwtHost "  |  Pinggy Tunnel - Access Info  |" -ForegroundColor Cyan
    Write-PwtHost "  +-------------------------------+" -ForegroundColor Cyan
    Write-PwtHost "    Login:        " -NoNewline; Write-PwtHost $Login        -ForegroundColor Green
    Write-PwtHost "    Password:     " -NoNewline; Write-PwtHost $maskedPwd    -ForegroundColor Green
    Write-PwtHost "    Local port:   " -NoNewline; Write-PwtHost $Port         -ForegroundColor Yellow
    Write-PwtHost "    Keep-alive:   " -NoNewline; Write-PwtHost "${KeepAlive}s" -ForegroundColor Yellow
    Write-PwtHost "    Web debugger: " -NoNewline; Write-PwtHost 'http://localhost:4300' -ForegroundColor Yellow
    Write-PwtHost ""
    Write-PwtHost "  Starting tunnel... (Ctrl+C to stop)" -ForegroundColor DarkGray
    Write-PwtHost ""

    $sshArgs = @(
        '-p', '443',
        '-L4300:127.0.0.1:4300',
        # Pinggy tunnels are ephemeral; do not write qr@eu.free.pinggy.io
        # host keys into the user's SSH known_hosts file.
        '-o', 'StrictHostKeyChecking=no',
        '-o', 'UserKnownHostsFile=/dev/null',
        '-o', "ServerAliveInterval=$KeepAlive",
        '-o', 'ExitOnForwardFailure=yes',
        '-t',
        "-R0:127.0.0.1:$Port",
        'qr@eu.free.pinggy.io',
        "b:${Login}:${Password}"
    )

    $urlCopied = $false
    & ssh @sshArgs 2>&1 | ForEach-Object {
        $line = $_
        Write-PwtHost $line

        if (-not $urlCopied -and $line -match 'https://[^\s]+\.pinggy\.[^\s]+') {
            $url = $matches[0]
            $urlCopied = $true
            try {
                Set-Clipboard -Value $url -ErrorAction Stop
                Write-PwtHost ""
                Write-PwtHost "  URL copied to clipboard: " -NoNewline -ForegroundColor Green
                Write-PwtHost $url -ForegroundColor Cyan
                Write-PwtHost "  Tip: " -NoNewline -ForegroundColor DarkGray
                Write-PwtHost "pwt qr -FromClipboard" -NoNewline -ForegroundColor Yellow
                Write-PwtHost " to share via QR." -ForegroundColor DarkGray
                Write-PwtHost ""
            } catch {
                Write-PwtHost ""
                Write-PwtHost "  Public URL: " -NoNewline -ForegroundColor Green
                Write-PwtHost $url -ForegroundColor Cyan
                Write-PwtHost "  (clipboard unavailable)" -ForegroundColor Yellow
                Write-PwtHost ""
            }
        }
    }

    if ($LASTEXITCODE -ne 0) {
        Write-PwtHost ""
        Write-PwtHost "  SSH tunnel exited with code $LASTEXITCODE" -ForegroundColor Red
        Write-PwtHost ""
    } else {
        Write-PwtHost ""
        Write-PwtHost "  Tunnel closed." -ForegroundColor Yellow
        Write-PwtHost ""
    }
}

if (Get-Command Register-PwtCommand -ErrorAction SilentlyContinue) {
    Register-PwtCommand -Name 'pinggy' -Category 'network' `
        -Synopsis 'Expose a local port via Pinggy HTTPS tunnel' `
        -Function 'Invoke-PwtPinggy' `
        -Requires @('ssh')
}

