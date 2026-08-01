#requires -Version 7.0
$Scripts = "$PSScriptRoot\Scripts"

# === PowerShell Tools (pwt) ===
# Core MUST load first - it provides Register-PwtCommand and the dispatcher.
. "$Scripts\_pwt-core.ps1"

# Lazy-register all pwt-*.ps1 modules (no dot-source yet — loads on first use).
Initialize-PwtLazyRegistry -ScriptsDir $Scripts

# Convenience: edit profile in edit.exe (fallback to notepad).
function Edit-Profile {
    if (Get-Command edit.exe -ErrorAction SilentlyContinue) {
        edit.exe $PROFILE
    } else {
        notepad $PROFILE
    }
}
Set-Alias -Name psconfig -Value Edit-Profile
