<#
    Removes the scheduled task created by Install-ScheduledTask.ps1.
    Must be run from an elevated (Administrator) PowerShell session.
#>
param(
    [string]$TaskName
)

. (Join-Path $PSScriptRoot 'Common.ps1')
$cfg = Get-Config
if (-not $TaskName) { $TaskName = $cfg.TaskName }

if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "Scheduled task '$TaskName' removed."
} else {
    Write-Host "No scheduled task named '$TaskName' found."
}
