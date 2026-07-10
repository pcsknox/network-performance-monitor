# Network Performance Monitor

Lightweight internet-speed monitoring tool for deployment on a client machine.
Pure PowerShell — no runtime to install beyond the official Ookla Speedtest CLI
(a single `.exe`, no installer). Runs on a schedule, logs every result to CSV,
and keeps a self-contained HTML trend report up to date.

## How it works

- **Primary test:** [Ookla Speedtest CLI](https://www.speedtest.net/apps/cli) — same
  engine as speedtest.net. Gives download, upload, ping, and jitter.
- **Fallback test:** fast.com (Netflix) — used only if the Ookla CLI is missing or
  a run fails (e.g. blocked by firewall). Download speed only.
- Every run appends one row to `data\speedtest_log.csv` and regenerates
  `data\report.html`.

## Folder layout

```
NetworkPerformance Monitoring\
  README.md
  config\settings.json          <- interval, fallback toggle, paths
  bin\speedtest.exe              <- Ookla CLI (fetched by Install-Prerequisites.ps1)
  scripts\
    Common.ps1                   <- shared functions (not run directly)
    Run-SpeedTest.ps1            <- runs one test cycle + logs + refreshes report
    New-Report.ps1                <- rebuilds data\report.html from the CSV
    Install-Prerequisites.ps1    <- downloads the Ookla CLI into bin\
    Install-ScheduledTask.ps1    <- registers the recurring scheduled task
    Uninstall-ScheduledTask.ps1  <- removes the scheduled task
  data\
    speedtest_log.csv            <- created on first run
    report.html                  <- created on first run, refreshed every run
```

## Setup on a client machine

1. Copy this whole folder to the target machine, e.g. `C:\NetworkPerformance Monitoring`.
2. Open an **elevated** PowerShell prompt (Run as Administrator) in that folder.
3. Fetch the Ookla CLI:
   ```powershell
   .\scripts\Install-Prerequisites.ps1
   ```
   If the download URL is stale, grab the "Windows 64-bit" CLI zip manually from
   https://www.speedtest.net/apps/cli and extract `speedtest.exe` into `bin\`.
4. Do one manual test run to confirm everything works:
   ```powershell
   .\scripts\Run-SpeedTest.ps1
   ```
   You should see a result line printed, a new row in `data\speedtest_log.csv`,
   and `data\report.html` created.
5. Install the recurring scheduled task (default: every 30 minutes, runs as SYSTEM
   so it works even when no one is logged in):
   ```powershell
   .\scripts\Install-ScheduledTask.ps1
   ```
   Override the interval or task name if needed:
   ```powershell
   .\scripts\Install-ScheduledTask.ps1 -IntervalMinutes 15 -TaskName "NPM-ClientSite"
   ```

## Remote deployment via ScreenConnect Backstage

For pushing this out to a client machine over ScreenConnect instead of copying files
by hand: open a **Backstage** session (or the Command toolbox) and paste a single
command. ScreenConnect's service normally runs as `NT AUTHORITY\SYSTEM`, so this
needs no separate elevation step:

```powershell
powershell -ExecutionPolicy Bypass -Command "iex (irm https://raw.githubusercontent.com/pcsknox/network-performance-monitor/master/scripts/Bootstrap-Remote.ps1)"
```

That one command downloads the repo, installs it to `C:\ProgramData\PCS\NetworkPerformanceMonitor`,
fetches the Ookla CLI, runs one verification test, and registers the scheduled task
— no manual steps on the remote end. To use a non-default interval:

```powershell
powershell -ExecutionPolicy Bypass -Command "& ([scriptblock]::Create((irm https://raw.githubusercontent.com/pcsknox/network-performance-monitor/master/scripts/Bootstrap-Remote.ps1))) -IntervalMinutes 15"
```

Re-running the same command later (e.g. to push out an update) detects the existing
install, refreshes `scripts\` and `config\`, and leaves `data\speedtest_log.csv` and
`bin\speedtest.exe` untouched.

## Viewing results

- Open `data\report.html` in any browser — no server, no internet needed to view it.
  It shows average/min/max for download, upload, and ping over all-time, last 24h,
  and last 7 days, a trend chart, and the 25 most recent test rows.
- Or open `data\speedtest_log.csv` directly in Excel for raw data / pivot tables.

## Configuration

Edit `config\settings.json`:

| Key | Meaning |
|---|---|
| `IntervalMinutes` | Default interval used by `Install-ScheduledTask.ps1` |
| `EnableFastComFallback` | Set `false` to disable the fast.com fallback entirely |
| `OoklaExeRelativePath` | Where to find `speedtest.exe`, relative to the tool root |
| `DataDirRelativePath` | Where the CSV log and report are written |
| `TaskName` | Name used for the Windows Scheduled Task |
| `TimeoutSeconds` | Max time to wait for a single test before giving up |

## Uninstalling

```powershell
.\scripts\Uninstall-ScheduledTask.ps1
```
Then delete the folder. Nothing else is installed on the machine — no services,
no registry changes beyond the one scheduled task.

## Notes

- The scheduled task runs as `NT AUTHORITY\SYSTEM` so it fires on schedule even if
  no user is logged on. It does not need network credentials or a stored password.
- Each run is capped at a 10-minute execution time limit so a hung test can't pile up.
- `data\speedtest_log.csv` grows by one row per run indefinitely (roughly 200 bytes/row,
  so ~48 rows/day at the default 30-minute interval is under a few hundred KB/year) —
  archive or trim it periodically if you want to keep it small on very long deployments.
