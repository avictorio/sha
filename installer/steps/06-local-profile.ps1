# installer/steps/06-local-profile.ps1 -- PLAN.md P1.3: the local (local-only) profile.
# Run from the `operator` account in an ELEVATED Windows PowerShell, in a visible window; the owner types
# the hermes password once per run.
#   -Phase Create  (no bot token yet) create the profile without cloning (no keys, no memory), merge
#                  config/templates/local.config.yaml (gateway.standalone first, so the default gateway
#                  never serves it), install the usage log (P1.5), pin Hermes_Gateway to -p default, and
#                  print what the Bot phase and the checks need. Re-runnable.
#   -Phase Bot     the second bot: added after Create (PLAN.md P1.3 step 4).
#   -Phase Tasks   re-copy start-gateway.ps1 and (re-)register Hermes_Gateway_local with its 45 s logon delay
#                  (P1.8 boot race). No password needed.
param([Parameter(Mandatory)][ValidateSet('Create', 'Bot', 'Tasks')][string]$Phase, [string]$LogPath)

$ErrorActionPreference = 'Stop'
if ($LogPath) { Start-Transcript -Path $LogPath -Force | Out-Null }
function Step($msg) { Write-Host "`n== $msg" -ForegroundColor Cyan }
$repo = Split-Path (Split-Path $PSScriptRoot)
$lock = ConvertFrom-StringData ((Get-Content (Join-Path $repo 'versions.lock') | Where-Object { $_ -notmatch '^\s*#' }) -join "`n")
if ($env:USERNAME -ne 'operator') { throw "Not running as 'operator' (got '$env:USERNAME'). Stop: CLAUDE.md rule 1." }
$p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw "Run this elevated (Run as administrator)." }
$hermesRoot = 'C:\Users\hermes\AppData\Local\hermes'
$localHome = "$hermesRoot\profiles\local"

function Restart-Gateway([string]$profile) { & (Join-Path $repo 'scripts\restart-gateway.ps1') -Profile $profile }
# At hermes's logon the local gateway starts 45 s after the default one: a gateway that starts while the
# other is still starting exits 75 ("second gateway on this host"; start-gateway.ps1 also retries).
function LocalTrigger([string]$user) { $t = New-ScheduledTaskTrigger -AtLogOn -User $user; $t.Delay = 'PT45S'; $t }
# The guarded logon task (re-registered with -Force, so it's safe to run again).
# RestartCount: until the default gateway's rescan confirms it no longer serves local, local's own
# gateway exits and retries (Hermes host_attach).
function Register-LocalTask {
  $hermesId = "$env:COMPUTERNAME\hermes"
  Register-ScheduledTask -TaskName 'Hermes_Gateway_local' -Force `
    -Action    (New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\agent\bin\start-gateway.ps1 -Profile local') `
    -Trigger   (LocalTrigger $hermesId) `
    -Principal (New-ScheduledTaskPrincipal -UserId $hermesId -LogonType Interactive -RunLevel Limited) `
    -Settings  (New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                  -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 5 -RestartInterval (New-TimeSpan -Minutes 1)) | Out-Null
  Enable-ScheduledTask -TaskName 'Hermes_Gateway_local' | Out-Null
}

if ($Phase -eq 'Tasks') {
  Copy-Item (Join-Path $repo 'scripts\start-gateway.ps1') 'C:\agent\bin\start-gateway.ps1' -Force
  Register-LocalTask
  $t = (Get-ScheduledTask -TaskName 'Hermes_Gateway_local').Triggers[0]
  Write-Host "Hermes_Gateway_local trigger: $($t.CimClass.CimClassName) user=$($t.UserId) delay=$($t.Delay)"
  Write-Host "start-gateway.ps1 updated: $((Get-FileHash 'C:\agent\bin\start-gateway.ps1').Hash -eq (Get-FileHash (Join-Path $repo 'scripts\start-gateway.ps1')).Hash)"
}

