# scripts/migrate-private-to-local.ps1 -- PLAN.md P1.10: the one-time rename private -> local (D3), on a
# machine set up before P1.10. New installs get `local` from installer/steps/06-local-profile.ps1.
# Run from the `operator` account in an ELEVATED Windows PowerShell; the owner types the hermes password once.
#   1. preflight; a fresh backup (Agent_Backup) before anything changes;
#   2. stop both gateways; remove Hermes_Gateway_private;
#   3. as hermes: `hermes profile rename private local`, `hermes profile rename default cloud` (display
#      name only, S15), re-merge config/templates/local.config.yaml (the new workspace mount), remove
#      sandbox containers that still mount C:\agent\private, list the profiles;
#   4. C:\agent\private -> C:\agent\local; usage-private.jsonl -> usage-local.jsonl;
#   5. copy backup.ps1 to C:\agent\bin; 06-local-profile.ps1 -Phase Tasks (Hermes_Gateway_local); start both gateways;
#   6. checks: 10-cron.ps1 (pings, then p1-8), p1-3-local, p1-5 -Profile local, a backup and p1-7.
# Stops at the first failure. Steps 2-5 skip what's already done, so it can be run again.
param([string]$LogPath)

$ErrorActionPreference = 'Stop'
if ($LogPath) { Start-Transcript -Path $LogPath -Force | Out-Null }
function Step($msg) { Write-Host "`n== $msg" -ForegroundColor Cyan }
$repo = Split-Path $PSScriptRoot
if ($env:USERNAME -ne 'operator') { throw "Not running as 'operator' (got '$env:USERNAME'). Stop: CLAUDE.md rule 1." }
$p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw "Run this elevated (Run as administrator)." }
$profiles = 'C:\Users\hermes\AppData\Local\hermes\profiles'
$logs = 'C:\agent\shared\logs'

function Backup-Now {
  $before = Get-ChildItem 'D:\backups\hermes-*.7z' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1
  Start-ScheduledTask -TaskName 'Agent_Backup'
  $deadline = (Get-Date).AddMinutes(15)
  do {
    Start-Sleep -Seconds 10
    $a = Get-ChildItem 'D:\backups\hermes-*.7z' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1
    $done = $a -and (-not $before -or $a.FullName -ne $before.FullName) -and (Get-ScheduledTask -TaskName 'Agent_Backup').State -ne 'Running'
  } until ($done -or (Get-Date) -gt $deadline)
  if (-not $done) { throw "No new backup in D:\backups after 15 minutes; nothing changed yet." }
  Write-Host ("backup: {0} ({1:N1} MB)" -f $a.Name, ($a.Length / 1MB))
}

Step "Preflight"
$hasPrivate = Test-Path "$profiles\private"
$hasLocal = Test-Path "$profiles\local"
Write-Host "profiles\private: $hasPrivate  profiles\local: $hasLocal"
if ($hasPrivate -and $hasLocal) { throw "Both profiles\private and profiles\local exist; sort that out by hand first." }
if (-not $hasPrivate -and -not $hasLocal) { throw "Neither profiles\private nor profiles\local exists." }

Write-Host "Type the hermes password (hidden):" -ForegroundColor Yellow
$pw = Read-Host -AsSecureString "hermes password"

Step "Backup before the change"
Backup-Now

Step "Stop both gateways; remove Hermes_Gateway_private"
foreach ($pr in 'private', 'local', 'default') { & (Join-Path $repo 'scripts\restart-gateway.ps1') -Profile $pr -StopOnly }
if (Get-ScheduledTask -TaskName 'Hermes_Gateway_private' -ErrorAction SilentlyContinue) {
  Disable-ScheduledTask -TaskName 'Hermes_Gateway_private' | Out-Null
  Unregister-ScheduledTask -TaskName 'Hermes_Gateway_private' -Confirm:$false
  Write-Host "Hermes_Gateway_private removed"
}

