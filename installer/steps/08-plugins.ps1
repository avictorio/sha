# installer/steps/08-plugins.ps1 -- PLAN.md P1.5: install and enable the usage-log plugin in a profile,
# restart the Telegram gateway cleanly, then run verify/checks/p1-5-usage-log.ps1.
# Run from the `operator` account in an ELEVATED Windows PowerShell, in a visible window: the owner
# types the hermes password once, at the hidden prompt. Re-runnable (the copy is overwritten).
#   -Profile default  now (PLAN.md Phase 1 order: before P1.3)
#   -Profile private  right after P1.3 step 1 creates the private profile
# The approval-policy plugin joins this step in P2.1.
param([ValidateSet('default', 'private')][string]$Profile = 'default', [string]$LogPath)

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
  Step "Stage plugins/usage-log"
  New-Item -ItemType Directory $stage | Out-Null
  icacls $stage /inheritance:r /grant:r "hermes:(OI)(CI)RX" "SYSTEM:(OI)(CI)F" "Administrators:(OI)(CI)F" | Out-Null
  Copy-Item -Recurse (Join-Path $repo 'plugins\usage-log') "$stage\usage-log"

  # The log folder: under C:\agent (hermes has full control), outside the sandbox's mounts.
  New-Item -ItemType Directory -Force 'C:\agent\shared\logs' | Out-Null

  Write-Host "Type the hermes password (hidden):" -ForegroundColor Yellow
  $pw = Read-Host -AsSecureString "hermes password"

  Step "Install and enable usage-log in profile '$Profile' (as hermes)"
  # Profile folders: %LOCALAPPDATA%\hermes (default) and ...\hermes\profiles\<name> (PLAN.md P1.5, verify).
  $dest = if ($Profile -eq 'default') { "`$env:LOCALAPPDATA\hermes\plugins" } else { "`$env:LOCALAPPDATA\hermes\profiles\$Profile\plugins" }
  $pargs = if ($Profile -eq 'default') { '@()' } else { "@('-p', '$Profile')" }
  $r = & (Join-Path $repo 'scripts\invoke-as-hermes.ps1') -Password $pw -Command @"
`$h = Join-Path `$env:LOCALAPPDATA 'hermes\bin\hermes.exe'
`$p = $pargs
`$dest = "$dest"
if (-not (Test-Path (Split-Path `$dest))) { 'NOPROFILE'; return }
New-Item -ItemType Directory -Force `$dest | Out-Null
Remove-Item -Recurse -Force "`$dest\usage-log" -ErrorAction SilentlyContinue
Copy-Item -Recurse '$stage\usage-log' "`$dest\usage-log"
& `$h @p plugins enable usage-log 2>&1
"ENABLED=`$((& `$h @p config get plugins.enabled 2>&1) -join ' ')"
"@
  $r.Output | ForEach-Object { Write-Host "  $_" }
  if ($r.Output -contains 'NOPROFILE') { throw "Profile '$Profile' has no folder yet ($dest). For private, run P1.3 step 1 first." }
  if (-not ($r.Output | Where-Object { $_ -like 'ENABLED=*usage-log*' })) { throw "usage-log isn't in plugins.enabled; gateway not restarted." }

  Step "Restart the Telegram gateway cleanly"
  # Start-ScheduledTask is a no-op on a running task, and Stop-ScheduledTask can leave hermes.exe/python behind.
  Stop-ScheduledTask -TaskName 'Hermes_Gateway' -ErrorAction SilentlyContinue
  Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'gateway run|start-gateway\.ps1' } |
    Where-Object { try { (Invoke-CimMethod -InputObject $_ -MethodName GetOwner -ErrorAction Stop).User -eq 'hermes' } catch { $false } } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  Start-Sleep 3
  Start-ScheduledTask -TaskName 'Hermes_Gateway'
  Write-Host "restarted Hermes_Gateway"

  Step "Check (verify/checks/p1-5-usage-log.ps1)"
  & (Join-Path $repo 'verify\checks\p1-5-usage-log.ps1') -Password $pw -Profile $Profile
} finally {
  Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
  if ($LogPath) { Stop-Transcript | Out-Null }
}
