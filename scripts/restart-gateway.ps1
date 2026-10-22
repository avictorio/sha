# scripts/restart-gateway.ps1 -- clean restart of one profile's guarded Telegram gateway task. ELEVATED.
#   Hermes_Gateway (default) or Hermes_Gateway_<profile>, each running C:\agent\bin\start-gateway.ps1.
# Start-ScheduledTask is a no-op on a running task, and Stop-ScheduledTask can leave hermes.exe/python behind,
# so this kills the task's process tree itself. Hermes drops "-p <profile>" when it re-executes, so the
# gateway processes all read "gateway run --quiet": a profile's processes are found as the descendants of
# its start-gateway.ps1 launcher. Temporary gateways that `hermes chat` auto-starts (--idle-exit) are
# stopped too: they hold the profile's gateway lock, so a fresh start would exit 1 (P1.3).
param([ValidateSet('default', 'private')][string]$Profile = 'default', [switch]$StopOnly)
$ErrorActionPreference = 'Stop'
$task = if ($Profile -eq 'default') { 'Hermes_Gateway' } else { "Hermes_Gateway_$Profile" }
if (-not (Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue)) { Write-Host "no $task task; nothing to restart"; return }

$all = @(Get-CimInstance Win32_Process)
function Descendants($ids) {
  $found = @(); $queue = @($ids | Where-Object { $_ })
  while ($queue.Count) { $kids = @($all | Where-Object { $queue -contains $_.ParentProcessId }); $found += $kids; $queue = @($kids | ForEach-Object ProcessId) }
  $found
}
# A launcher without -Profile is the pre-P1.3 default task.
$launchers = @($all | Where-Object { $_.CommandLine -match 'start-gateway\.ps1' } | Where-Object {
  if ($_.CommandLine -match '-Profile\s+(\w+)') { $Matches[1] -eq $Profile } else { $Profile -eq 'default' } })
$idle = @($all | Where-Object { $_.CommandLine -match 'gateway run.*--idle-exit' })
$kill = @($launchers) + @(Descendants $launchers.ProcessId) + $idle + @(Descendants $idle.ProcessId)

Stop-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
foreach ($p in ($kill | Sort-Object ProcessId -Unique)) { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }
Write-Host "stopped $(@($kill).Count) process(es) for $task (incl. $($idle.Count) temporary --idle-exit)"
if ($StopOnly) { return }
Start-Sleep 3
Start-ScheduledTask -TaskName $task
Write-Host "restarted $task"
