# installer/steps/04-hermes.ps1 -- PLAN.md P0.6: install Hermes Agent AS `hermes` (stable channel).
# Run from the `operator` account in an ELEVATED Windows PowerShell, in a visible window:
# the owner types the hermes password at the hidden prompt (scripts/invoke-as-hermes.ps1).
#
# The upstream install.ps1 is downloaded here, checked against the SHA-256 pinned in versions.lock
# (the copy that was read and reviewed), and only then run as hermes. If upstream changes, this
# stops: review the new script, then update hermes_install_ps1_sha256.
#
# -Configure: instead of installing, apply config/templates/default.config.yaml (deep merge with
# Hermes's own Python + ruamel.yaml, so comments and other keys survive), pull the sandbox image,
# and run the S1 Docker-backend probe. Also as hermes, behind the same password prompt.
param([string]$LogPath, [switch]$Configure)

$ErrorActionPreference = 'Stop'
if ($LogPath) { Start-Transcript -Path $LogPath -Force | Out-Null }
function Step($msg) { Write-Host "`n== $msg" -ForegroundColor Cyan }

$repo = Split-Path (Split-Path $PSScriptRoot)
$lock = ConvertFrom-StringData ((Get-Content (Join-Path $repo 'versions.lock') |
  Where-Object { $_ -notmatch '^\s*#' }) -join "`n")

if ($env:USERNAME -ne 'operator') { throw "Not running as 'operator' (got '$env:USERNAME'). Stop: CLAUDE.md rule 1." }
$p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw "Run this elevated (Run as administrator)." }

if ($Configure) {
  # --- Template + merge script into a folder hermes can read but not change ------
  $dir = Join-Path $env:PUBLIC ("hermes-config-" + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory $dir | Out-Null
  icacls $dir /inheritance:r /grant:r "hermes:(OI)(CI)RX" "SYSTEM:(OI)(CI)F" "Administrators:(OI)(CI)F" | Out-Null
  try {
    Copy-Item (Join-Path $repo 'config\templates\default.config.yaml') "$dir\template.yaml"
    Set-Content "$dir\merge.py" -Encoding UTF8 -Value @'
import sys
from ruamel.yaml import YAML
y = YAML(); y.preserve_quotes = True
cfg_path, tpl_path = sys.argv[1], sys.argv[2]
with open(cfg_path, encoding="utf-8") as f: cfg = y.load(f)
with open(tpl_path, encoding="utf-8") as f: tpl = y.load(f)
def merge(dst, src):
    for k, v in src.items():
        if isinstance(v, dict) and isinstance(dst.get(k), dict): merge(dst[k], v)
        else: dst[k] = v
merge(cfg, tpl)
with open(cfg_path, "w", encoding="utf-8") as f: y.dump(cfg, f)
print("MERGED")
'@
    Step "Configure, pull the sandbox image, S1 probe (as hermes)"
    $cmd = @"
`$env:NO_COLOR = '1'
`$h = Join-Path `$env:LOCALAPPDATA 'hermes\bin\hermes.exe'
`$cfg = Join-Path `$env:LOCALAPPDATA 'hermes\config.yaml'
`$py = Get-ChildItem (Join-Path `$env:LOCALAPPDATA 'hermes\installs') -Recurse -Filter python.exe -ErrorAction SilentlyContinue |
  Where-Object FullName -match '\\venv\\Scripts\\python\.exe$' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
"PYTHON=`$(`$py.FullName)"
Copy-Item `$cfg "`$cfg.pre-p0.6.bak" -Force
& `$py.FullName '$dir\merge.py' `$cfg '$dir\template.yaml' 2>&1
"##### config check"; & `$h config check 2>&1
foreach (`$k in 'model','terminal.backend','terminal.docker_volumes','terminal.docker_image','approvals') { "##### get `$k"; & `$h config get `$k 2>&1 }
"##### docker pull"
`$img = ((& `$h config get terminal.docker_image 2>&1) -join '').Trim()
& "`$env:ProgramFiles\Docker\Docker\resources\bin\docker.exe" pull `$img 2>&1 | Select-Object -Last 3
"PULLRC=`$LASTEXITCODE IMAGE=`$img"
"##### S1 probe"
& `$h chat -Q -q 'Use your terminal tool to run exactly these two commands and show their raw output: uname -a ; ls -la /workspace/work' 2>&1 | Select-Object -Last 40
"CHATRC=`$LASTEXITCODE"
"@
    $r = & (Join-Path $repo 'scripts\invoke-as-hermes.ps1') -Command $cmd -TimeoutSeconds 2400
    $r.Output | ForEach-Object { Write-Host "  $_" }
    if ($r.TimedOut) { throw ("configure as hermes timed out (task result 0x{0:X8})" -f $r.TaskResult) }
  } finally {
    Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
  }
  Step "Done (configure)"
  if ($LogPath) { Stop-Transcript | Out-Null }
  return
}

