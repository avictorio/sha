# installer/steps/05-telegram.ps1 -- PLAN.md P0.7: the Telegram gateway for the default profile.
# Run from the `operator` account in an ELEVATED Windows PowerShell, in a visible window.
# The owner types: their numeric Telegram ID, the bot token (hidden), then the hermes password.
#
# Order matters (CLAUDE.md: the gateway never starts without TELEGRAM_ALLOWED_USERS):
#   1. stop any running hermes gateway (`hermes chat` leaves a `gateway run --idle-exit` behind);
#   2. write TELEGRAM_ALLOWED_USERS and TELEGRAM_HOME_CHANNEL, then the token, into hermes's .env
#      (where `hermes config set` puts UPPER_SNAKE keys). The token goes from the hidden prompt
#      straight into the file: never on a command line, in a script file or in a log;
#   3. refuse to go on unless Hermes itself reads TELEGRAM_ALLOWED_USERS back;
#   4. register the Hermes_Gateway logon task from operator. `hermes gateway install` can't do it
#      as standard user hermes: it stops at "Open the UAC prompt now? [y/N]" (Hermes v0.22.4).
#      The task runs scripts/start-gateway.ps1 (copied to C:\agent\bin), which refuses to start the
#      gateway without TELEGRAM_ALLOWED_USERS.
# -GatewayOnly: skip the prompts and .env writes (already done); just do steps 3-4.
param([string]$LogPath, [switch]$GatewayOnly)

$ErrorActionPreference = 'Stop'
if ($LogPath) { Start-Transcript -Path $LogPath -Force | Out-Null }
function Step($msg) { Write-Host "`n== $msg" -ForegroundColor Cyan }
$repo = Split-Path (Split-Path $PSScriptRoot)

if ($env:USERNAME -ne 'operator') { throw "Not running as 'operator' (got '$env:USERNAME'). Stop: CLAUDE.md rule 1." }
$p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw "Run this elevated (Run as administrator)." }

$envFile = 'C:\Users\hermes\AppData\Local\hermes\.env'
if (-not (Test-Path $envFile)) { throw "$envFile not found (P0.6 done?)" }

if ($GatewayOnly) {
  $id = ((Get-Content $envFile | Where-Object { $_ -match '^\s*TELEGRAM_ALLOWED_USERS\s*=' } | Select-Object -Last 1) -replace '^\s*TELEGRAM_ALLOWED_USERS\s*=\s*', '').Trim()
  if ($id -notmatch '^\d{5,15}$') { throw "TELEGRAM_ALLOWED_USERS isn't set in .env; run without -GatewayOnly first." }
} else {
# --- Owner input --------------------------------------------------------------------
Step "Your Telegram numeric ID (from @userinfobot)"
$id = (Read-Host "numeric ID").Trim()
if ($id -notmatch '^\d{5,15}$') { throw "That doesn't look like a numeric Telegram ID." }

Step "Bot token from @BotFather (hidden)"
$sec = Read-Host -AsSecureString "bot token"
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
try {
  $token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr).Trim()
  if ($token -notmatch '^\d{6,12}:[A-Za-z0-9_-]{30,}$') { throw "That doesn't look like a bot token (expected 123456789:AA...)." }

  # --- 1. Stop any running gateway -----------------------------------------------------
  Step "Stop running hermes gateways"
  $gw = Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'hermes_cli\.main .*gateway run' }
  foreach ($g in $gw) {
    if ((Invoke-CimMethod -InputObject $g -MethodName GetOwner).User -ne 'hermes') { throw "A gateway runs as someone other than hermes (PID $($g.ProcessId)). Stop: tell the owner." }
    Stop-Process -Id $g.ProcessId -Force; Write-Host "stopped PID $($g.ProcessId)"
  }
  if (-not $gw) { Write-Host "none running" }

  # --- 2. .env: allowed users first, then the token --------------------------------------
  Step "Write TELEGRAM_* to hermes's .env"
  function Set-EnvLine([string]$path, [string]$key, [string]$value) {
    $lines = [Collections.Generic.List[string]]([IO.File]::ReadAllLines($path))
    $i = $lines.FindIndex({ param($l) $l -match "^\s*#?\s*$key\s*=" })
    if ($i -ge 0) { $lines[$i] = "$key=$value" } else { $lines.Add("$key=$value") }
    [IO.File]::WriteAllLines($path, $lines, (New-Object Text.UTF8Encoding $false))   # keeps the file's ACL
  }
  Set-EnvLine $envFile 'TELEGRAM_ALLOWED_USERS' $id
  Set-EnvLine $envFile 'TELEGRAM_HOME_CHANNEL' $id      # cron delivery; in a DM, chat id = user id
  Set-EnvLine $envFile 'TELEGRAM_BOT_TOKEN' $token
  Write-Host "written (token not shown)"
} finally {
  $token = $null
  if ($bstr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}
}

