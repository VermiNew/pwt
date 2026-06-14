#!/usr/bin/env pwsh
#requires -Version 7.0

function Invoke-PwtCollect {
<#
.SYNOPSIS
    Collect text-file contents from a directory tree into one bundle (clipboard or file).

.DESCRIPTION
    Walks a folder, reads text files, and writes them all into one buffer
    using a markdown-friendly layout (one fenced block per file). Output
    goes to clipboard or file. Designed for feeding code to an LLM.

    Skips common noise by default (build outputs, lock files, binaries,
    media, archives, vcs metadata) and runs a fast binary-content check.

.PARAMETER Path
    Starting directory (default: current directory). Alias: -p

.PARAMETER OutputFile
    Output file name when writing to disk (default: collected_files.md). Alias: -o

.PARAMETER Clipboard
    Send output to clipboard instead of a file. Alias: -c

.PARAMETER Filter
    Hashtable with custom file patterns:
        @{ skip = '*.png','*.jpg'; search = '*.cs','*.ps1' }
      - 'skip'   : extra wildcards to EXCLUDE on top of built-ins.
      - 'search' : whitelist - only files matching at least one of these
                   patterns are kept (built-in skips still apply).

.PARAMETER MaxKB
    Skip files larger than N kilobytes (default: 8192). 0 = no limit.

.PARAMETER InteractiveExclude
    Show an interactive picker to exclude additional sub-folders. Alias: -i

.PARAMETER NoConfirm
    Skip the confirmation prompt before scanning. Alias: -y

.PARAMETER Silent
    Run without any prompts (requires -Clipboard or -OutputFile to choose
    output mode). Alias: -s

.EXAMPLE
    pwt collect
    Interactive: confirms target dir and asks where to write.

.EXAMPLE
    pwt collect -c -y
    Skip prompts, write to clipboard.

.EXAMPLE
    pwt collect -Filter @{ skip = '*.test.ts'; search = '*.ts','*.tsx' } -c -y
    Only TypeScript, exclude tests, clipboard, no confirm.

.EXAMPLE
    pwt collect -p C:\Project -o snapshot.md -MaxKB 100
    Write a snapshot to file, skip files over 100 KB.
#>
    [CmdletBinding()]
    param(
        [Alias('p')]
        [string]$Path = '.',

        [Alias('o')]
        [string]$OutputFile = 'collected_files.md',

        [Alias('c')]
        [switch]$Clipboard,

        [hashtable]$Filter,

        [int]$MaxKB = 8192,

        [Alias('i')]
        [switch]$InteractiveExclude,

        [Alias('y')]
        [switch]$NoConfirm,

        [Alias('s')]
        [switch]$Silent
    )

    # --- built-in skip patterns ------------------------------------------
    $skipDirs = @(
        '.git','.svn','.hg',
        'node_modules','bower_components','jspm_packages','vendor','packages',
        'bin','obj','build','dist','target','out',
        '.vs','.vscode','.idea',
        'logs','temp','tmp','.cache'
    )
    $skipFiles = @(
        '.gitignore','.gitattributes','.gitmodules','.hgignore',
        '*.exe','*.dll','*.so','*.dylib','*.bin','*.obj','*.o','*.a','*.lib','*.out','*.app',
        '.DS_Store','Thumbs.db','desktop.ini',
        '*.suo','*.user','*.userosscache','*.sln.docstates','*.swp','*.swo','*~',
        '*.log','*.tmp','*.temp','*.cache','*.bak','*.old',
        '*.zip','*.tar','*.gz','*.rar','*.7z','*.bz2','*.xz',
        '*.png','*.jpg','*.jpeg','*.gif','*.bmp','*.ico','*.webp','*.svg',
        '*.mp3','*.mp4','*.avi','*.mov','*.wmv','*.flv','*.wav',
        '*.pdf','*.doc','*.docx','*.xls','*.xlsx','*.ppt','*.pptx',
        '*.db','*.sqlite','*.sqlite3','*.mdb',
        'package-lock.json','yarn.lock','Gemfile.lock','Cargo.lock','pnpm-lock.yaml',
        '*.pyc','*.pyo','*.class','*.jar'
    )
    $omitContent = @('*.min.js','*.min.css','*.map','.env','.env.local','.env.production','.env.development')

    # --- merge user filter ------------------------------------------------
    $extraSkip   = @()
    $searchOnly  = @()
    if ($Filter) {
        if ($Filter.ContainsKey('skip'))   { $extraSkip  = @($Filter.skip) }
        if ($Filter.ContainsKey('search')) { $searchOnly = @($Filter.search) }
    }
    $skipFiles += $extraSkip

    # --- resolve / confirm ------------------------------------------------
    try {
        $startPath = (Resolve-Path $Path -ErrorAction Stop).Path
    } catch {
        Write-PwtHost "Path not found: $Path" -ForegroundColor Red
        return
    }

    # mode resolution
    $mode = if ($Clipboard) { 'clipboard' } else { 'file' }
    $outPath = $null

    if (-not $Silent) {
        if (-not $NoConfirm) {
            Write-PwtHost ""
            Write-PwtHost "  Scan directory: " -NoNewline -ForegroundColor Cyan
            Write-PwtHost $startPath -ForegroundColor White
            $ans = Read-Host "  Proceed? [Y/n]"
            if ($ans -and $ans -notmatch '^[Yy]') {
                Write-PwtHost "  Cancelled." -ForegroundColor Yellow
                return
            }
        }

        if (-not $Clipboard) {
            Write-PwtHost ""
            Write-PwtHost "  Output: [1] clipboard  [2] file '$OutputFile'  [3] custom path  [Q] cancel" -ForegroundColor Cyan
            $choice = (Read-Host "  Choose").ToUpper()
            switch ($choice) {
                '1' { $mode = 'clipboard' }
                '2' { $mode = 'file'; $outPath = Join-Path (Get-Location) $OutputFile }
                '3' {
                    $mode = 'file'
                    $cust = Read-Host "  Path"
                    if ([string]::IsNullOrWhiteSpace($cust)) {
                        $outPath = Join-Path (Get-Location) $OutputFile
                    } elseif ([System.IO.Path]::IsPathRooted($cust)) {
                        $outPath = $cust
                    } else {
                        $outPath = Join-Path (Get-Location) $cust
                    }
                }
                'Q' { Write-PwtHost "  Cancelled." -ForegroundColor Yellow; return }
                default { Write-PwtHost "  Cancelled." -ForegroundColor Yellow; return }
            }
        }
    }

    if ($mode -eq 'file' -and -not $outPath) {
        $outPath = Join-Path (Get-Location) $OutputFile
    }

    # --- interactive folder exclusion ------------------------------------
    if ($InteractiveExclude -and -not $Silent) {
        $extraDirs = Show-CollectExcludeUI -BasePath $startPath -CurrentSkips $skipDirs
        $skipDirs += $extraDirs
    }

    # --- gather files -----------------------------------------------------
    $stats = [PSCustomObject]@{
        Total = 0; Processed = 0; Omitted = 0; Skipped = 0; Errors = 0; Bytes = 0L
        Started = Get-Date
    }

    Write-PwtHost ""
    Write-PwtHost "  Scanning..." -ForegroundColor DarkCyan

    $maxBytes = if ($MaxKB -gt 0) { $MaxKB * 1KB } else { [long]::MaxValue }

    $files = @(Get-ChildItem -Path $startPath -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object {
            # skip if file matches built-in/extra skip patterns
            if (Test-AnyPattern $_.Name $skipFiles)        { return $false }
            # skip if any path segment matches a skipped directory
            $parts = $_.FullName -split '[\\/]'
            foreach ($seg in $parts) { if ($skipDirs -contains $seg) { return $false } }
            # apply whitelist (search) if provided
            if ($searchOnly.Count -gt 0 -and -not (Test-AnyPattern $_.Name $searchOnly)) {
                return $false
            }
            # skip if writing to file and we'd read our own output
            if ($mode -eq 'file' -and $_.FullName -eq $outPath) { return $false }
            $true
        })

    $stats.Total = $files.Count
    Write-PwtHost "  Found $($files.Count) candidate file(s)" -ForegroundColor Green
    Write-PwtHost ""

    # --- write header to buffer ------------------------------------------
    $sb = [System.Text.StringBuilder]::new()
    $void = $sb.AppendLine("# File collection")
    $void = $sb.AppendLine()
    $void = $sb.AppendLine("- Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    $void = $sb.AppendLine("- Source:    $startPath")
    $void = $sb.AppendLine("- Files:     $($files.Count)")
    $void = $sb.AppendLine()
    $void = $sb.AppendLine("---")
    $void = $sb.AppendLine()

    $i = 0
    foreach ($file in $files) {
        $i++
        $rel = $file.FullName.Substring($startPath.Length).TrimStart('\','/')
        $rel = $rel -replace '\\','/'

        # progress every 10 files (or last)
        if ($i % 10 -eq 0 -or $i -eq $files.Count) {
            $pct = [Math]::Round(($i / $files.Count) * 100)
            Write-PwtHost ("`r  [{0,3}%] ({1}/{2}) {3}" -f $pct, $i, $files.Count, $rel) -NoNewline -ForegroundColor DarkCyan
        }

        $stats.Bytes += $file.Length

        $void = $sb.AppendLine("## ``$rel``")
        $void = $sb.AppendLine("`n*$($file.Length) bytes - modified $($file.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))*`n")

        if (Test-AnyPattern $file.Name $omitContent) {
            $void = $sb.AppendLine('```')
            $void = $sb.AppendLine('(content omitted by pattern)')
            $void = $sb.AppendLine('```')
            $stats.Omitted++
        } elseif ($file.Length -gt $maxBytes) {
            $void = $sb.AppendLine('```')
            $void = $sb.AppendLine("(file too large: $(Format-PwtSize $file.Length) > limit $MaxKB KB)")
            $void = $sb.AppendLine('```')
            $stats.Omitted++
        } elseif (Test-IsBinaryFile $file.FullName) {
            $void = $sb.AppendLine('```')
            $void = $sb.AppendLine('(binary file - content skipped)')
            $void = $sb.AppendLine('```')
            $stats.Skipped++
        } else {
            try {
                $content = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop
                $lang = Get-FenceLang $file.Name
                $void = $sb.AppendLine('```' + $lang)
                $void = $sb.AppendLine($content.TrimEnd())
                $void = $sb.AppendLine('```')
                $stats.Processed++
            } catch {
                $void = $sb.AppendLine('```')
                $void = $sb.AppendLine("(read error: $($_.Exception.Message))")
                $void = $sb.AppendLine('```')
                $stats.Errors++
            }
        }

        $void = $sb.AppendLine()
    }

    Write-PwtHost ""

    # --- write output -----------------------------------------------------
    if ($mode -eq 'clipboard') {
        try {
            Set-Clipboard -Value $sb.ToString() -ErrorAction Stop
            Write-PwtHost "  [OK] Copied to clipboard" -ForegroundColor Green
        } catch {
            Write-PwtHost "  Clipboard failed ($($_.Exception.Message)); writing to file." -ForegroundColor Yellow
            $outPath = Join-Path (Get-Location) $OutputFile
            Set-Content -LiteralPath $outPath -Value $sb.ToString() -Encoding UTF8
            $mode = 'file'
            Write-PwtHost "  [OK] Saved to $outPath" -ForegroundColor Green
        }
    } else {
        Set-Content -LiteralPath $outPath -Value $sb.ToString() -Encoding UTF8
        Write-PwtHost "  [OK] Saved to $outPath" -ForegroundColor Green
    }

    # --- summary ----------------------------------------------------------
    $elapsed = (Get-Date) - $stats.Started
    Write-PwtHost ""
    Write-PwtHost "  --- summary ---" -ForegroundColor Cyan
    Write-PwtHost ("    candidates:  {0}" -f $stats.Total)
    Write-PwtHost ("    processed:   {0}" -f $stats.Processed) -ForegroundColor Green
    Write-PwtHost ("    omitted:     {0}" -f $stats.Omitted)   -ForegroundColor Yellow
    Write-PwtHost ("    binary:      {0}" -f $stats.Skipped)   -ForegroundColor Yellow
    Write-PwtHost ("    errors:      {0}" -f $stats.Errors)    -ForegroundColor $(if($stats.Errors){'Red'}else{'Green'})
    Write-PwtHost ("    bytes seen:  {0}" -f (Format-PwtSize $stats.Bytes))
    Write-PwtHost ("    elapsed:     {0:mm\:ss}" -f $elapsed)
    Write-PwtHost ""
}

# ---------------------------------------------------------------------------
# Helpers (script-private; not exported into pwt registry)
# ---------------------------------------------------------------------------

function Test-AnyPattern {
    param([string]$Name, [string[]]$Patterns)
    foreach ($p in $Patterns) {
        if ($Name -like $p) { return $true }
    }
    return $false
}

function Test-IsBinaryFile {
    param([string]$FilePath)
    $stream = $null
    try {
        $stream = [System.IO.File]::OpenRead($FilePath)
        $buf = New-Object byte[] 4096
        $bytes = $stream.Read($buf, 0, 4096)
        if ($bytes -eq 0) { return $false }
        # > 5 null bytes in first 4 KB -> treat as binary
        $nulls = 0; $i = 0
        while ($i -lt $bytes) {
            $idx = [Array]::IndexOf($buf, [byte]0, $i, $bytes - $i)
            if ($idx -lt 0) { break }
            $nulls++
            if ($nulls -gt 5) { return $true }
            $i = $idx + 1
        }
        return $false
    } catch {
        return $true
    } finally {
        if ($stream) { $stream.Dispose() }
    }
}

function Get-FenceLang {
    param([string]$FileName)
    $ext = [System.IO.Path]::GetExtension($FileName).TrimStart('.').ToLowerInvariant()
    switch ($ext) {
        'ps1'  { 'powershell' }
        'psm1' { 'powershell' }
        'psd1' { 'powershell' }
        'cs'   { 'csharp' }
        'ts'   { 'typescript' }
        'tsx'  { 'tsx' }
        'js'   { 'javascript' }
        'jsx'  { 'jsx' }
        'py'   { 'python' }
        'rb'   { 'ruby' }
        'go'   { 'go' }
        'rs'   { 'rust' }
        'java' { 'java' }
        'kt'   { 'kotlin' }
        'sh'   { 'bash' }
        'yml'  { 'yaml' }
        'yaml' { 'yaml' }
        'json' { 'json' }
        'xml'  { 'xml' }
        'html' { 'html' }
        'css'  { 'css' }
        'scss' { 'scss' }
        'md'   { 'markdown' }
        'sql'  { 'sql' }
        'toml' { 'toml' }
        default { $ext }
    }
}

function Show-CollectExcludeUI {
    param([string]$BasePath, [string[]]$CurrentSkips)

    $dirs = @(Get-ChildItem -Path $BasePath -Directory -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $CurrentSkips -notcontains $_.Name } |
        ForEach-Object {
            [PSCustomObject]@{
                Full = $_.FullName
                Rel  = ($_.FullName.Substring($BasePath.Length).TrimStart('\','/') -replace '\\','/')
            }
        } | Sort-Object Rel)

    if ($dirs.Count -eq 0) { return @() }

    Write-PwtHost ""
    Write-PwtHost "  Found $($dirs.Count) sub-directories:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $dirs.Count; $i++) {
        Write-PwtHost ("    [{0,3}] {1}" -f ($i + 1), $dirs[$i].Rel) -ForegroundColor Magenta
    }
    Write-PwtHost ""
    $ans = Read-Host "  Exclude (e.g. 1-5,7,10 / all / none)"
    if (-not $ans -or $ans -ieq 'none') { return @() }
    if ($ans -ieq 'all') {
        return ($dirs | ForEach-Object { Split-Path $_.Full -Leaf })
    }
    $idxs = @()
    foreach ($part in ($ans -split ',')) {
        $p = $part.Trim()
        if ($p -match '^(\d+)-(\d+)$') {
            $idxs += [int]$matches[1]..[int]$matches[2]
        } elseif ($p -match '^\d+$') {
            $idxs += [int]$p
        }
    }
    $idxs = $idxs | Where-Object { $_ -ge 1 -and $_ -le $dirs.Count } | Select-Object -Unique
    return $idxs | ForEach-Object { Split-Path $dirs[$_ - 1].Full -Leaf }
}

if (Get-Command Register-PwtCommand -ErrorAction SilentlyContinue) {
    Register-PwtCommand -Name 'collect' -Category 'dev' `
        -Synopsis 'Bundle text files in a tree into one output (clipboard or file) for LLMs' `
        -Function 'Invoke-PwtCollect'
}