# --- Fetch the installer into a folder hermes can read but not change -----------
Step "Fetch install.ps1"
$dir = Join-Path $env:PUBLIC ("hermes-install-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $dir | Out-Null
icacls $dir /inheritance:r /grant:r "hermes:(OI)(CI)RX" "SYSTEM:(OI)(CI)F" "Administrators:(OI)(CI)F" | Out-Null
try {
  $inst = Join-Path $dir 'install.ps1'
  Invoke-WebRequest $lock.hermes_install_url -OutFile $inst -UseBasicParsing
  $got = (Get-FileHash $inst -Algorithm SHA256).Hash
  if ($got -ne $lock.hermes_install_ps1_sha256) {
    throw "install.ps1 changed upstream (sha256 $got, reviewed $($lock.hermes_install_ps1_sha256)). Review it, then update versions.lock."
  }
  Write-Host "sha256 matches the reviewed copy: $got"

  # --- Run it as hermes ----------------------------------------------------------
  Step "Install as hermes (stable channel; this takes several minutes)"
  $cmd = @"
`$env:HERMES_INSTALL_CHANNEL = 'stable'
& ([scriptblock]::Create((Get-Content -Raw '$inst'))) -NonInteractive -Channel stable -SkipBrowser
"INSTALLRC=`$LASTEXITCODE"
`$h = Join-Path `$env:LOCALAPPDATA 'hermes\bin\hermes.exe'
if (-not (Test-Path `$h)) { `$h = (Get-ChildItem (Join-Path `$env:LOCALAPPDATA 'hermes\bin') -Filter 'hermes*' -ErrorAction SilentlyContinue | Select-Object -First 1).FullName }
"HERMESBIN=`$h"
if (`$h) { "VERSION=`$((& `$h --version 2>&1) -join ' ')" }
`$cfg = Join-Path `$env:LOCALAPPDATA 'hermes\config.yaml'
"CONFIG=`$cfg exists=`$(Test-Path `$cfg)"
"@
  $r = & (Join-Path $repo 'scripts\invoke-as-hermes.ps1') -Command $cmd -TimeoutSeconds 2400
  $r.Output | Where-Object { $_ -match '^(INSTALLRC|HERMESBIN|VERSION|CONFIG)=' -or $_ -match 'error|fail|Error|Fail' } |
    ForEach-Object { Write-Host "  $_" }
  $rc = ($r.Output | Where-Object { $_ -like 'INSTALLRC=*' } | Select-Object -First 1) -replace '^INSTALLRC=', ''
  if ($r.TimedOut) { throw "install as hermes timed out (task result 0x{0:X8})" -f $r.TaskResult }
  if ($rc -and $rc -ne '0') { throw "install.ps1 reported failure (LASTEXITCODE=$rc). See %LOCALAPPDATA%\hermes\logs\install.log in hermes's profile." }
  Write-Host "install finished (rc=$rc)"
} finally {
  Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
}

Step "Done (next: S1 spike, then config)"
if ($LogPath) { Stop-Transcript | Out-Null }
