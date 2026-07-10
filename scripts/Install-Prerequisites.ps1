<#
    Downloads the official Ookla Speedtest CLI (a single self-contained .exe, no
    installer, no other dependencies) into the bin\ folder.

    If this URL ever 404s because Ookla shipped a newer version, download the
    "Windows 64-bit" CLI zip yourself from https://www.speedtest.net/apps/cli
    and extract speedtest.exe into the bin\ folder next to this script's parent.
#>
param(
    [string]$DownloadUrl = 'https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-win64.zip'
)

$root = Split-Path -Parent $PSScriptRoot
$binDir = Join-Path $root 'bin'
$zipPath = Join-Path $binDir 'ookla-speedtest.zip'
$exePath = Join-Path $binDir 'speedtest.exe'

if (Test-Path -LiteralPath $exePath) {
    Write-Host "speedtest.exe already present at $exePath - nothing to do."
    return
}

New-Item -ItemType Directory -Path $binDir -Force | Out-Null

Write-Host "Downloading Ookla Speedtest CLI from $DownloadUrl ..."
try {
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $zipPath -UseBasicParsing
} catch {
    Write-Error "Download failed: $($_.Exception.Message)`nManually download the Windows 64-bit CLI zip from https://www.speedtest.net/apps/cli and extract speedtest.exe into $binDir"
    return
}

Write-Host "Extracting..."
Expand-Archive -Path $zipPath -DestinationPath $binDir -Force
Remove-Item -Path $zipPath -Force

if (Test-Path -LiteralPath $exePath) {
    Write-Host "speedtest.exe installed at $exePath"
} else {
    Write-Warning "Extraction finished but speedtest.exe was not found in $binDir - check the zip contents."
}
