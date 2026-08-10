$PWT_TOOLKIT_SCRIPTS_FOLDER_PATH = Join-Path (Split-Path $PROFILE) "Scripts"
. "$PWT_TOOLKIT_SCRIPTS_FOLDER_PATH\_pwt-core.ps1"
Initialize-PwtLazyRegistry -ScriptsDir $Scripts
