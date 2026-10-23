# verify/checks/s3-cron-provider.ps1 -- PLAN.md S3: can a cron job be pinned to the local model?
# Run in the `operator` account, ELEVATED; the owner types the hermes password. As hermes, per profile:
# create a job (daily 12:00; `cron run` refuses paused jobs, so it is created active and removed right after) pinned with --model <model_default> --provider custom, trigger it once (`cron run`
# fires on the next tick), wait for its run record, then remove the job. If the default profile's custom
# attempt fails, retry with providers.ollama.base_url + --provider ollama (PLAN.md S3 step 2).
# Every hermes call runs with its own time cap and an empty stdin, so an unexpected prompt fails fast
# (the first version stalled for 30 min with no output). Deliveries go to each profile's own bot ("pong").
# -Profiles limits the run; -Step Create stops after creating the job (for diagnosis).
param([securestring]$Password, [string[]]$Profiles = @('default', 'local'), [ValidateSet('All', 'Create')][string]$Step = 'All', [string]$LogPath)
$ErrorActionPreference = 'Continue'
if ($LogPath) { Start-Transcript -Path $LogPath -Force | Out-Null }
try {
if ($env:USERNAME -ne 'operator') { throw "Not running as 'operator' (got '$env:USERNAME')." }
$repo = Split-Path (Split-Path $PSScriptRoot)
$lock = ConvertFrom-StringData ((Get-Content (Join-Path $repo 'versions.lock') | Where-Object { $_ -notmatch '^\s*#' }) -join "`n")
$logs = @{ default = 'C:\agent\shared\logs\usage-default.jsonl'; local = 'C:\agent\shared\logs\usage-local.jsonl' }
$before = @{}; foreach ($k in $logs.Keys) { $before[$k] = if (Test-Path $logs[$k]) { @(Get-Content $logs[$k]).Count } else { 0 } }

$cmd = @"
[Console]::OutputEncoding = [Text.Encoding]::UTF8; `$env:NO_COLOR = '1'; `$env:PYTHONIOENCODING = 'utf-8'; `$env:COLUMNS = '200'
`$h = Join-Path `$env:LOCALAPPDATA 'hermes\bin\hermes.exe'
`$model = '$($lock.model_default)'
`$step = '$Step'
# One hermes call, capped, stdin empty; returns its stdout+stderr lines, or a TIMEOUT line first.
function Cap([string]`$argline, [int]`$sec = 90) {
  `$o = [IO.Path]::GetTempFileName(); `$e = [IO.Path]::GetTempFileName(); `$i = [IO.Path]::GetTempFileName()
  `$p = Start-Process `$h -ArgumentList `$argline -NoNewWindow -PassThru -RedirectStandardOutput `$o -RedirectStandardError `$e -RedirectStandardInput `$i
  if (-not `$p.WaitForExit(`$sec * 1000)) { taskkill /PID `$p.Id /T /F 2>&1 | Out-Null; "TIMEOUT after `${sec}s: hermes `$argline" }
  Get-Content `$o, `$e -Encoding UTF8 | Where-Object { "`$_" -notmatch 'sk-or-|\d{6,12}:[A-Za-z0-9_-]{30,}' }
  Remove-Item `$o, `$e, `$i -Force -ErrorAction SilentlyContinue
}
function Try-Pin(`$prof, `$provider) {
  `$p = if (`$prof -eq 'default') { '' } else { "-p `$prof " }
  `$name = "s3-`$provider"
  # Remove leftover s3-* jobs from an earlier attempt (list format: "<id> [state]" then "Name: <name>").
  `$cur = `$null
  foreach (`$line in @(Cap "`${p}cron list" 60)) {
    if (`$line -match '^\s*([0-9a-f]{8,})\s+\[') { `$cur = `$Matches[1] }
    elseif (`$cur -and `$line -match '^\s*Name:\s+s3-') { "removing leftover `$cur"; Cap "`${p}cron remove `$cur" 60 | Select-Object -Last 1; `$cur = `$null }
  }
  "##### `$prof / `${provider}: create"
  `$c = @(Cap ("`${p}cron create ``"0 12 * * *``" ``"Reply with the words pong from `$prof and the current time.``" --name `$name --model `$model --provider `$provider --deliver telegram") 120)
  `$c | Select-Object -Last 12
  "##### `${prof}: list"
  `$l = @(Cap "`${p}cron list" 60); `$l | Select-Object -First 20
  # The id, from create's "Created job: <id>".
  `$id = `$null
  foreach (`$line in `$c) { if (`$line -match 'Created job:\s*([0-9a-f]{6,})') { `$id = `$Matches[1]; break } }
  "JOBID=`$id"
  if (-not `$id -or `$step -eq 'Create') { "RESULT=`$prof/`$provider/stopped (id=`$id)"; `$script:lastOk = `$null; return }
  "##### `$prof / `${provider}: run"; Cap "`${p}cron run `$id" 60 | Select-Object -Last 4
  `$deadline = (Get-Date).AddSeconds(240); `$runs = @()
  do { Start-Sleep 15; `$runs = @(Cap "`${p}cron runs `$id --limit 5" 60) } while ((Get-Date) -lt `$deadline -and -not (`$runs -match '(?i)\b(success|succeeded|ok|failed|error)\b'))
  "##### `$prof / `${provider}: runs"; `$runs | Select-Object -First 15
  "##### `$prof / `${provider}: remove"; Cap "`${p}cron remove `$id" 60 | Select-Object -Last 2
  `$ok = [bool](`$runs -match '(?i)\b(success|succeeded)\b') -and -not (`$runs -match '(?i)\bfailed\b')
  "RESULT=`$prof/`$provider/`$ok"; `$script:lastOk = `$ok
}
foreach (`$prof in @('$($Profiles -join "','")')) {
  `$p = if (`$prof -eq 'default') { '' } else { "-p `$prof " }
  "##### `${prof}: status"; Cap "`${p}cron status" 60 | Select-Object -First 4
  Try-Pin `$prof 'custom'
  if (`$prof -eq 'default' -and `$script:lastOk -eq `$false) {
    '##### default: providers.ollama.base_url, then --provider ollama'
    Cap 'config set providers.ollama.base_url http://localhost:11434/v1' 60
    Cap 'config get providers' 60
    Try-Pin 'default' 'ollama'
  }
}
'##### end'
"@
$args_ = @{ Command = $cmd; TimeoutSeconds = 1800 }
if ($Password) { $args_.Password = $Password }
$r = & (Join-Path $repo 'scripts\invoke-as-hermes.ps1') @args_
Write-Host "hermes step: TimedOut=$($r.TimedOut) ExitCode=$($r.ExitCode)"
$r.Output | ForEach-Object { Write-Host "  $_" }

foreach ($k in $Profiles) {
  $new = if (Test-Path $logs[$k]) { @(Get-Content $logs[$k] -Encoding UTF8 | Select-Object -Skip $before[$k]) } else { @() }
  Write-Host "--- usage-$k new lines (fields only)"
  $new | ForEach-Object { try { $_ | ConvertFrom-Json } catch { } } | ForEach-Object {
    Write-Host ("  {0} {1} platform={2} model={3} provider={4} local={5} base_url={6}" -f $_.ts, $_.event, $_.platform, $_.model, $_.provider, $_.local, $_.base_url)
  }
}
} finally {
  if ($LogPath) { Stop-Transcript | Out-Null }
}
