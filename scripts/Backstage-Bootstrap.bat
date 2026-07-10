@echo off
:: One-shot remote installer for ScreenConnect Backstage.
:: Upload/run this single file via Backstage - no other files or arguments needed.
:: Downloads the tool from GitHub, installs it, fetches the Ookla CLI, runs one
:: verification test, and registers the 30-minute scheduled task.
::
:: Backstage commands run through cmd.exe (via the ScreenConnect service, which is
:: normally NT AUTHORITY\SYSTEM) - kept to single-quoted PowerShell strings here on
:: purpose, since nested double quotes are what breaks when pasted into Backstage.
powershell -NoProfile -ExecutionPolicy Bypass -Command "iex (irm 'https://raw.githubusercontent.com/pcsknox/network-performance-monitor/master/scripts/Bootstrap-Remote.ps1')"
