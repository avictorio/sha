# verify/checks/p0-7-telegram.ps1 -- PLAN.md P0.7 (Telegram gateway) checks
# Run in the `operator` account, in an ELEVATED Windows PowerShell, in a visible window, after an
# unattended reboot. Reads hermes's logs as admin; `hermes gateway status` runs AS hermes via
# scripts/invoke-as-hermes.ps1 (the owner types the password). Never prints the bot token.
# Manual parts (owner, on the phone): the bot answers; a second account gets no reply.
param([string]$LogPath)
$ErrorActionPreference = 'Continue'
if ($LogPath) { Start-Transcript -Path $LogPath -Force | Out-Null }
try {
$results = [ordered]@{}
function Step($m) { Write-Host "`n== $m" -ForegroundColor Cyan }
function Record($name, $ok, $detail) {
  $results[$name] = $ok
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("[{0}] {1}  {2}" -f ($(if ($ok) {'PASS'} else {'FAIL'})), $name, $detail) -ForegroundColor $c
}
if ($env:USERNAME -ne 'operator') { throw "Not running as 'operator' (got '$env:USERNAME')." }
$p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw "Run this elevated (Run as administrator)." }
$repo = Split-Path (Split-Path $PSScriptRoot)
$home_ = 'C:\Users\hermes\AppData\Local\hermes'
$boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime

Step "Allow-list and guard"
$envLines = Get-Content "$home_\.env"
$allowed = ($envLines | Where-Object { $_ -match '^\s*TELEGRAM_ALLOWED_USERS\s*=' } | Select-Object -Last 1) -replace '^\s*TELEGRAM_ALLOWED_USERS\s*=\s*', ''
Record 'allowed-users-set' ($allowed -match '^\d{5,15}$') 'TELEGRAM_ALLOWED_USERS has one numeric ID'
Record 'token-set' ([bool]($envLines | Where-Object { $_ -match '^\s*TELEGRAM_BOT_TOKEN\s*=\s*\d{6,12}:' })) '(value not shown)'
Record 'guard-installed' ((Test-Path 'C:\agent\bin\start-gateway.ps1') -and ((Get-Content 'C:\agent\bin\start-gateway.ps1' -Raw) -match 'REFUSED')) 'C:\agent\bin\start-gateway.ps1'

Step "Logon task"
$t = Get-ScheduledTask -TaskName 'Hermes_Gateway' -ErrorAction SilentlyContinue
$trig = $t.Triggers | Where-Object { $_.CimClass.CimClassName -eq 'MSFT_TaskLogonTrigger' }
Record 'task-at-hermes-logon' ($t -and $trig -and $t.Principal.UserId -match 'hermes$' -and $t.Principal.LogonType -eq 'Interactive' -and $t.State -ne 'Disabled') "state=$($t.State) user=$($t.Principal.UserId) logon=$($t.Principal.LogonType)"

Step "Running since boot, Telegram connected"
$gw = Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'gateway run' -and $_.Name -match 'python|hermes' } |
  Where-Object { (Invoke-CimMethod -InputObject $_ -MethodName GetOwner).User -eq 'hermes' } | Sort-Object CreationDate | Select-Object -First 1
Record 'gateway-running-as-hermes' ($gw -and $gw.CreationDate -gt $boot) "boot=$boot started=$($gw.CreationDate) session=$($gw.SessionId)"
$conn = Get-Content "$home_\logs\gateway.log" -Tail 400 | Where-Object { $_ -match '^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d).*telegram connected' -and ([datetime]$Matches[1]) -gt $boot } | Select-Object -Last 1
Record 'telegram-connected-since-boot' ([bool]$conn) $(if ($conn) { $conn.Substring(0, 19) } else { 'no "telegram connected" since boot' })
$refused = Get-Content "$home_\logs\start-gateway.log" -Tail 20 | Where-Object { $_ -match 'REFUSED' }
if ($refused) { Write-Host "  note: the guard has refused before: $($refused | Select-Object -Last 1)" -ForegroundColor Yellow }

Step "hermes gateway status (as hermes)"
try {
  $r = & (Join-Path $repo 'scripts\invoke-as-hermes.ps1') -TimeoutSeconds 120 -Command @'
[Console]::OutputEncoding = [Text.Encoding]::UTF8; $env:NO_COLOR = '1'; $env:PYTHONIOENCODING = 'utf-8'
& (Join-Path $env:LOCALAPPDATA 'hermes\bin\hermes.exe') gateway status 2>&1
'@
  # v0.22.4 prints "(check mark) Gateway process running (PID: n)". It also flags our task as predating its template
  # and suggests `hermes gateway start|install` as a repair: don't. That would replace the guarded task.
  $line = $r.Output | Where-Object { $_ -match 'Gateway process running' } | Select-Object -First 1
  Record 'gateway-status-running' ([bool]$line) $(if ($line) { "$line".Trim() } else { ($r.Output -join ' | ') })
  $act = (Get-ScheduledTask -TaskName 'Hermes_Gateway' -ErrorAction SilentlyContinue).Actions | Select-Object -First 1
  Record 'task-runs-guard' ("$($act.Arguments)" -match 'start-gateway\.ps1') "action: $($act.Execute) $($act.Arguments)"
} catch { Record 'gateway-status-running' $false $_.Exception.Message }

Step "Summary"
$results.GetEnumerator() | ForEach-Object { "{0,-32} {1}" -f $_.Key, $(if ($_.Value) {'PASS'} else {'FAIL'}) }
Write-Host "`nManual (owner, phone): the bot answers you; a second Telegram account gets no reply."
} finally {
  if ($LogPath) { Stop-Transcript | Out-Null }
}
