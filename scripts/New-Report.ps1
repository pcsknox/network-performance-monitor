<#
    Regenerates data\report.html from data\speedtest_log.csv.
    Self-contained (no external JS/CSS), so it opens fine from a local file:// path
    on a machine with no internet access at viewing time.
#>

. (Join-Path $PSScriptRoot 'Common.ps1')

$cfg = Get-Config
$csvPath = Join-Path $cfg.DataDir 'speedtest_log.csv'
$outPath = Join-Path $cfg.DataDir 'report.html'

if (-not (Test-Path -LiteralPath $csvPath)) {
    Write-Warning "No log file found yet at $csvPath - run Run-SpeedTest.ps1 first."
    return
}

$allRows = @(Import-Csv -Path $csvPath)
$okRows = @($allRows | Where-Object { $_.Success -eq 'True' -and $_.DownloadMbps })

function Get-Stats {
    param($rows)
    $rows = @($rows)
    $d = $rows | ForEach-Object { [double]$_.DownloadMbps }
    $u = $rows | ForEach-Object { $_.UploadMbps } | Where-Object { $_ } | ForEach-Object { [double]$_ }
    $p = $rows | ForEach-Object { $_.PingMs } | Where-Object { $_ } | ForEach-Object { [double]$_ }

    function Stat($vals) {
        if (-not $vals -or $vals.Count -eq 0) { return [PSCustomObject]@{ Avg = 0; Min = 0; Max = 0 } }
        [PSCustomObject]@{
            Avg = [Math]::Round(($vals | Measure-Object -Average).Average, 1)
            Min = [Math]::Round(($vals | Measure-Object -Minimum).Minimum, 1)
            Max = [Math]::Round(($vals | Measure-Object -Maximum).Maximum, 1)
        }
    }

    [PSCustomObject]@{
        Count    = $rows.Count
        Download = Stat $d
        Upload   = Stat $u
        Ping     = Stat $p
    }
}

$now = Get-Date
$last24h = @($okRows | Where-Object { [datetime]$_.Timestamp -ge $now.AddHours(-24) })
$last7d  = @($okRows | Where-Object { [datetime]$_.Timestamp -ge $now.AddDays(-7) })

$statsAll   = Get-Stats $okRows
$stats24h   = Get-Stats $last24h
$stats7d    = Get-Stats $last7d

$failCount = @($allRows | Where-Object { $_.Success -ne 'True' }).Count

$chartPoints = @($okRows | Select-Object -Last 500 | ForEach-Object {
    [PSCustomObject]@{
        t   = $_.Timestamp
        dl  = [double]$_.DownloadMbps
        ul  = if ($_.UploadMbps) { [double]$_.UploadMbps } else { $null }
        png = if ($_.PingMs) { [double]$_.PingMs } else { $null }
        src = $_.Source
    }
})
# ConvertTo-Json collapses a single-element pipeline into a bare object instead of
# a one-item array, which would break the JS `data.forEach`/`data.map` calls below -
# so build the array literal manually to keep the shape stable regardless of count.
$chartJson = '[' + (($chartPoints | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 3 }) -join ',') + ']'

