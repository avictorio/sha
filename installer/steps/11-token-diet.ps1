# installer/steps/11-token-diet.ps1 -- PLAN.md P1.9: cut what each default-profile (cloud) request carries.
# Run from the `operator` account in an ELEVATED Windows PowerShell; the owner types the hermes password once.
#   1. as hermes: back up config.yaml, deep-merge config/templates/default.token-diet.yaml (side tasks on
#      the local model, earlier compression, skills.disabled), switch off unused toolsets on cli and
#      telegram, and read the result back;
#   2. restart the default gateway;
#   3. verify/checks/p1-5-usage-log.ps1 (one fresh cloud chat) and compare its input tokens with -Baseline.
# Re-runnable. The local profile is local-only and unchanged.
param([string]$LogPath, [securestring]$Password, [int]$Baseline = 13034)   # baseline: P1.9, 2026-10-22

$ErrorActionPreference = 'Stop'
if ($LogPath) { Start-Transcript -Path $LogPath -Force | Out-Null }
function Step($msg) { Write-Host "`n== $msg" -ForegroundColor Cyan }
$repo = Split-Path (Split-Path $PSScriptRoot)
if ($env:USERNAME -ne 'operator') { throw "Not running as 'operator' (got '$env:USERNAME'). Stop: CLAUDE.md rule 1." }
$p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw "Run this elevated (Run as administrator)." }
$tpl = Join-Path $repo 'config\templates\default.token-diet.yaml'
# Toolsets the default bot doesn't use yet. Browser stays (Phase 3); re-enable with `hermes tools enable`.
$offTools = 'computer_use image_gen tts code_execution delegation'

$pw = $Password
if (-not $pw) {
  Write-Host "Type the hermes password (hidden):" -ForegroundColor Yellow
  $pw = Read-Host -AsSecureString "hermes password"
}

$dir = Join-Path $env:PUBLIC ("hermes-diet-" + [guid]::NewGuid().ToString('N'))
try {
  Step "As hermes: merge default.token-diet.yaml, switch off toolsets, read back"
  New-Item -ItemType Directory $dir | Out-Null
  icacls $dir /inheritance:r /grant:r "hermes:(OI)(CI)RX" "SYSTEM:(OI)(CI)F" "Administrators:(OI)(CI)F" | Out-Null
  Copy-Item $tpl "$dir\template.yaml"
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
        elif isinstance(v, dict): dst[k] = dict(v)
        else: dst[k] = v
merge(cfg, tpl)
with open(cfg_path, "w", encoding="utf-8") as f: y.dump(cfg, f)
print("MERGED")
'@
  $r = & (Join-Path $repo 'scripts\invoke-as-hermes.ps1') -Password $pw -TimeoutSeconds 900 -Command @"
[Console]::OutputEncoding = [Text.Encoding]::UTF8; `$env:NO_COLOR = '1'; `$env:PYTHONIOENCODING = 'utf-8'; `$env:COLUMNS = '200'
`$h = Join-Path `$env:LOCALAPPDATA 'hermes\bin\hermes.exe'
function Cap([string]`$argline, [int]`$sec = 90) {
  `$o = [IO.Path]::GetTempFileName(); `$e = [IO.Path]::GetTempFileName(); `$i = [IO.Path]::GetTempFileName()
  `$pr = Start-Process `$h -ArgumentList `$argline -NoNewWindow -PassThru -RedirectStandardOutput `$o -RedirectStandardError `$e -RedirectStandardInput `$i
  if (-not `$pr.WaitForExit(`$sec * 1000)) { taskkill /PID `$pr.Id /T /F 2>&1 | Out-Null; "TIMEOUT after `${sec}s: hermes `$argline" }
  Get-Content `$o, `$e -Encoding UTF8 | Where-Object { "`$_" -notmatch 'sk-or-|\d{6,12}:[A-Za-z0-9_-]{30,}' }
  Remove-Item `$o, `$e, `$i -Force -ErrorAction SilentlyContinue
}
`$cfg = Join-Path `$env:LOCALAPPDATA 'hermes\config.yaml'
Copy-Item `$cfg "`$cfg.pre-p19-`$(Get-Date -Format yyyyMMdd-HHmmss).bak" -Force
`$py = Get-ChildItem (Join-Path `$env:LOCALAPPDATA 'hermes\installs') -Recurse -Filter python.exe -ErrorAction SilentlyContinue |
  Where-Object FullName -match '\\venv\\Scripts\\python\.exe$' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
& `$py.FullName '$dir\merge.py' `$cfg '$dir\template.yaml' 2>&1
foreach (`$pf in 'cli', 'telegram') { "##### tools disable `$pf"; Cap "tools disable --platform `$pf $offTools" | Select-Object -Last 5 }
foreach (`$a in 'config check', 'config get auxiliary.background_review', 'config get auxiliary.compression', 'config get auxiliary.title_generation',
               'config get compression.threshold', 'config get compression.idle_compact_after_seconds', 'tools list --platform telegram', 'tools list --platform cli') {
  "##### `$a"; Cap `$a | Select-Object -First 40
}
"##### skills list (summary)"; Cap 'skills list' | Select-Object -Last 2
"@
  $r.Output | ForEach-Object { Write-Host "  $_" }
  if ($r.TimedOut) { throw "the hermes step timed out" }
  if (-not ($r.Output -contains 'MERGED')) { throw "The config merge failed; gateway not restarted." }
} finally {
  Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
}

Step "Restart the default gateway"
& (Join-Path $repo 'scripts\restart-gateway.ps1') -Profile default

Step "Check (verify/checks/p1-5-usage-log.ps1), then compare with the baseline"
$log = 'C:\agent\shared\logs\usage-default.jsonl'
$before = if (Test-Path $log) { @(Get-Content $log).Count } else { 0 }
& (Join-Path $repo 'verify\checks\p1-5-usage-log.ps1') -Password $pw -Profile default
$c = @(Get-Content $log -Encoding UTF8 | Select-Object -Skip $before | ForEach-Object { try { $_ | ConvertFrom-Json } catch { } } |
  Where-Object event -eq 'call') | Select-Object -Last 1
if ($c) {
  $in = [int]$c.tokens.input + [int]$c.tokens.cache_read   # cached tokens are still sent, just billed lower
  $cut = [math]::Round(100 * (1 - $in / $Baseline))
  $ok = $in -le [math]::Floor($Baseline * 0.7)
  Write-Host ("[{0}] p1-9-cut  input {1} (cache_read {2}) vs baseline {3}: {4}% fewer" -f $(if ($ok) {'PASS'} else {'FAIL'}), $in, $c.tokens.cache_read, $Baseline, $cut) -ForegroundColor $(if ($ok) {'Green'} else {'Red'})
} else { Write-Host "[FAIL] p1-9-cut  no new call line in $log" -ForegroundColor Red }
if ($LogPath) { Stop-Transcript | Out-Null }