Step "As hermes: rename the profiles, re-merge the local config, remove stale sandboxes"
$dir = Join-Path $env:PUBLIC ("hermes-p110-" + [guid]::NewGuid().ToString('N'))
try {
  New-Item -ItemType Directory $dir | Out-Null
  icacls $dir /inheritance:r /grant:r "hermes:(OI)(CI)RX" "SYSTEM:(OI)(CI)F" "Administrators:(OI)(CI)F" | Out-Null
  Copy-Item (Join-Path $repo 'config\templates\local.config.yaml') "$dir\template.yaml"
  # Same merge as 06-local-profile.ps1 -Phase Create: lists (docker_volumes) are replaced, not appended.
  Set-Content "$dir\merge.py" -Encoding UTF8 -Value @'
import sys
from ruamel.yaml import YAML
y = YAML(); y.preserve_quotes = True
cfg_path, tpl_path = sys.argv[1], sys.argv[2]
with open(cfg_path, encoding="utf-8") as f: cfg = y.load(f) or {}
with open(tpl_path, encoding="utf-8") as f: tpl = y.load(f)
def merge(dst, src):
    for k, v in src.items():
        if isinstance(v, dict) and isinstance(dst.get(k), dict): merge(dst[k], v)
        else: dst[k] = v
merge(cfg, tpl)
with open(cfg_path, "w", encoding="utf-8") as f: y.dump(cfg, f)
print("MERGED")
'@
  $r = & (Join-Path $repo 'scripts\invoke-as-hermes.ps1') -Password $pw -TimeoutSeconds 900 -Command @"
[Console]::OutputEncoding = [Text.Encoding]::UTF8; `$env:NO_COLOR = '1'; `$env:PYTHONIOENCODING = 'utf-8'; `$env:COLUMNS = '200'
`$h = Join-Path `$env:LOCALAPPDATA 'hermes\bin\hermes.exe'
function Cap([string]`$argline, [int]`$sec = 120) {
  `$o = [IO.Path]::GetTempFileName(); `$e = [IO.Path]::GetTempFileName(); `$i = [IO.Path]::GetTempFileName()
  `$pr = Start-Process `$h -ArgumentList `$argline -NoNewWindow -PassThru -RedirectStandardOutput `$o -RedirectStandardError `$e -RedirectStandardInput `$i
  if (-not `$pr.WaitForExit(`$sec * 1000)) { taskkill /PID `$pr.Id /T /F 2>&1 | Out-Null; "TIMEOUT after `${sec}s: hermes `$argline" }
  Get-Content `$o, `$e -Encoding UTF8
  "RC=`$(`$pr.ExitCode)"
  Remove-Item `$o, `$e, `$i -Force -ErrorAction SilentlyContinue
}
`$profiles = Join-Path `$env:LOCALAPPDATA 'hermes\profiles'
'##### profile rename --help'; `$help = @(Cap 'profile rename --help'); `$help
`$yes = if ((`$help -join ' ') -match '--yes\b') { ' --yes' } else { '' }
if (Test-Path (Join-Path `$profiles 'private')) { '##### rename private local'; Cap "profile rename private local`$yes" } else { 'ALREADY-RENAMED' }
'##### rename default cloud'; Cap "profile rename default cloud`$yes"
"LOCALHOME=`$(Test-Path (Join-Path `$profiles 'local'))"
`$cfg = Join-Path `$profiles 'local\config.yaml'
Copy-Item `$cfg "`$cfg.pre-p110-`$(Get-Date -Format yyyyMMdd-HHmmss).bak" -Force
`$py = Get-ChildItem (Join-Path `$env:LOCALAPPDATA 'hermes\installs') -Recurse -Filter python.exe -ErrorAction SilentlyContinue |
  Where-Object FullName -match '\\venv\\Scripts\\python\.exe$' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
& `$py.FullName '$dir\merge.py' `$cfg '$dir\template.yaml' 2>&1
'##### sandboxes that mount C:\agent\private'
foreach (`$id in @(docker ps -aq 2>`$null)) {
  `$src = (docker inspect -f '{{range .Mounts}}{{.Source}} {{end}}' `$id 2>`$null) -join ' '
  if (`$src -match 'agent[\\/]private') { docker rm -f `$id 2>&1 | Out-Null; "removed container `$id" }
}
'##### config get terminal.docker_volumes'; Cap '-p local config get terminal.docker_volumes'
'##### profile list'; Cap 'profile list'
"@
  $r.Output | ForEach-Object { Write-Host "  $_" }
  if ($r.TimedOut) { throw "the hermes step timed out" }
  if (-not ($r.Output -contains 'LOCALHOME=True')) { throw "profiles\local doesn't exist after the rename; stopping (gateways are stopped; see the output above)." }
  if (-not ($r.Output -contains 'MERGED')) { throw "The local config merge failed; stopping." }
} finally {
  Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
}

Step "Folders and the usage log"
if (Test-Path 'C:\agent\private') {
  if (Test-Path 'C:\agent\local') { throw "Both C:\agent\private and C:\agent\local exist; sort that out by hand." }
  Move-Item 'C:\agent\private' 'C:\agent\local'
}
if (Test-Path "$logs\usage-private.jsonl") {
  if (Test-Path "$logs\usage-local.jsonl") {
    Get-Content "$logs\usage-local.jsonl" -Encoding UTF8 | Add-Content "$logs\usage-private.jsonl" -Encoding UTF8
    Remove-Item "$logs\usage-local.jsonl"
  }
  Rename-Item "$logs\usage-private.jsonl" 'usage-local.jsonl'
}
Write-Host "C:\agent\local: $(Test-Path 'C:\agent\local')  C:\agent\private: $(Test-Path 'C:\agent\private')  usage-local.jsonl: $(Test-Path "$logs\usage-local.jsonl")"

Step "Scripts in C:\agent\bin; Hermes_Gateway_local; start both gateways"
Copy-Item (Join-Path $repo 'scripts\backup.ps1') 'C:\agent\bin\backup.ps1' -Force
& (Join-Path $repo 'installer\steps\06-local-profile.ps1') -Phase Tasks
& (Join-Path $repo 'scripts\restart-gateway.ps1') -Profile default
Start-Sleep -Seconds 45   # the same gap as the logon trigger (P1.8 boot race)
$start = Get-Date
& (Join-Path $repo 'scripts\restart-gateway.ps1') -Profile local
$gl = "$profiles\local\logs\gateway.log"
do {
  Start-Sleep -Seconds 5
  $ok = [bool](Get-Content $gl -Tail 100 -ErrorAction SilentlyContinue | Where-Object {
    $_ -match '^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d).*telegram connected' -and ([datetime]$Matches[1]) -ge $start.AddSeconds(-1) })
} until ($ok -or (Get-Date) -gt $start.AddSeconds(120))
Write-Host "local gateway: $(if ($ok) { 'telegram connected' } else { 'no telegram connected line within 120 s; see ' + $gl })"

Step "Checks"
& (Join-Path $repo 'installer\steps\10-cron.ps1') -Password $pw
& (Join-Path $repo 'verify\checks\p1-3-local.ps1') -Password $pw
& (Join-Path $repo 'verify\checks\p1-5-usage-log.ps1') -Password $pw -Profile local
$bad = Select-String -Path "$logs\usage-local.jsonl" -Pattern '"local": false' -SimpleMatch -ErrorAction SilentlyContinue
Write-Host ("[{0}] usage-local-only  {1} line(s) with ""local"": false" -f $(if ($bad) {'FAIL'} else {'PASS'}), @($bad).Count)
Backup-Now
& (Join-Path $repo 'verify\checks\p1-7-backup.ps1')
Step "Done. Next (owner): /setname the bots in BotFather ('Hermes Cloud', 'Hermes Local') and message each."
if ($LogPath) { Stop-Transcript | Out-Null }
