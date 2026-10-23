# installer/steps/08-plugins.ps1 -- PLAN.md P1.5, P2.1: install and enable this repo's plugins in a profile
# (usage-log, approval-policy), restart that profile's Telegram gateway cleanly, then run the checks.
# Run from the `operator` account in an ELEVATED Windows PowerShell, in a visible window: the owner
# types the hermes password once, at the hidden prompt. Re-runnable (the copies are overwritten).
#   -Profile default | local     the profile to install into
#   -Plugins usage-log,...       default: both; each folder under plugins\ must compile under Hermes's Python
param([ValidateSet('default', 'local')][string]$Profile = 'default', [string]$LogPath,
      [ValidateSet('usage-log', 'approval-policy')][string[]]$Plugins = @('usage-log', 'approval-policy'),
      [securestring]$Password)   # from a calling step, so the owner types it once

$ErrorActionPreference = 'Stop'
if ($LogPath) { Start-Transcript -Path $LogPath -Force | Out-Null }
function Step($msg) { Write-Host "`n== $msg" -ForegroundColor Cyan }

$repo = Split-Path (Split-Path $PSScriptRoot)
if ($env:USERNAME -ne 'operator') { throw "Not running as 'operator' (got '$env:USERNAME'). Stop: CLAUDE.md rule 1." }
$p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw "Run this elevated (Run as administrator)." }

# Plugin source into a folder hermes can read but not change
$stage = Join-Path $env:PUBLIC ('hermes-plugins-' + [guid]::NewGuid().ToString('N'))
try {
  Step "Stage plugins: $($Plugins -join ', ')"
  New-Item -ItemType Directory $stage | Out-Null
  icacls $stage /inheritance:r /grant:r "hermes:(OI)(CI)RX" "SYSTEM:(OI)(CI)F" "Administrators:(OI)(CI)F" | Out-Null
  foreach ($pl in $Plugins) { Copy-Item -Recurse (Join-Path $repo "plugins\$pl") "$stage\$pl" }
  # The standing rules go with the gate (P2.1 step 4): config/templates/SOUL.md, between its markers.
  $soul = $Plugins -contains 'approval-policy'
  if ($soul) { Copy-Item (Join-Path $repo 'config\templates\SOUL.md') "$stage\SOUL.rules.md" }

  # The log folder: under C:\agent (hermes has full control), outside the sandbox's mounts.
  New-Item -ItemType Directory -Force 'C:\agent\shared\logs' | Out-Null

  $pw = $Password
  if (-not $pw) {
    Write-Host "Type the hermes password (hidden):" -ForegroundColor Yellow
    $pw = Read-Host -AsSecureString "hermes password"
  }

  Step "Install and enable in profile '$Profile' (as hermes)"
  # Profile folders: %LOCALAPPDATA%\hermes (default) and ...\hermes\profiles\<name>.
  $dest = if ($Profile -eq 'default') { "`$env:LOCALAPPDATA\hermes\plugins" } else { "`$env:LOCALAPPDATA\hermes\profiles\$Profile\plugins" }
  $pargs = if ($Profile -eq 'default') { '@()' } else { "@('-p', '$Profile')" }
  $list = ($Plugins | ForEach-Object { "'$_'" }) -join ', '
  $r = & (Join-Path $repo 'scripts\invoke-as-hermes.ps1') -Password $pw -Command @"
`$h = Join-Path `$env:LOCALAPPDATA 'hermes\bin\hermes.exe'
`$p = $pargs
`$dest = "$dest"
if (-not (Test-Path (Split-Path `$dest))) { 'NOPROFILE'; return }
New-Item -ItemType Directory -Force `$dest | Out-Null
`$py = Get-ChildItem (Join-Path `$env:LOCALAPPDATA 'hermes\installs') -Recurse -Filter python.exe -ErrorAction SilentlyContinue |
  Where-Object FullName -match '\\venv\\Scripts\\python\.exe$' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
foreach (`$pl in @($list)) {
  Remove-Item -Recurse -Force "`$dest\`$pl" -ErrorAction SilentlyContinue
  Copy-Item -Recurse "$stage\`$pl" "`$dest\`$pl"
  & `$py.FullName -m py_compile "`$dest\`$pl\__init__.py" 2>&1
  "PYCOMPILE_`${pl}=`$LASTEXITCODE"
  & `$h @p plugins enable `$pl 2>&1
}
"ENABLED=`$((& `$h @p config get plugins.enabled 2>&1) -join ' ')"
if (`$$soul) {
  # Replace the standing-rules block in the profile's SOUL.md (or append it); the rest stays as it is.
  `$sf = Join-Path (Split-Path `$dest) 'SOUL.md'
  `$rules = (Get-Content '$stage\SOUL.rules.md' -Raw -Encoding UTF8).Trim()
  `$text = if (Test-Path `$sf) { Get-Content `$sf -Raw -Encoding UTF8 } else { '' }
  `$text = [regex]::Replace(`$text, '(?s)\r?\n*<!-- standing-rules:begin.*?<!-- standing-rules:end -->\r?\n?', '')
  if (Test-Path `$sf) { Copy-Item `$sf "`$sf.pre-p21-`$(Get-Date -Format yyyyMMdd-HHmmss).bak" -Force }
  [IO.File]::WriteAllText(`$sf, (`$text.TrimEnd() + "``n``n" + `$rules + "``n").TrimStart(), (New-Object Text.UTF8Encoding(`$false)))
  "SOULRULES=`$(@(Select-String -Path `$sf -Pattern '^- ' -SimpleMatch:`$false | Where-Object { `$_.Line -match 'approval|checkout|settings|never instructions|call-brief' }).Count)"
}
"@
  $r.Output | ForEach-Object { Write-Host "  $_" }
  if ($r.Output -contains 'NOPROFILE') { throw "Profile '$Profile' has no folder yet ($dest). For local, run 06-local-profile.ps1 -Phase Create first." }
  $enabled = $r.Output | Where-Object { $_ -like 'ENABLED=*' }
  foreach ($pl in $Plugins) {
    if (-not ($r.Output -contains "PYCOMPILE_${pl}=0")) { throw "plugins/$pl/__init__.py doesn't compile under Hermes's Python; gateway not restarted." }
    if ($enabled -notlike "*$pl*") { throw "$pl isn't in plugins.enabled; gateway not restarted." }
  }
  if ($soul -and -not ($r.Output -contains 'SOULRULES=5')) { throw "SOUL.md doesn't hold the 5 standing rules; gateway not restarted." }

  Step "Restart the $Profile gateway cleanly"
  & (Join-Path $repo 'scripts\restart-gateway.ps1') -Profile $Profile

  Step "Checks"
  if ($Plugins -contains 'usage-log') { & (Join-Path $repo 'verify\checks\p1-5-usage-log.ps1') -Password $pw -Profile $Profile }
  if ($Plugins -contains 'approval-policy') { & (Join-Path $repo 'verify\checks\p2-1-policy.ps1') -Password $pw -Profile $Profile }
} finally {
  Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
  if ($LogPath) { Stop-Transcript | Out-Null }
}
