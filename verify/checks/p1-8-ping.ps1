# verify/checks/p1-8-ping.ps1 -- PLAN.md P1.8: each profile's ping ran, on the local model, logged per profile.
# Run in the `operator` account, ELEVATED (reads the usage logs). -Since: only calls at or after this time count.
#   Right after installer/steps/10-cron.ps1 (it passes its start time): the "run now" pings.
#   The day after an unattended reboot: -Since '<that day> 11:59' checks the 12:00 pings fired by themselves.
# Prints PASS/FAIL per check, plus the last boot time (for the reboot half of the Done when).
param([datetime]$Since = (Get-Date).Date, [string]$LogPath)
$ErrorActionPreference = 'Continue'
if ($LogPath) { Start-Transcript -Path $LogPath -Force | Out-Null }
try {
$results = [ordered]@{}
function Record($name, $ok, $detail) {
  $results[$name] = $ok
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("[{0}] {1}  {2}" -f ($(if ($ok) {'PASS'} else {'FAIL'})), $name, $detail) -ForegroundColor $c
}
$repo = Split-Path (Split-Path $PSScriptRoot)
$lock = ConvertFrom-StringData ((Get-Content (Join-Path $repo 'versions.lock') | Where-Object { $_ -notmatch '^\s*#' }) -join "`n")
Write-Host "since $Since; last boot $((Get-CimInstance Win32_OperatingSystem).LastBootUpTime)"
foreach ($k in 'default', 'local') {
  $f = "C:\agent\shared\logs\usage-$k.jsonl"
  $cron = @(Get-Content $f -Encoding UTF8 -ErrorAction SilentlyContinue | ForEach-Object { try { $_ | ConvertFrom-Json } catch { } } |
    Where-Object { $_.event -eq 'call' -and $_.platform -eq 'cron' -and [datetime]$_.ts -ge $Since })
  $last = $cron | Select-Object -Last 1
  Record "$k-ping-ran" ($cron.Count -ge 1) "$($cron.Count) cron call(s); last $($last.ts) profile=$($last.profile)"
  Record "$k-ping-local" ($cron.Count -ge 1 -and -not ($cron | Where-Object { $_.local -ne $true -or $_.model -ne $lock.model_default })) "model=$($last.model) base_url=$($last.base_url)"
}
"`n"; $results.GetEnumerator() | ForEach-Object { "{0,-24} {1}" -f $_.Key, $(if ($_.Value) {'PASS'} else {'FAIL'}) }
} finally {
  if ($LogPath) { Stop-Transcript | Out-Null }
}
