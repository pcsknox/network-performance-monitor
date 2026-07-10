<#
    Registers a Windows Scheduled Task that runs Run-SpeedTest.ps1 on a recurring
    interval, as SYSTEM, so it keeps running whether or not anyone is logged on.
    Must be run from an elevated (Administrator) PowerShell session.
#>
param(
    [int]$IntervalMinutes,
    [string]$TaskName
)

. (Join-Path $PSScriptRoot 'Common.ps1')
$cfg = Get-Config

if (-not $IntervalMinutes) { $IntervalMinutes = $cfg.IntervalMinutes }
if (-not $TaskName) { $TaskName = $cfg.TaskName }

$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = (New-Object Security.Principal.WindowsPrincipal($currentUser)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "This script must be run from an elevated (Administrator) PowerShell session."
    return
}

$runScript = Join-Path $PSScriptRoot 'Run-SpeedTest.ps1'

$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$runScript`""

$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
    -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) `
    -RepetitionDuration (New-TimeSpan -Days 3650)

$principal = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -LogonType ServiceAccount -RunLevel Highest

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Write-Host "Task '$TaskName' already exists - replacing it."
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
    -Principal $principal -Settings $settings `
    -Description "Network Performance Monitor: runs an internet speed test every $IntervalMinutes minute(s) and logs the result." | Out-Null

Write-Host "Scheduled task '$TaskName' installed - runs every $IntervalMinutes minute(s) as SYSTEM."
Write-Host "Run it once manually now to verify: powershell -File `"$runScript`""
