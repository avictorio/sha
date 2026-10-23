# installer/steps/07-cloud.ps1 -- PLAN.md P1.4: OpenRouter for the default profile only, cloud-first (D2 revised
# per PLAN section 9, D9), falling back to the local model.
# Run from the `operator` account in an ELEVATED Windows PowerShell, in a visible window. The owner types:
# the OpenRouter key (hidden), then the hermes password.
#   1. the key goes from the hidden prompt to OpenRouter's GET /api/v1/key (to read its limit back) and
#      into the DEFAULT profile's .env only: never on a command line, in a script file or in a log;
#   2. refuses unless the key has a limit, no higher than versions.lock cloud_key_limit_usd, with a
#      monthly reset (CLAUDE.md: spend caps stay set);
#   3. as hermes: deep-merges config/templates/default.cloud.yaml into the default config.yaml (backed up
#      first) and reads it back;
#   4. restarts the default gateway (scripts/restart-gateway.ps1), then runs verify/checks/p1-4-cloud.ps1.
# Re-runnable. -SkipKey: keep the key already in .env (steps 3-4 only).
param([string]$LogPath, [switch]$SkipKey)

$ErrorActionPreference = 'Stop'
if ($LogPath) { Start-Transcript -Path $LogPath -Force | Out-Null }
function Step($msg) { Write-Host "`n== $msg" -ForegroundColor Cyan }
$repo = Split-Path (Split-Path $PSScriptRoot)
$lock = ConvertFrom-StringData ((Get-Content (Join-Path $repo 'versions.lock') | Where-Object { $_ -notmatch '^\s*#' }) -join "`n")
if ($env:USERNAME -ne 'operator') { throw "Not running as 'operator' (got '$env:USERNAME'). Stop: CLAUDE.md rule 1." }
$p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw "Run this elevated (Run as administrator)." }
$hermesRoot = 'C:\Users\hermes\AppData\Local\hermes'
$defEnv = "$hermesRoot\.env"; $localEnv = "$hermesRoot\profiles\local\.env"
$tpl = Join-Path $repo 'config\templates\default.cloud.yaml'
if (-not (Select-String -Path $tpl -SimpleMatch "default: $($lock.cloud_model_default)" -Quiet)) { throw "default.cloud.yaml doesn't name versions.lock cloud_model_default ($($lock.cloud_model_default))." }
if (-not (Test-Path $defEnv)) { throw "$defEnv not found (P0.6 done?)" }
# Credentials never go to the local profile (D3, P1.3).
if (Select-String -Path $localEnv -Pattern '^\s*OPENROUTER' -Quiet -ErrorAction SilentlyContinue) { throw "The LOCAL .env has an OPENROUTER entry. Stop: tell the owner." }

function Set-EnvLine([string]$path, [string]$key, [string]$value) {
  $lines = [Collections.Generic.List[string]]([IO.File]::ReadAllLines($path))
  $i = $lines.FindIndex({ param($l) $l -match "^\s*#?\s*$key\s*=" })
  if ($i -ge 0) { $lines[$i] = "$key=$value" } else { $lines.Add("$key=$value") }
  [IO.File]::WriteAllLines($path, $lines, (New-Object Text.UTF8Encoding $false))   # keeps the file's ACL
}

