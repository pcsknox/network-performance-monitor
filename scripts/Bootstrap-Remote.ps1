<#
    One-liner remote installer, meant to be pasted into a ScreenConnect Backstage
    command box (or any other remote shell). Downloads this repo from GitHub,
    installs it under $InstallDir, fetches the Ookla CLI, runs one test to verify,
    and registers the recurring scheduled task - all in a single command.

    ScreenConnect Backstage commands run through the ScreenConnect service, which
    is normally installed as NT AUTHORITY\SYSTEM, so no separate elevation step is
    needed for the scheduled task registration.

    Usage (paste as-is into a Backstage command box):
      powershell -ExecutionPolicy Bypass -Command "iex (irm https://raw.githubusercontent.com/pcsknox/network-performance-monitor/master/scripts/Bootstrap-Remote.ps1)"

    Optional overrides, e.g. a different interval:
      powershell -ExecutionPolicy Bypass -Command "& ([scriptblock]::Create((irm https://raw.githubusercontent.com/pcsknox/network-performance-monitor/master/scripts/Bootstrap-Remote.ps1))) -IntervalMinutes 15"
#>
param(
    [string]$RepoZipUrl = 'https://github.com/pcsknox/network-performance-monitor/archive/refs/heads/master.zip',
    [string]$InstallDir = 'C:\ProgramData\PCS\NetworkPerformanceMonitor',
    [int]$IntervalMinutes = 30,
    [string]$TaskName = 'NetworkPerformanceMonitor'
)

$ErrorActionPreference = 'Stop'

function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }

$tempZip = Join-Path $env:TEMP "npm-$(Get-Random).zip"
$tempExtract = Join-Path $env:TEMP "npm-$(Get-Random)-extract"

Write-Step "Downloading tool from $RepoZipUrl"
Invoke-WebRequest -Uri $RepoZipUrl -OutFile $tempZip -UseBasicParsing

Write-Step "Extracting"
Expand-Archive -Path $tempZip -DestinationPath $tempExtract -Force

$extractedRoot = Get-ChildItem -Path $tempExtract -Directory | Select-Object -First 1
if (-not $extractedRoot) { throw "Could not find extracted repo folder under $tempExtract" }

if (Test-Path -LiteralPath $InstallDir) {
    Write-Step "Existing install found at $InstallDir - updating scripts, keeping data\ and bin\"
    Copy-Item -Path (Join-Path $extractedRoot.FullName 'scripts\*') -Destination (Join-Path $InstallDir 'scripts') -Recurse -Force
    Copy-Item -Path (Join-Path $extractedRoot.FullName 'config\*') -Destination (Join-Path $InstallDir 'config') -Recurse -Force
    Copy-Item -Path (Join-Path $extractedRoot.FullName 'README.md') -Destination $InstallDir -Force
} else {
    Write-Step "Installing to $InstallDir"
    New-Item -ItemType Directory -Path (Split-Path $InstallDir) -Force -ErrorAction SilentlyContinue | Out-Null
    Move-Item -Path $extractedRoot.FullName -Destination $InstallDir
}

Remove-Item -Path $tempZip -Force -ErrorAction SilentlyContinue
Remove-Item -Path $tempExtract -Recurse -Force -ErrorAction SilentlyContinue

Write-Step "Fetching the Ookla Speedtest CLI"
& (Join-Path $InstallDir 'scripts\Install-Prerequisites.ps1')

Write-Step "Running one test to verify the setup"
& (Join-Path $InstallDir 'scripts\Run-SpeedTest.ps1')

Write-Step "Registering the scheduled task (every $IntervalMinutes minute(s), runs as SYSTEM)"
& (Join-Path $InstallDir 'scripts\Install-ScheduledTask.ps1') -IntervalMinutes $IntervalMinutes -TaskName $TaskName

Write-Step "Done. Installed at $InstallDir - view $InstallDir\data\report.html for results."
