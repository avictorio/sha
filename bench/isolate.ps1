# bench/isolate.ps1 -- cut Hermes (not the machine) off from the network for the P1.1 benchmark (PLAN.md S14).
# Run in `operator`, ELEVATED. -On / -Off. Claude keeps its own connection; Ollama on 127.0.0.1 keeps working.
#   1. Outbound firewall block rules (group "hermes-bench") on every program Hermes runs as: the executables
#      of hermes's live processes, plus hermes.exe / python*.exe / uv.exe / node.exe under hermes's AppData.
#      A venv's python.exe is only a launcher, so the real interpreter must be blocked too.
#   2. The sandbox: TERMINAL_DOCKER_NETWORK=false in hermes's .env (= terminal.docker_network: false,
#      --network=none), and the sandbox container removed so Hermes recreates it without a network.
# While isolated, the Telegram gateway can't reach Telegram either; it resumes after -Off.
param([switch]$On, [switch]$Off)

$ErrorActionPreference = 'Stop'
if ($On -eq $Off) { throw "Use exactly one of -On or -Off." }
$p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw "Run this elevated." }
$group = 'hermes-bench'
$envFile = 'C:\Users\hermes\AppData\Local\hermes\.env'
$docker = "$env:ProgramFiles\Docker\Docker\resources\bin\docker.exe"

function Set-EnvKey([string]$key, [string]$value, [switch]$Remove) {   # keeps the file's ACL
  # -Remove, not $null: PS turns $null into "" for a [string] parameter, which wrote "KEY=".
  $lines = [Collections.Generic.List[string]]([IO.File]::ReadAllLines($envFile))
  $lines.RemoveAll({ param($l) $l -match "^\s*$key\s*=" }) | Out-Null
  if (-not $Remove) { $lines.Add("$key=$value") }
  [IO.File]::WriteAllLines($envFile, $lines, (New-Object Text.UTF8Encoding $false))
}
function Remove-Sandbox {
  & $docker ps -a -q --filter name=^hermes- 2>$null | ForEach-Object { & $docker rm -f $_ 2>&1 | Out-Null; Write-Host "removed sandbox container $_" }
}

if ($On) {
  $prof = Get-NetFirewallProfile | Where-Object { -not $_.Enabled }
  if ($prof) { throw "Windows Firewall is off for: $($prof.Name -join ', '). The block rules would do nothing." }
  # Filter by path first; GetOwner throws "Not found" for a process that exits in between.
  $live = Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -match '(?i)\\(hermes|python\w*|uv|node)\.exe$' } |
    Where-Object { try { (Invoke-CimMethod -InputObject $_ -MethodName GetOwner -ErrorAction Stop).User -eq 'hermes' } catch { $false } } |
    ForEach-Object ExecutablePath
  $found = Get-ChildItem 'C:\Users\hermes\AppData' -Recurse -File -Include hermes.exe, python*.exe, uv.exe, node.exe -ErrorAction SilentlyContinue |
    ForEach-Object FullName
  $programs = @($live) + @($found) | Sort-Object -Unique
  if (-not $programs) { throw "Found no Hermes executables to block." }
  Get-NetFirewallRule -Group $group -ErrorAction SilentlyContinue | Remove-NetFirewallRule
  foreach ($prog in $programs) {
    New-NetFirewallRule -DisplayName "bench-block-hermes: $(Split-Path $prog -Leaf)" -Group $group -Direction Outbound `
      -Action Block -Program $prog -Profile Any | Out-Null
    Write-Host "blocked outbound: $prog"
  }
  Set-EnvKey 'TERMINAL_DOCKER_NETWORK' 'false'
  Remove-Sandbox
  Write-Host "ISOLATED: $($programs.Count) programs blocked; sandbox network off." -ForegroundColor Yellow
} else {
  Get-NetFirewallRule -Group $group -ErrorAction SilentlyContinue | Remove-NetFirewallRule
  Set-EnvKey 'TERMINAL_DOCKER_NETWORK' -Remove
  Remove-Sandbox
  # Clean gateway restart: its Telegram polling gives up after 10 failed reconnects (40 s apart), fewer
  # than a benchmark run lasts. Both bots: each one's Telegram polling was blocked.
  $repo = Split-Path $PSScriptRoot
  & (Join-Path $repo 'scripts\restart-gateway.ps1') -Profile default
  & (Join-Path $repo 'scripts\restart-gateway.ps1') -Profile private
  Write-Host "NOT ISOLATED: rules removed; sandbox network back to default." -ForegroundColor Green
}
