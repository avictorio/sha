# verify/checks/p0-4-ollama.ps1 -- PLAN.md P0.4 (Ollama as a Windows service) checks
# Run in the `operator` account, in Windows PowerShell, after a reboot. Elevation not needed.
# Prints PASS/FAIL per check. Re-runnable.
$ErrorActionPreference = 'Continue'
$results = [ordered]@{}
function Step($m) { Write-Host "`n== $m" -ForegroundColor Cyan }
function Record($name, $ok, $detail) {
  $results[$name] = $ok
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("[{0}] {1}  {2}" -f ($(if ($ok) {'PASS'} else {'FAIL'})), $name, $detail) -ForegroundColor $c
}
if ($env:USERNAME -ne 'operator') { throw "Not running as 'operator' (got '$env:USERNAME')." }

$repo = Split-Path (Split-Path $PSScriptRoot)
$lock = ConvertFrom-StringData ((Get-Content (Join-Path $repo 'versions.lock') |
  Where-Object { $_ -notmatch '^\s*#' }) -join "`n")
$ollama = 'D:\ollama\bin\ollama.exe'
$log    = 'D:\ollama\logs\ollama.log'

# --- Service ---
Step "Service"
$svc = Get-Service Ollama -ErrorAction SilentlyContinue
Record 'service-running-automatic' ($svc -and $svc.Status -eq 'Running' -and $svc.StartType -eq 'Automatic') "$($svc.Status) $($svc.StartType)"
$boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
# Win32_Process, not Get-Process: StartTime of a SYSTEM process is unreadable unelevated.
$proc = Get-CimInstance Win32_Process -Filter "Name='ollama.exe'" | Sort-Object CreationDate | Select-Object -First 1
Record 'started-since-boot' ($proc -and $proc.CreationDate -gt $boot) "boot=$boot ollama started=$($proc.CreationDate)"
$tray = Get-Process 'ollama app' -ErrorAction SilentlyContinue
Record 'no-tray-app' (-not $tray) ''

# --- Version ---
$ver = (& $ollama --version 2>&1) -join ' '
Record 'version-pinned' ($ver -match [regex]::Escape($lock.ollama_version.TrimStart('v'))) $ver

# --- Localhost only ---
Step "Listening address"
$listen = netstat -ano | Select-String ':11434\s' | Where-Object { $_ -match 'LISTENING' } | ForEach-Object { ($_ -split '\s+')[2] }
$bad = $listen | Where-Object { $_ -notmatch '^127\.0\.0\.1:11434$' }
Record 'localhost-only' ($listen -and -not $bad) ($listen -join ', ')

# --- Models ---
Step "Models"
$list = (& $ollama list 2>&1) -join "`n"
foreach ($tag in ($lock.model_candidates -split ',')) {
  Record "model:$tag" ($list -match [regex]::Escape($tag)) ''
}
$blobs = Get-ChildItem 'D:\ollama\models\blobs' -ErrorAction SilentlyContinue | Measure-Object Length -Sum
Record 'models-on-D' ($blobs.Sum -gt 1GB) ("{0:N1} GB in D:\ollama\models" -f ($blobs.Sum / 1GB))

# --- GPU (not in PLAN.md's Done-when, but the benchmark is meaningless without it) ---
Step "GPU"
$since = Get-Content $log | Select-String 'Listening on' | Select-Object -Last 1
$tail  = Get-Content $log | Select-Object -Skip ($since.LineNumber - 1)
$gpuFail = $tail | Select-String 'failure during llama-server GPU discovery'
$gpuOk   = $tail | Select-String 'inference compute' | Where-Object { $_ -match 'cuda|CUDA' }
Record 'gpu-detected' ($gpuOk -and -not $gpuFail) $(if ($gpuOk) { ($gpuOk | Select-Object -Last 1).Line -replace '.*msg=','' } else { 'no CUDA "inference compute" line since last start' })
Write-Host "  $(nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>&1)"

Step "Summary"
$results.GetEnumerator() | ForEach-Object { "{0,-50} {1}" -f $_.Key, $(if ($_.Value) {'PASS'} else {'FAIL'}) }
