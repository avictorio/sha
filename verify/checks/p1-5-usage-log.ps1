# verify/checks/p1-5-usage-log.ps1 -- PLAN.md P1.5: the usage-log plugin writes one line per model call.
# Run in the `operator` account, ELEVATED, in a visible window: the chat runs AS hermes via
# scripts/invoke-as-hermes.ps1 (the owner types the password, unless -Password is passed in).
# Makes one `hermes chat` call in the given profile, then checks the new line(s) in
# C:\agent\shared\logs\usage-<profile>.jsonl: profile, model, a local base_url, tokens and duration.
# The Telegram half of P1.5's Done-when (per-bot profile; no "local": false in usage-local) is
# checked during P1.3/P1.4. Re-runnable.
param([securestring]$Password, [ValidateSet('default', 'local')][string]$Profile = 'default', [string]$LogPath)
$ErrorActionPreference = 'Continue'
if ($LogPath) { Start-Transcript -Path $LogPath -Force | Out-Null }
try {
$results = [ordered]@{}
function Record($name, $ok, $detail) {
  $results[$name] = $ok
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("[{0}] {1}  {2}" -f ($(if ($ok) {'PASS'} else {'FAIL'})), $name, $detail) -ForegroundColor $c
}
if ($env:USERNAME -ne 'operator') { throw "Not running as 'operator' (got '$env:USERNAME')." }
$repo = Split-Path (Split-Path $PSScriptRoot)
$lock = ConvertFrom-StringData ((Get-Content (Join-Path $repo 'versions.lock') | Where-Object { $_ -notmatch '^\s*#' }) -join "`n")
$log = "C:\agent\shared\logs\usage-$Profile.jsonl"
$before = if (Test-Path $log) { @(Get-Content $log).Count } else { 0 }

$pargs = if ($Profile -eq 'default') { '@()' } else { "@('-p', '$Profile')" }
$cmd = @"
`$h = Join-Path `$env:LOCALAPPDATA 'hermes\bin\hermes.exe'
`$p = $pargs
'##### plugins'
& `$h @p plugins list 2>&1
'##### chat'
& `$h @p chat -Q -q 'Reply with exactly the word PONG and nothing else.' 2>&1 | Where-Object { "`$_" -notmatch '^System\.Management\.Automation' } | Select-Object -Last 5
"@
$args_ = @{ Command = $cmd; TimeoutSeconds = 600 }
if ($Password) { $args_.Password = $Password }
$r = & (Join-Path $repo 'scripts\invoke-as-hermes.ps1') @args_
$out = $r.Output -join "`n"
Record 'plugin-listed' ($out -match '(?m)usage-log') (($r.Output | Where-Object { $_ -match 'usage-log' } | Select-Object -First 1) -replace '\s+', ' ')
Record 'chat-answers' ($out -match 'PONG') ''

$new = if (Test-Path $log) { @(Get-Content $log -Encoding UTF8 | Select-Object -Skip $before) } else { @() }
Record 'new-lines' ($new.Count -ge 1) "$($new.Count) new line(s) in $log"
$calls = @($new | ForEach-Object { try { $_ | ConvertFrom-Json } catch { } } | Where-Object event -eq 'call')
$c = $calls | Select-Object -Last 1
if ($c) {
  Record 'profile' ($c.profile -eq $Profile) "profile=$($c.profile) hermes_home=$($c.hermes_home)"
  $want = if ($Profile -eq 'default') { $lock.cloud_model_default } else { $lock.model_default }   # default is cloud-first (P1.4)
  Record 'model' ($c.model -eq $want) "model=$($c.model) provider=$($c.provider)"
  $isLocal = $c.local -eq $true -and $c.base_url -match '^http://(localhost|127\.0\.0\.1)'
  Record 'base-url' $(if ($Profile -eq 'default') { $c.local -eq $false } else { $isLocal }) "base_url=$($c.base_url) local=$($c.local)"
  Record 'tokens-and-duration' ($null -ne $c.tokens.total -and $null -ne $c.duration) "tokens in=$($c.tokens.input) out=$($c.tokens.output) total=$($c.tokens.total) cache_read=$($c.tokens.cache_read) unaccounted=$($c.tokens.unaccounted) keys=$($c.tokens.usage_keys -join ',') duration=$($c.duration) platform=$($c.platform)"
} else { Record 'call-line' $false 'no line with event=call' }
Record 'no-cloud-in-local' (($Profile -ne 'local') -or -not (Select-String -Path $log -Pattern '"local": false' -Quiet)) "profile=$Profile"

"`n"; $results.GetEnumerator() | ForEach-Object { "{0,-30} {1}" -f $_.Key, $(if ($_.Value) {'PASS'} else {'FAIL'}) }
} finally {
  if ($LogPath) { Stop-Transcript | Out-Null }
}
