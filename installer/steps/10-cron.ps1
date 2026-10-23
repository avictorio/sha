# installer/steps/10-cron.ps1 -- PLAN.md P1.8: the daily "ping" job in each profile (cron/ping.yaml).
# Run from the `operator` account in an ELEVATED Windows PowerShell; the owner types the hermes password.
# As hermes, per profile: make sure providers.ollama.base_url points at the local server (S3), remove any
# existing job with the same name, create the job (pinned: --model/--provider), and run it once now.
# Then runs verify/checks/p1-8-ping.ps1. Every hermes call has its own time cap and an empty stdin.
param([string]$LogPath, [securestring]$Password)
$ErrorActionPreference = 'Stop'
if ($LogPath) { Start-Transcript -Path $LogPath -Force | Out-Null }
$repo = Split-Path (Split-Path $PSScriptRoot)
$lock = ConvertFrom-StringData ((Get-Content (Join-Path $repo 'versions.lock') | Where-Object { $_ -notmatch '^\s*#' }) -join "`n")
if ($env:USERNAME -ne 'operator') { throw "Not running as 'operator' (got '$env:USERNAME'). Stop: CLAUDE.md rule 1." }
$p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw "Run this elevated (Run as administrator)." }

$job = @{}
Get-Content (Join-Path $repo 'cron\ping.yaml') -Encoding UTF8 | Where-Object { $_ -match '^(\w+):\s*(.+)$' } | ForEach-Object { $job[$Matches[1]] = $Matches[2].Trim() }
if ($job.model -ne $lock.model_default) { throw "cron/ping.yaml model ($($job.model)) isn't versions.lock model_default ($($lock.model_default))." }
if ($job.prompt -match '"') { throw "cron/ping.yaml prompt must not contain double quotes." }
$start = Get-Date

$cmd = @"
[Console]::OutputEncoding = [Text.Encoding]::UTF8; `$env:NO_COLOR = '1'; `$env:PYTHONIOENCODING = 'utf-8'; `$env:COLUMNS = '200'
`$h = Join-Path `$env:LOCALAPPDATA 'hermes\bin\hermes.exe'
function Cap([string]`$argline, [int]`$sec = 90) {
  `$o = [IO.Path]::GetTempFileName(); `$e = [IO.Path]::GetTempFileName(); `$i = [IO.Path]::GetTempFileName()
  `$p = Start-Process `$h -ArgumentList `$argline -NoNewWindow -PassThru -RedirectStandardOutput `$o -RedirectStandardError `$e -RedirectStandardInput `$i
  if (-not `$p.WaitForExit(`$sec * 1000)) { taskkill /PID `$p.Id /T /F 2>&1 | Out-Null; "TIMEOUT after `${sec}s: hermes `$argline" }
  Get-Content `$o, `$e -Encoding UTF8 | Where-Object { "`$_" -notmatch 'sk-or-|\d{6,12}:[A-Za-z0-9_-]{30,}' }
  Remove-Item `$o, `$e, `$i -Force -ErrorAction SilentlyContinue
}
foreach (`$prof in 'default', 'private') {
  `$p = if (`$prof -eq 'default') { '' } else { "-p `$prof " }
  "##### `${prof}: providers.ollama"
  Cap "`${p}config set providers.ollama.base_url http://localhost:11434/v1" 60 | Select-Object -Last 1
  Cap "`${p}config get providers" 60
  # Remove existing jobs with this name (list format: "<id> [state]" then "Name: <name>").
  `$cur = `$null
  foreach (`$line in @(Cap "`${p}cron list" 60)) {
    if (`$line -match '^\s*([0-9a-f]{8,})\s+\[') { `$cur = `$Matches[1] }
    elseif (`$cur -and `$line -match '^\s*Name:\s+$($job.name)\s*$') { Cap "`${p}cron remove `$cur" 60 | Select-Object -Last 1; `$cur = `$null }
  }
  "##### `${prof}: create"
  `$prompt = '$($job.prompt)' -replace '\{profile\}', `$prof
  `$c = @(Cap ("`${p}cron create ``"$($job.schedule)``" ``"`$prompt``" --name $($job.name) --model $($job.model) --provider $($job.provider) --deliver $($job.deliver)") 120)
  `$c | Select-Object -Last 6
  `$id = `$null; foreach (`$line in `$c) { if (`$line -match 'Created job:\s*([0-9a-f]{6,})') { `$id = `$Matches[1] } }
  "JOBID_`$prof=`$id"
  if (`$id) {
    "##### `${prof}: run now"; Cap "`${p}cron run `$id" 300 | Select-Object -Last 3
    "##### `${prof}: runs"; Cap "`${p}cron runs `$id --limit 3" 60
    "##### `${prof}: list"; Cap "`${p}cron list" 60 | Where-Object { `$_ -notmatch '^[\u2500-\u257F]' } | Select-Object -First 12
  }
}
'##### end'
"@
$t = $null; $e = $null; [void][Management.Automation.Language.Parser]::ParseInput($cmd, [ref]$t, [ref]$e)
if ($e.Count) { throw "Internal: the hermes command doesn't parse: $($e[0].Message)" }

$pw = $Password
if (-not $pw) { Write-Host "Type the hermes password (hidden):" -ForegroundColor Yellow; $pw = Read-Host -AsSecureString "hermes password" }
$r = & (Join-Path $repo 'scripts\invoke-as-hermes.ps1') -Password $pw -Command $cmd -TimeoutSeconds 1500
Write-Host "hermes step: TimedOut=$($r.TimedOut) ExitCode=$($r.ExitCode)"
$r.Output | ForEach-Object { Write-Host "  $_" }

& (Join-Path $repo 'verify\checks\p1-8-ping.ps1') -Since $start
if ($LogPath) { Stop-Transcript | Out-Null }