$recentRows = @($allRows | Select-Object -Last 25 | Sort-Object { [datetime]$_.Timestamp } -Descending)
$tableRowsHtml = ($recentRows | ForEach-Object {
    $statusClass = if ($_.Success -eq 'True') { 'ok' } else { 'fail' }
    $statusText  = if ($_.Success -eq 'True') { 'OK' } else { 'FAIL' }
    $dl = if ($_.DownloadMbps) { $_.DownloadMbps } else { '-' }
    $ul = if ($_.UploadMbps) { $_.UploadMbps } else { '-' }
    $pg = if ($_.PingMs) { $_.PingMs } else { '-' }
    $err = if ($_.ErrorMessage) { $_.ErrorMessage -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' } else { '' }
    "<tr class='$statusClass'><td>$($_.Timestamp)</td><td>$($_.Source)</td><td>$statusText</td><td>$dl</td><td>$ul</td><td>$pg</td><td class='err'>$err</td></tr>"
}) -join "`n"

$generatedAt = $now.ToString('yyyy-MM-dd HH:mm:ss')

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Network Performance Report</title>
<style>
  :root { color-scheme: light dark; }
  body { font-family: Segoe UI, Arial, sans-serif; margin: 0; padding: 24px; background: #f5f6f8; color: #1a1a1a; }
  h1 { font-size: 1.4rem; margin-bottom: 4px; }
  .sub { color: #666; margin-bottom: 24px; font-size: 0.9rem; }
  .cards { display: flex; gap: 16px; flex-wrap: wrap; margin-bottom: 24px; }
  .card { background: #fff; border-radius: 8px; padding: 16px 20px; box-shadow: 0 1px 3px rgba(0,0,0,0.12); min-width: 180px; }
  .card h2 { font-size: 0.85rem; text-transform: uppercase; letter-spacing: 0.03em; color: #666; margin: 0 0 8px; }
  .card .row { display: flex; justify-content: space-between; font-size: 0.9rem; padding: 2px 0; }
  .card .row b { font-weight: 600; }
  canvas { background: #fff; border-radius: 8px; box-shadow: 0 1px 3px rgba(0,0,0,0.12); width: 100%; max-width: 100%; height: 320px; margin-bottom: 24px; }
  table { width: 100%; border-collapse: collapse; background: #fff; border-radius: 8px; overflow: hidden; box-shadow: 0 1px 3px rgba(0,0,0,0.12); }
  th, td { text-align: left; padding: 8px 12px; font-size: 0.85rem; border-bottom: 1px solid #eee; }
  th { background: #fafafa; }
  tr.fail td { color: #b00020; }
  td.err { max-width: 320px; overflow: hidden; text-overflow: ellipsis; }
  .legend { display: flex; gap: 16px; font-size: 0.85rem; margin: -12px 0 12px; color: #555; }
  .legend span { display: inline-flex; align-items: center; gap: 6px; }
  .swatch { width: 10px; height: 10px; border-radius: 2px; display: inline-block; }
</style>
</head>
<body>
  <h1>Network Performance Report</h1>
  <div class="sub">Generated $generatedAt &middot; $($allRows.Count) total tests &middot; $failCount failed</div>

  <div class="cards">
    <div class="card"><h2>All Time</h2>
      <div class="row"><span>Download</span><b>$($statsAll.Download.Avg) Mbps</b></div>
      <div class="row"><span>Upload</span><b>$($statsAll.Upload.Avg) Mbps</b></div>
      <div class="row"><span>Ping</span><b>$($statsAll.Ping.Avg) ms</b></div>
    </div>
    <div class="card"><h2>Last 24 Hours ($($stats24h.Count))</h2>
      <div class="row"><span>Download</span><b>$($stats24h.Download.Avg) Mbps</b></div>
      <div class="row"><span>Upload</span><b>$($stats24h.Upload.Avg) Mbps</b></div>
      <div class="row"><span>Ping</span><b>$($stats24h.Ping.Avg) ms</b></div>
    </div>
    <div class="card"><h2>Last 7 Days ($($stats7d.Count))</h2>
      <div class="row"><span>Download</span><b>$($stats7d.Download.Avg) Mbps</b></div>
      <div class="row"><span>Upload</span><b>$($stats7d.Upload.Avg) Mbps</b></div>
      <div class="row"><span>Ping</span><b>$($stats7d.Ping.Avg) ms</b></div>
    </div>
  </div>

  <div class="legend">
    <span><i class="swatch" style="background:#2563eb"></i>Download (Mbps)</span>
    <span><i class="swatch" style="background:#16a34a"></i>Upload (Mbps)</span>
    <span><i class="swatch" style="background:#ea580c"></i>Ping (ms, right axis)</span>
  </div>
  <canvas id="chart"></canvas>

  <table>
    <thead><tr><th>Timestamp</th><th>Source</th><th>Status</th><th>Down (Mbps)</th><th>Up (Mbps)</th><th>Ping (ms)</th><th>Error</th></tr></thead>
    <tbody>
$tableRowsHtml
    </tbody>
  </table>

<script>
const data = $chartJson;

function draw() {
  const canvas = document.getElementById('chart');
  const dpr = window.devicePixelRatio || 1;
  const cssW = canvas.clientWidth || 800;
  const cssH = 320;
  canvas.width = cssW * dpr;
  canvas.height = cssH * dpr;
  const ctx = canvas.getContext('2d');
  ctx.scale(dpr, dpr);
  ctx.clearRect(0, 0, cssW, cssH);

  if (!data.length) {
    ctx.fillStyle = '#888';
    ctx.fillText('No successful test results yet.', 16, 24);
    return;
  }

  const padL = 50, padR = 50, padT = 16, padB = 28;
  const w = cssW - padL - padR, h = cssH - padT - padB;

  const dlVals = data.map(p => p.dl);
  const ulVals = data.filter(p => p.ul !== null).map(p => p.ul);
  const pingVals = data.filter(p => p.png !== null).map(p => p.png);

  const maxLeft = Math.max(1, ...dlVals, ...ulVals) * 1.1;
  const maxRight = Math.max(1, ...pingVals) * 1.2;

  const x = i => padL + (data.length === 1 ? w / 2 : (i / (data.length - 1)) * w);
  const yLeft = v => padT + h - (v / maxLeft) * h;
  const yRight = v => padT + h - (v / maxRight) * h;

  // axes
  ctx.strokeStyle = '#ddd';
  ctx.beginPath();
  ctx.moveTo(padL, padT); ctx.lineTo(padL, padT + h); ctx.lineTo(padL + w, padT + h);
  ctx.stroke();

  ctx.fillStyle = '#888';
  ctx.font = '11px Segoe UI, Arial, sans-serif';
  ctx.fillText(maxLeft.toFixed(0) + ' Mbps', 4, padT + 8);
  ctx.fillText('0', 4, padT + h);
  ctx.textAlign = 'right';
  ctx.fillText(maxRight.toFixed(0) + ' ms', cssW - 4, padT + 8);
  ctx.fillText('0', cssW - 4, padT + h);
  ctx.textAlign = 'left';
  ctx.fillText(data[0].t, padL, cssH - 6);
  ctx.textAlign = 'right';
  ctx.fillText(data[data.length - 1].t, cssW - padR, cssH - 6);
  ctx.textAlign = 'left';

  function line(getVal, color, axis) {
    ctx.beginPath();
    let started = false;
    data.forEach((p, i) => {
      const v = getVal(p);
      if (v === null || v === undefined) { started = false; return; }
      const px = x(i), py = axis === 'left' ? yLeft(v) : yRight(v);
      if (!started) { ctx.moveTo(px, py); started = true; } else { ctx.lineTo(px, py); }
    });
    ctx.strokeStyle = color;
    ctx.lineWidth = 1.5;
    ctx.stroke();
  }

  line(p => p.dl, '#2563eb', 'left');
  line(p => p.ul, '#16a34a', 'left');
  line(p => p.png, '#ea580c', 'right');
}

draw();
window.addEventListener('resize', draw);
</script>
</body>
</html>
"@

Set-Content -Path $outPath -Value $html -Encoding UTF8
Write-Host "Report written to $outPath"