# --- 3. As hermes: install the Telegram extra, confirm Hermes reads the allow-list back ------
# Without the extra, the gateway installs python-telegram-bot itself at first start; that blocks
# its event loop, and its own watchdog kills it after ~2 min (exit 75) before Telegram connects.
Step "As hermes: Telegram extra, check TELEGRAM_ALLOWED_USERS"
$cmd = @"
`$h = Join-Path `$env:LOCALAPPDATA 'hermes\bin\hermes.exe'
& `$h pm install --extra telegram 2>&1 | Select-Object -Last 5
"PMRC=`$LASTEXITCODE"
`$allowed = ((& `$h config get TELEGRAM_ALLOWED_USERS 2>&1) -join '').Trim()
if (`$allowed -eq '$id') { 'ALLOWED=ok' } else { 'ALLOWED=MISMATCH' }
"@
$r = & (Join-Path $repo 'scripts\invoke-as-hermes.ps1') -Command $cmd -TimeoutSeconds 900
$r.Output | Where-Object { $_ -notmatch '\d{6,12}:[A-Za-z0-9_-]{30,}' } | ForEach-Object { Write-Host "  $_" }
if ($r.Output -notcontains 'PMRC=0') { throw "hermes pm install --extra telegram failed; the gateway was NOT started." }
if ($r.Output -notcontains 'ALLOWED=ok') { throw "Hermes doesn't read TELEGRAM_ALLOWED_USERS back as $id; the gateway was NOT installed." }
Write-Host "ALLOWED=ok"

# --- 4. The Hermes_Gateway logon task (registered by operator; runs as hermes, no stored password) ---
Step "Hermes_Gateway logon task"
New-Item -ItemType Directory -Force 'C:\agent\bin' | Out-Null
Copy-Item (Join-Path $repo 'scripts\start-gateway.ps1') 'C:\agent\bin\start-gateway.ps1' -Force
$hermesId = "$env:COMPUTERNAME\hermes"
Register-ScheduledTask -TaskName 'Hermes_Gateway' -Force `
  -Action    (New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\agent\bin\start-gateway.ps1') `
  -Trigger   (New-ScheduledTaskTrigger -AtLogOn -User $hermesId) `
  -Principal (New-ScheduledTaskPrincipal -UserId $hermesId -LogonType Interactive -RunLevel Limited) `
  -Settings  (New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)) | Out-Null
Enable-ScheduledTask -TaskName 'Hermes_Gateway' | Out-Null
Write-Host "registered Hermes_Gateway (at hermes logon, in hermes's session)"

# Start it now if hermes is signed in (it is after auto-logon); otherwise it starts at next logon.
$hermesSignedIn = [bool](Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" |
  Where-Object { (Invoke-CimMethod -InputObject $_ -MethodName GetOwner).User -eq 'hermes' })
if ($hermesSignedIn) {
  # Clean restart: Start-ScheduledTask is a no-op on a running task, and Stop-ScheduledTask can leave
  # hermes.exe/python behind, so a gateway started before the Telegram extra keeps running without it.
  Stop-ScheduledTask -TaskName 'Hermes_Gateway' -ErrorAction SilentlyContinue
  Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'gateway run|start-gateway\.ps1' } |
    Where-Object { (Invoke-CimMethod -InputObject $_ -MethodName GetOwner).User -eq 'hermes' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  Start-Sleep 3
  $start = Get-Date
  Start-ScheduledTask -TaskName 'Hermes_Gateway'
  $deadline = $start.AddSeconds(90); $connected = $false
  while (-not $connected -and (Get-Date) -lt $deadline) {
    Start-Sleep 5
    $connected = [bool](Get-Content 'C:\Users\hermes\AppData\Local\hermes\logs\gateway.log' -Tail 100 | Where-Object {
      $_ -match '^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d).*telegram connected' -and ([datetime]$Matches[1]) -ge $start.AddSeconds(-1) })
  }
  if ($connected) { Write-Host "telegram connected" -ForegroundColor Green }
  else { Write-Host "telegram not connected within 90 s; see C:\Users\hermes\AppData\Local\hermes\logs\gateway.log" -ForegroundColor Red }
} else { Write-Host "hermes isn't signed in; the gateway starts at its next logon" }

Step "Done"
if ($LogPath) { Stop-Transcript | Out-Null }
