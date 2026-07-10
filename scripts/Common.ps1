function Get-ToolRoot {
    Split-Path -Parent $PSScriptRoot
}

function Get-Config {
    $root = Get-ToolRoot
    $configPath = Join-Path $root 'config\settings.json'
    $cfg = Get-Content -Path $configPath -Raw | ConvertFrom-Json

    [PSCustomObject]@{
        IntervalMinutes       = $cfg.IntervalMinutes
        EnableFastComFallback = $cfg.EnableFastComFallback
        OoklaExePath          = Join-Path $root $cfg.OoklaExeRelativePath
        DataDir               = Join-Path $root $cfg.DataDirRelativePath
        TaskName              = $cfg.TaskName
        TimeoutSeconds        = $cfg.TimeoutSeconds
        ToolRoot              = $root
    }
}

function Invoke-OoklaTest {
    param(
        [Parameter(Mandatory)][string]$ExePath,
        [int]$TimeoutSeconds = 45
    )

    if (-not (Test-Path -LiteralPath $ExePath)) {
        return [PSCustomObject]@{
            Success = $false; Source = 'Ookla'
            DownloadMbps = $null; UploadMbps = $null; PingMs = $null; JitterMs = $null; PacketLossPct = $null
            ISP = $null; ServerName = $null; ServerLocation = $null
            ErrorMessage = "speedtest.exe not found at $ExePath. Run Install-Prerequisites.ps1 or place the Ookla CLI there manually."
        }
    }

    try {
        $job = Start-Job -ScriptBlock {
            param($exe)
            & $exe --accept-license --accept-gdpr --format=json 2>&1
        } -ArgumentList $ExePath

        $completed = Wait-Job -Job $job -Timeout $TimeoutSeconds
        if (-not $completed) {
            Stop-Job -Job $job -ErrorAction SilentlyContinue
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
            throw "speedtest.exe timed out after $TimeoutSeconds seconds"
        }

        $rawOutput = Receive-Job -Job $job
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue

        $jsonLine = $rawOutput | Where-Object { $_ -match '^\s*\{' } | Select-Object -Last 1
        if (-not $jsonLine) { throw "No JSON result returned by speedtest.exe. Raw output: $($rawOutput -join ' ')" }

        $result = $jsonLine | ConvertFrom-Json
        if ($result.type -eq 'error' -or -not $result.download) {
            throw "speedtest.exe reported an error: $($result.message)"
        }

        [PSCustomObject]@{
            Success        = $true
            Source         = 'Ookla'
            DownloadMbps   = [Math]::Round(($result.download.bandwidth * 8) / 1000000, 2)
            UploadMbps     = [Math]::Round(($result.upload.bandwidth * 8) / 1000000, 2)
            PingMs         = [Math]::Round($result.ping.latency, 2)
            JitterMs       = [Math]::Round($result.ping.jitter, 2)
            PacketLossPct  = $result.packetLoss
            ISP            = $result.isp
            ServerName     = $result.server.name
            ServerLocation = "$($result.server.location), $($result.server.country)"
            ErrorMessage   = ''
        }
    } catch {
        [PSCustomObject]@{
            Success = $false; Source = 'Ookla'
            DownloadMbps = $null; UploadMbps = $null; PingMs = $null; JitterMs = $null; PacketLossPct = $null
            ISP = $null; ServerName = $null; ServerLocation = $null
            ErrorMessage = $_.Exception.Message
        }
    }
}

function Invoke-FastComTest {
    param(
        [int]$UrlCount = 5,
        [int]$TimeoutSeconds = 30
    )

    $client = $null
    try {
        # Public token used by fast.com's own web client to request test targets.
        $token = 'YXNkZmFzZGxmbnNkYWZoYXNkZmhrYWxm'
        $apiUrl = "https://api.fast.com/netflix/speedtest/v2?https=true&token=$token&urlCount=$UrlCount"
        $meta = Invoke-RestMethod -Uri $apiUrl -TimeoutSec 15

        $urls = $meta.targets | Select-Object -ExpandProperty url
        if (-not $urls) { throw "fast.com returned no test targets" }

        Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue
        $client = New-Object System.Net.Http.HttpClient
        $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)

        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $tasks = foreach ($u in $urls) { $client.GetByteArrayAsync($u) }
        [System.Threading.Tasks.Task]::WaitAll($tasks)
        $sw.Stop()

        $totalBytes = ($tasks | ForEach-Object { $_.Result.Length } | Measure-Object -Sum).Sum
        $seconds = [Math]::Max($sw.Elapsed.TotalSeconds, 0.001)
        $mbps = [Math]::Round((($totalBytes * 8) / $seconds) / 1000000, 2)

        [PSCustomObject]@{
            Success        = $true
            Source         = 'fast.com'
            DownloadMbps   = $mbps
            UploadMbps     = $null
            PingMs         = $null
            JitterMs       = $null
            PacketLossPct  = $null
            ISP            = $meta.client.isp
            ServerName     = ($meta.targets | Select-Object -First 1 -ExpandProperty name)
            ServerLocation = "$($meta.client.location.city), $($meta.client.location.country)"
            ErrorMessage   = ''
        }
    } catch {
        [PSCustomObject]@{
            Success = $false; Source = 'fast.com'
            DownloadMbps = $null; UploadMbps = $null; PingMs = $null; JitterMs = $null; PacketLossPct = $null
            ISP = $null; ServerName = $null; ServerLocation = $null
            ErrorMessage = $_.Exception.Message
        }
    } finally {
        if ($client) { $client.Dispose() }
    }
}

function Write-SpeedTestResult {
    param(
        [Parameter(Mandatory)][string]$DataDir,
        [Parameter(Mandatory)][PSCustomObject]$Result
    )

    if (-not (Test-Path -LiteralPath $DataDir)) {
        New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
    }

    $csvPath = Join-Path $DataDir 'speedtest_log.csv'
    $row = [PSCustomObject]@{
        Timestamp      = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        Source         = $Result.Source
        Success        = $Result.Success
        DownloadMbps   = $Result.DownloadMbps
        UploadMbps     = $Result.UploadMbps
        PingMs         = $Result.PingMs
        JitterMs       = $Result.JitterMs
        PacketLossPct  = $Result.PacketLossPct
        ISP            = $Result.ISP
        ServerName     = $Result.ServerName
        ServerLocation = $Result.ServerLocation
        ErrorMessage   = $Result.ErrorMessage
    }

    $row | Export-Csv -Path $csvPath -Append -NoTypeInformation
}
