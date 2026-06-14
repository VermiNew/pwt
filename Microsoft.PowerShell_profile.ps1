#requires -Version 7.0
$Scripts = "$PSScriptRoot\Scripts"

# === PowerShell Tools (pwt) ===
# Core MUST load first - it provides Register-PwtCommand and the dispatcher.
. "$Scripts\_pwt-core.ps1"

# Auto-load every pwt-*.ps1 module. Each registers itself with the dispatcher.
Get-ChildItem "$Scripts\pwt-*.ps1" -ErrorAction SilentlyContinue |
    ForEach-Object { . $_.FullName }

# Convenience: edit profile in edit.exe (fallback to notepad).
function Edit-Profile {
    if (Get-Command edit.exe -ErrorAction SilentlyContinue) {
        edit.exe $PROFILE
    } else {
        notepad $PROFILE
    }
}
Set-Alias -Name psconfig -Value Edit-Profile
