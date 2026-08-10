$Scripts = Join-Path (Split-Path $PROFILE) "Scripts"
. "$Scripts\_pwt-core.ps1"
Initialize-PwtLazyRegistry -ScriptsDir $Scripts
