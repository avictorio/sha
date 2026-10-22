# verify/checks/s14-isolation.ps1 -- PLAN.md S14: does bench/isolate.ps1 cut Hermes off from the network
# while it still reaches Ollama on 127.0.0.1? Run in `operator`, ELEVATED, in a visible window: one chat
# runs AS hermes (the owner types the password). Always ends with isolate.ps1 -Off.
param([string]$LogPath)
$ErrorActionPreference = 'Continue'
if ($LogPath) { Start-Transcript -Path $LogPath -Force | Out-Null }
$results = [ordered]@{}
function Step($m) { Write-Host "`n== $m" -ForegroundColor Cyan }
function Record($name, $ok, $detail) {
  $results[$name] = $ok
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("[{0}] {1}  {2}" -f ($(if ($ok) {'PASS'} else {'FAIL'})), $name, $detail) -ForegroundColor $c
}
$repo = Split-Path (Split-Path $PSScriptRoot)
$docker = "$env:ProgramFiles\Docker\Docker\resources\bin\docker.exe"
function HermesProcs {
  # Filter by path first; GetOwner throws "Not found" for a process that exits in between.
  Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -match '(?i)\\(hermes|python\w*|uv|node)\.exe$' } |
    Where-Object { try { (Invoke-CimMethod -InputObject $_ -MethodName GetOwner -ErrorAction Stop).User -eq 'hermes' } catch { $false } }
}

# A fetch from Hermes's own interpreter(s): the firewall rule applies by program path, whoever runs it.
$probe = Join-Path $env:TEMP 's14-probe.py'
Set-Content $probe -Encoding ASCII -Value @'
import urllib.request as u
for name, url in (("NET", "https://example.com"), ("LOOP", "http://127.0.0.1:11434/api/version")):
    try:
        print("%s=%s" % (name, u.urlopen(url, timeout=10).status))
    except Exception as e:
        print("%s=ERR %s %s" % (name, e.__class__.__name__, str(e)[:100]))
'@
function Probe($py) { (& $py -I $probe 2>&1) | ForEach-Object { "$_" } }

Step "Which programs Hermes runs as (live gateway) and what they connect to"
$procs = @(HermesProcs)
foreach ($pr in $procs) {
  $conns = Get-NetTCPConnection -OwningProcess $pr.ProcessId -State Established -ErrorAction SilentlyContinue |
    ForEach-Object { "$($_.RemoteAddress):$($_.RemotePort)" } | Sort-Object -Unique
  Write-Host ("  PID {0,-6} {1}  -> {2}" -f $pr.ProcessId, $pr.ExecutablePath, ($conns -join ', '))
}
$pys = @($procs | Where-Object { $_.ExecutablePath -match '(?i)python' } | ForEach-Object ExecutablePath | Sort-Object -Unique)
Record 'hermes-python-found' ($pys.Count -gt 0) ($pys -join '; ')
Record 'firewall-enabled' (-not (Get-NetFirewallProfile | Where-Object { -not $_.Enabled })) ((Get-NetFirewallProfile | ForEach-Object { "$($_.Name)=$($_.Enabled)" }) -join ' ')

Step "Baseline (not isolated)"
$base = foreach ($py in $pys) { Probe $py }
Record 'baseline-net-works' ([bool]($base | Where-Object { $_ -eq 'NET=200' })) ($base -join ' | ')

try {
  Step "isolate.ps1 -On"
  & (Join-Path $repo 'bench\isolate.ps1') -On

  Step "Hermes's interpreters, isolated"
  $iso = foreach ($py in $pys) { Probe $py }
  Record 'isolated-net-blocked' (@($iso | Where-Object { $_ -like 'NET=*' }).Count -gt 0 -and -not ($iso | Where-Object { $_ -eq 'NET=200' })) ($iso -join ' | ')
  Record 'isolated-loopback-ok' (-not ($iso | Where-Object { $_ -like 'LOOP=*' -and $_ -ne 'LOOP=200' })) ''

  Step "A real chat as hermes, isolated"
  $r = & (Join-Path $repo 'scripts\invoke-as-hermes.ps1') -TimeoutSeconds 900 -Command @'
[Console]::OutputEncoding = [Text.Encoding]::UTF8; $env:NO_COLOR = '1'; $env:PYTHONIOENCODING = 'utf-8'
$h = Join-Path $env:LOCALAPPDATA 'hermes\bin\hermes.exe'
"##### pong"
& $h chat -Q -q 'Reply with exactly: PONG' 2>&1 | Select-Object -Last 5
"##### sandbox"
& $h chat -Q -q 'Use your terminal tool to run exactly this and show the raw output: curl -sS -m 10 -o /dev/null https://example.com && echo NET_OK || echo NET_BLOCKED' 2>&1 | Select-Object -Last 10
'@
  $r.Output | ForEach-Object { Write-Host "  $_" }
  $pong = ($r.Output -join "`n") -split '##### sandbox' | Select-Object -First 1
  Record 'chat-answers-from-ollama' ($pong -match 'PONG') ''

  $ctr = & $docker ps -q --filter name=^hermes- 2>$null | Select-Object -First 1
  $mode = if ($ctr) { & $docker inspect -f '{{.HostConfig.NetworkMode}}' $ctr 2>&1 } else { 'no sandbox container' }
  Record 'sandbox-network-none' ("$mode" -eq 'none') "NetworkMode=$mode"
  $curl = if ($ctr) { & $docker exec $ctr sh -c 'curl -sS -m 10 -o /dev/null https://example.com && echo NET_OK || echo NET_BLOCKED' 2>&1 } else { '' }
  Record 'sandbox-curl-blocked' (($curl -join ' ') -match 'NET_BLOCKED' -and ($curl -join ' ') -notmatch 'NET_OK') ($curl -join ' ')
} finally {
  Step "isolate.ps1 -Off"
  & (Join-Path $repo 'bench\isolate.ps1') -Off
}

Step "Restored"
$after = foreach ($py in $pys) { Probe $py }
$left = Get-NetFirewallRule -Group 'hermes-bench' -ErrorAction SilentlyContinue
$envLeft = Select-String -Path 'C:\Users\hermes\AppData\Local\hermes\.env' -Pattern '^\s*TERMINAL_DOCKER_NETWORK\s*=' -Quiet
Record 'restored' (($after | Where-Object { $_ -eq 'NET=200' }) -and -not $left -and -not $envLeft) "$($after -join ' | '); rules left=$(@($left).Count); env key left=$envLeft"
Remove-Item $probe -ErrorAction SilentlyContinue

Step "Summary"
$results.GetEnumerator() | ForEach-Object { "{0,-28} {1}" -f $_.Key, $(if ($_.Value) {'PASS'} else {'FAIL'}) }
if ($LogPath) { Stop-Transcript | Out-Null }