if ($Phase -eq 'Create') {
  $dir = Join-Path $env:PUBLIC ("hermes-local-" + [guid]::NewGuid().ToString('N'))
  try {
    Step "Stage the template; local workspace folder"
    New-Item -ItemType Directory $dir | Out-Null
    icacls $dir /inheritance:r /grant:r "hermes:(OI)(CI)RX" "SYSTEM:(OI)(CI)F" "Administrators:(OI)(CI)F" | Out-Null
    Copy-Item (Join-Path $repo 'config\templates\local.config.yaml') "$dir\template.yaml"
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
    New-Item -ItemType Directory -Force 'C:\agent\local\workspace' | Out-Null   # hermes: full control, inherited from C:\agent

    Write-Host "Type the hermes password (hidden):" -ForegroundColor Yellow
    $pw = Read-Host -AsSecureString "hermes password"

    Step "As hermes: create the profile (no clone), merge the local-only config, read it back"
    $cmd = @"
[Console]::OutputEncoding = [Text.Encoding]::UTF8; `$env:NO_COLOR = '1'; `$env:PYTHONIOENCODING = 'utf-8'; `$env:COLUMNS = '200'
`$h = Join-Path `$env:LOCALAPPDATA 'hermes\bin\hermes.exe'
function Herm { & `$h @args 2>&1 | Where-Object { "`$_" -notmatch '^System\.Management\.Automation' } }
"PDEFAULT=`$((Herm -p default config get model.default) -join '')"
`$ph = Join-Path `$env:LOCALAPPDATA 'hermes\profiles\local'
if (-not (Test-Path `$ph)) { '##### create'; Herm profile create local --no-alias; "CREATERC=`$LASTEXITCODE" } else { 'EXISTS=1' }
"PHOME=`$(Test-Path `$ph)"
`$cfg = Join-Path `$ph 'config.yaml'
if (-not (Test-Path `$cfg)) { New-Item -ItemType File `$cfg | Out-Null }
Copy-Item `$cfg "`$cfg.pre-p13-`$(Get-Date -Format yyyyMMdd-HHmmss).bak" -Force
`$py = Get-ChildItem (Join-Path `$env:LOCALAPPDATA 'hermes\installs') -Recurse -Filter python.exe -ErrorAction SilentlyContinue |
  Where-Object FullName -match '\\venv\\Scripts\\python\.exe$' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
& `$py.FullName '$dir\merge.py' `$cfg '$dir\template.yaml' 2>&1
'##### env key names (values never printed)'
`$envf = Join-Path `$ph '.env'
if (Test-Path `$envf) { (Get-Content `$envf | Where-Object { `$_ -match '^\s*[A-Z_]+\s*=\s*\S' } | ForEach-Object { (`$_ -split '=')[0].Trim() }) -join ',' } else { 'no .env' }
'##### process env names matching KEY|TOKEN|SECRET'
(Get-ChildItem Env: | Where-Object Name -match 'KEY|TOKEN|SECRET' | ForEach-Object Name) -join ','
foreach (`$a in @('config','check'), @('config','get','model'), @('config','get','gateway.standalone'), @('config','get','fallback_providers'), @('config','get','delegation.fallback_providers'), @('config','get','terminal.docker_volumes'), @('config','get','approvals.mode'), @('fallback','list'), @('auth','list'), @('config','get','memory.provider'), @('config','get','honcho'), @('tools','list'), @('tools','disable','--help')) {
  "##### `$(`$a -join ' ')"; Herm -p local @a | Select-Object -First 80
}
'##### auxiliary providers'
Herm -p local config get auxiliary | Where-Object { `$_ -match '^\S|provider:|base_url:' }
'##### profile list'
Herm profile list
"@
    $r = & (Join-Path $repo 'scripts\invoke-as-hermes.ps1') -Password $pw -Command $cmd -TimeoutSeconds 900
    $r.Output | ForEach-Object { Write-Host "  $_" }
    if ($r.TimedOut) { throw "the hermes step timed out" }
    if (-not ($r.Output -contains 'PHOME=True')) { throw "The local profile folder wasn't created; stopping." }
    if (-not ($r.Output -contains 'MERGED')) { throw "The local config merge failed; stopping." }

    Step "Pin Hermes_Gateway to the default profile"
    if (($r.Output | Where-Object { $_ -like 'PDEFAULT=*' }) -ne "PDEFAULT=$($lock.model_default)") {
      Write-Host "'hermes -p default' didn't read the default config back; Hermes_Gateway left unchanged." -ForegroundColor Red
    } else {
      Copy-Item (Join-Path $repo 'scripts\start-gateway.ps1') 'C:\agent\bin\start-gateway.ps1' -Force
      Set-ScheduledTask -TaskName 'Hermes_Gateway' -Action (New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\agent\bin\start-gateway.ps1 -Profile default') | Out-Null
      Restart-Gateway 'default'
      Write-Host "action: $((Get-ScheduledTask -TaskName 'Hermes_Gateway').Actions[0].Arguments)"
    }
  } finally {
    Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
  }

  Step "Usage log in the local profile (P1.5)"
  & (Join-Path $repo 'installer\steps\08-plugins.ps1') -Profile local -Password $pw
  Step "Done (Create). Next: -Phase Bot"
}

if ($Phase -eq 'Bot') {
  $localEnv = "$localHome\.env"; $defEnv = "$hermesRoot\.env"
  if (-not (Test-Path "$localHome\config.yaml")) { throw "No local profile; run -Phase Create first." }
  if (-not (Select-String -Path "$localHome\config.yaml" -Pattern '^\s+standalone:\s*true\b' -Quiet)) { throw "gateway.standalone isn't true in the local config; run -Phase Create again." }
  function EnvValue($path, $key) { ((Get-Content $path -ErrorAction SilentlyContinue | Where-Object { $_ -match "^\s*$key\s*=" } | Select-Object -Last 1) -replace "^\s*$key\s*=\s*", '').Trim() }
  $id = EnvValue $defEnv 'TELEGRAM_ALLOWED_USERS'
  if ($id -notmatch '^\d{5,15}$') { throw "The default profile has no single numeric TELEGRAM_ALLOWED_USERS to reuse." }

  Write-Host "Type the hermes password (hidden):" -ForegroundColor Yellow
  $pw = Read-Host -AsSecureString "hermes password"

  # Never add a token while the default (multiplexed) gateway still serves local: it would poll it too.
  Step "Is the local profile still served by the default gateway? (as hermes)"
  $r = & (Join-Path $repo 'scripts\invoke-as-hermes.ps1') -Password $pw -Command @"
[Console]::OutputEncoding = [Text.Encoding]::UTF8; `$env:NO_COLOR = '1'; `$env:PYTHONIOENCODING = 'utf-8'; `$env:COLUMNS = '200'
& (Join-Path `$env:LOCALAPPDATA 'hermes\bin\hermes.exe') profile list 2>&1 | Where-Object { "`$_" -match 'local' }
"@
  $r.Output | ForEach-Object { Write-Host "  $_" }
  $row = $r.Output | Where-Object { $_ -match '^\s*\S?\s*local\s' } | Select-Object -First 1
  if (-not $row) { throw "Couldn't read the local row of 'hermes profile list'; token NOT added." }
  if ($row -match '\brunning\b') { throw "The default gateway still serves the local profile (standalone not honoured?); token NOT added. Stop: tell the owner." }

  Step "The local bot's token from @BotFather (hidden)"
  $sec = Read-Host -AsSecureString "local bot token"
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
  try {
    $token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr).Trim()
    if ($token -notmatch '^\d{6,12}:[A-Za-z0-9_-]{30,}$') { throw "That doesn't look like a bot token (expected 123456789:AA...)." }
    if ($token -eq (EnvValue $defEnv 'TELEGRAM_BOT_TOKEN')) { throw "That's the default bot's token. Each profile needs its own bot (F1)." }
    function Set-EnvLine([string]$path, [string]$key, [string]$value) {
      $lines = [Collections.Generic.List[string]]@(if (Test-Path $path) { [IO.File]::ReadAllLines($path) })
      $i = $lines.FindIndex({ param($l) $l -match "^\s*#?\s*$key\s*=" })
      if ($i -ge 0) { $lines[$i] = "$key=$value" } else { $lines.Add("$key=$value") }
      [IO.File]::WriteAllLines($path, $lines, (New-Object Text.UTF8Encoding $false))
    }
    Step "Write TELEGRAM_* to the local .env (allowed users first; your ID reused from the default profile)"
    Set-EnvLine $localEnv 'TELEGRAM_ALLOWED_USERS' $id
    Set-EnvLine $localEnv 'TELEGRAM_HOME_CHANNEL' $id
    Set-EnvLine $localEnv 'TELEGRAM_BOT_TOKEN' $token
    Write-Host "written (token not shown)"
  } finally {
    $token = $null
    if ($bstr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
  }

  Step "Turn off cloud-facing toolsets in the local profile (cli and telegram)"
  # PLAN.md P1.3 step 5: web search/extract, image generation, cloud TTS/vision; browser too (Phase 3 is default-only).
  $r = & (Join-Path $repo 'scripts\invoke-as-hermes.ps1') -Password $pw -Command @"
[Console]::OutputEncoding = [Text.Encoding]::UTF8; `$env:NO_COLOR = '1'; `$env:PYTHONIOENCODING = 'utf-8'
`$h = Join-Path `$env:LOCALAPPDATA 'hermes\bin\hermes.exe'
foreach (`$pf in 'cli', 'telegram') { & `$h -p local tools disable --platform `$pf web browser vision image_gen tts 2>&1 | Where-Object { "`$_" -notmatch '^System\.Management\.Automation' } }
"@
  $r.Output | ForEach-Object { Write-Host "  $_" }

  Step "Hermes_Gateway_local logon task"
  Copy-Item (Join-Path $repo 'scripts\start-gateway.ps1') 'C:\agent\bin\start-gateway.ps1' -Force
  Register-LocalTask
  $start = Get-Date
  Restart-Gateway 'local'
  $deadline = $start.AddSeconds(120); $connected = $false
  while (-not $connected -and (Get-Date) -lt $deadline) {
    Start-Sleep 5
    $connected = [bool](Get-Content "$localHome\logs\gateway.log" -Tail 100 -ErrorAction SilentlyContinue | Where-Object {
      $_ -match '^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d).*telegram connected' -and ([datetime]$Matches[1]) -ge $start.AddSeconds(-1) })
  }
  if ($connected) { Write-Host "local bot: telegram connected" -ForegroundColor Green }
  else { Write-Host "local bot not connected within 120 s; see $localHome\logs\gateway.log and start-gateway.log" -ForegroundColor Red }

  Step "Check (verify/checks/p1-3-local.ps1)"
  & (Join-Path $repo 'verify\checks\p1-3-local.ps1') -Password $pw
}
if ($LogPath) { Stop-Transcript | Out-Null }
