# pwt — PowerShell Tools

Personal PowerShell 7+ toolbox loaded automatically via `$PROFILE`.

## Requirements

- PowerShell 7+
- Windows 10/11

## Installation

```powershell
# Clone into your PowerShell profile directory
git clone https://github.com/VermiNew/pwt "$([Environment]::GetFolderPath('MyDocuments'))\PowerShell"
```

The profile loads `_pwt-core.ps1` first, then lazy-registers all `pwt-*.ps1` modules via regex scan — each script is dot-sourced only on first use, keeping shell startup fast.

## Usage

```
pwt list                # show all commands
pwt help <name>         # detailed help for a command
pwt edit <name>         # open source in editor
pwt reload              # reload profile
```

## Commands

| Command | Category | Description |
|---|---|---|
| `bigfiles` | files | Find the largest files in a directory tree |
| `bom` | dev | Check / fix UTF-8 BOM in .ps1 and .psm1 files |
| `clipfile` | clipboard | Copy a text file into the clipboard |
| `clipsave` | clipboard | Save clipboard content to a file (text / image / file-list) |
| `cleanspool` | printer | Clear stuck printer queue (Spooler restart + wipe) |
| `collect` | dev | Bundle text files into one markdown output for LLMs |
| `note` | misc | Append timestamped notes to `~/Documents/notes.md` |
| `parse` | dev | Validate .ps1 syntax via AST parser (no execution) |
| `phone` | phone | Android ADB helper — streaming, terminal, dual-pane file manager |
| `pinggy` | network | Expose a local port via Pinggy HTTPS tunnel |
| `pingmon` | network | Continuous ping with colored latency thresholds and stats |
| `portcheck` | network | Show what process is listening on a TCP port |
| `qr` | network | Generate a QR code (ASCII in terminal or PNG file) |
| `sha256it` | files | Hash a file (SHA-256 default), copy to clipboard, optional verify |
| `unlock` | files | Unblock files downloaded from the Internet (Zone.Identifier) |
| `watch` | system | Run a command repeatedly at fixed intervals (like Linux `watch`) |
| `whichinpath` | system | Show every PATH match for a command (including aliases/functions) |
| `yt-dlp` | download | Download video / audio / subtitles with yt-dlp presets |

## External tools (optional)

| Tool | Used by | Install |
|---|---|---|
| `adb` | `phone` | `winget install Google.PlatformTools` |
| `scrcpy` | `phone` (streaming mode) | `winget install Genymobile.scrcpy` |
| `yt-dlp` | `yt-dlp` | `winget install yt-dlp.yt-dlp` |
| `ffmpeg` | `yt-dlp` (audio/merge) | `winget install Gyan.FFmpeg` |
| `ssh` | `pinggy` | Built into Windows 10/11 |

## Legal notice

The `yt-dlp` wrapper (`pwt yt-dlp`) invokes [yt-dlp](https://github.com/yt-dlp/yt-dlp) as an external tool.
Downloading copyrighted content may violate the terms of service of the respective platforms or applicable copyright law.
Use responsibly and only for content you are legally entitled to download.

The `qr` command sends text to third-party public services (`qrenco.de`, `api.qrserver.com`) to generate QR codes.
Do not encode sensitive data.

## Conventions

- All `.ps1` / `.psm1` files: UTF-8 with BOM (`EF BB BF`)
- Each tool registers itself with `Register-PwtCommand` — no manual wiring needed
- Destructive operations always use `[CmdletBinding(SupportsShouldProcess)]` and require confirmation
- UI messages in Polish; code (variables, functions, comments) in English
