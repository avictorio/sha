# verify/checks/s1-docker-backend.ps1 -- PLAN.md S1: does Hermes's Docker backend work on native Windows?
# Run in the `operator` account, in an ELEVATED Windows PowerShell, in a visible window
# (the owner types the hermes password; scripts/invoke-as-hermes.ps1). Needs P0.6's config applied.
$ErrorActionPreference = 'Continue'
if ($env:USERNAME -ne 'operator') { throw "Not running as 'operator' (got '$env:USERNAME')." }
$repo = Split-Path (Split-Path $PSScriptRoot)

$r = & (Join-Path $repo 'scripts\invoke-as-hermes.ps1') -TimeoutSeconds 900 -Command @'
$env:NO_COLOR = '1'
$h = Join-Path $env:LOCALAPPDATA 'hermes\bin\hermes.exe'
"BACKEND=$((& $h config get terminal.backend 2>&1) -join '')"
& $h chat -Q -q 'Use your terminal tool to run exactly these two commands and show their raw output: uname -a ; ls -la /workspace/work' 2>&1 | Select-Object -Last 40
'@
$out = $r.Output -join "`n"
$backend = ($r.Output | Where-Object { $_ -like 'BACKEND=*' }) -replace '^BACKEND=', ''
$linux = $out -match 'Linux \S+ \S+.*x86_64'
$mount = $out -match '(?m)\scalls\s*$'     # C:\agent\workspace\calls, created by 01-host.ps1
foreach ($c in @(@('backend-docker', ($backend -eq 'docker'), $backend), @('container-is-linux', $linux, ''), @('workspace-mount-visible', $mount, 'expects calls/ from C:\agent\workspace'))) {
  $col = if ($c[1]) { 'Green' } else { 'Red' }
  Write-Host ("[{0}] {1}  {2}" -f ($(if ($c[1]) {'PASS'} else {'FAIL'})), $c[0], $c[2]) -ForegroundColor $col
}
