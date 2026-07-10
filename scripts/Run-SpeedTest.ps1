<#
    Runs one speed test cycle: Ookla (speedtest.net engine) primary, fast.com fallback
    if Ookla is unavailable or fails. Appends the result to data\speedtest_log.csv and
    regenerates data\report.html.

    Intended to be invoked by the scheduled task created via Install-ScheduledTask.ps1,
    but can also be run manually to test the setup or capture an on-demand reading.
#>

. (Join-Path $PSScriptRoot 'Common.ps1')

$cfg = Get-Config

$result = Invoke-OoklaTest -ExePath $cfg.OoklaExePath -TimeoutSeconds $cfg.TimeoutSeconds

if (-not $result.Success -and $cfg.EnableFastComFallback) {
    Write-Warning "Ookla test failed ($($result.ErrorMessage)) - falling back to fast.com"
    $result = Invoke-FastComTest -TimeoutSeconds $cfg.TimeoutSeconds
}

Write-SpeedTestResult -DataDir $cfg.DataDir -Result $result

if ($result.Success) {
    Write-Host "[$($result.Source)] Download: $($result.DownloadMbps) Mbps  Upload: $($result.UploadMbps) Mbps  Ping: $($result.PingMs) ms"
} else {
    Write-Warning "Speed test failed: $($result.ErrorMessage)"
}

try {
    & (Join-Path $PSScriptRoot 'New-Report.ps1') | Out-Null
} catch {
    Write-Warning "Report generation failed: $($_.Exception.Message)"
}