if (-not $SkipKey) {
  Step "OpenRouter key for the default profile (hidden)"
  $sec = Read-Host -AsSecureString "OpenRouter key"
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
  try {
    $key = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr).Trim()
    if ($key -notmatch '^sk-or-[A-Za-z0-9_-]{20,}$') { throw "That doesn't look like an OpenRouter key (expected sk-or-...)." }
    Step "Read the key's limit back from OpenRouter (GET /api/v1/key; the key itself is never shown)"
    $info = (Invoke-RestMethod -Uri 'https://openrouter.ai/api/v1/key' -Headers @{ Authorization = "Bearer $key" }).data
    # Not the label: OpenRouter's default label is a masked copy of the key.
    Write-Host ("  limit={0} limit_reset={1} limit_remaining={2} usage={3}" -f $info.limit, $info.limit_reset, $info.limit_remaining, $info.usage)
    if ($null -eq $info.limit) { throw "This key has NO credit limit. Set a limit of `$$($lock.cloud_key_limit_usd), reset monthly (D9), then run this again. Key NOT saved." }
    if ([double]$info.limit -gt [double]$lock.cloud_key_limit_usd) { throw "The key's limit (`$$($info.limit)) is above D9's `$$($lock.cloud_key_limit_usd). Key NOT saved." }
    if ($info.limit_reset) {
      if ($info.limit_reset -ne 'monthly') { throw "The key's limit resets '$($info.limit_reset)', not monthly (D9). Key NOT saved." }
    } else {
      # GET /api/v1/key returned no limit_reset (2026-10-22); the owner confirms it from the OpenRouter key page.
      Write-Host "OpenRouter didn't report the key's reset period." -ForegroundColor Yellow
      if ((Read-Host "On openrouter.ai/settings/keys, is this key's limit set to reset MONTHLY? (y/N)") -notmatch '^(y|yes)$') { throw "Set the key's limit to reset monthly (D9), then run this again. Key NOT saved." }
    }
    Step "Write OPENROUTER_API_KEY to the default profile's .env"
    Set-EnvLine $defEnv 'OPENROUTER_API_KEY' $key
    Write-Host "written (key not shown)"
  } finally {
    $key = $null
    if ($bstr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
  }
} elseif (-not (Select-String -Path $defEnv -Pattern '^\s*OPENROUTER_API_KEY\s*=\s*\S' -Quiet)) { throw "-SkipKey, but the default .env has no OPENROUTER_API_KEY." }

Write-Host "Type the hermes password (hidden):" -ForegroundColor Yellow
$pw = Read-Host -AsSecureString "hermes password"

$dir = Join-Path $env:PUBLIC ("hermes-cloud-" + [guid]::NewGuid().ToString('N'))
try {
  Step "As hermes: merge default.cloud.yaml into the default config, read it back"
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
        else: dst[k] = v
merge(cfg, tpl)
with open(cfg_path, "w", encoding="utf-8") as f: y.dump(cfg, f)
print("MERGED")
'@
  $r = & (Join-Path $repo 'scripts\invoke-as-hermes.ps1') -Password $pw -TimeoutSeconds 600 -Command @"
[Console]::OutputEncoding = [Text.Encoding]::UTF8; `$env:NO_COLOR = '1'; `$env:PYTHONIOENCODING = 'utf-8'; `$env:COLUMNS = '200'
`$h = Join-Path `$env:LOCALAPPDATA 'hermes\bin\hermes.exe'
function Herm { & `$h @args 2>&1 | Where-Object { "`$_" -notmatch '^System\.Management\.Automation' } }
`$cfg = Join-Path `$env:LOCALAPPDATA 'hermes\config.yaml'
Copy-Item `$cfg "`$cfg.pre-p14-`$(Get-Date -Format yyyyMMdd-HHmmss).bak" -Force
`$py = Get-ChildItem (Join-Path `$env:LOCALAPPDATA 'hermes\installs') -Recurse -Filter python.exe -ErrorAction SilentlyContinue |
  Where-Object FullName -match '\\venv\\Scripts\\python\.exe$' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
& `$py.FullName '$dir\merge.py' `$cfg '$dir\template.yaml' 2>&1
foreach (`$a in @('config','check'), @('config','get','model'), @('fallback','list'), @('auth','list'), @('config','get','delegation'), @('config','get','auxiliary')) {
  "##### `$(`$a -join ' ')"; Herm @a | Where-Object { "`$_" -notmatch 'sk-or-' } | Select-Object -First 60
}
"@
  $r.Output | ForEach-Object { Write-Host "  $_" }
  if ($r.TimedOut) { throw "the hermes step timed out" }
  if (-not ($r.Output -contains 'MERGED')) { throw "The config merge failed; gateway not restarted." }
} finally {
  Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
}

Step "Restart the default gateway"
& (Join-Path $repo 'scripts\restart-gateway.ps1') -Profile default

Step "Check (verify/checks/p1-4-cloud.ps1)"
& (Join-Path $repo 'verify\checks\p1-4-cloud.ps1') -Password $pw
Step "Done. Next: the Telegram tests in docs/SETUP-GUIDE.md#openrouter"
if ($LogPath) { Stop-Transcript | Out-Null }
