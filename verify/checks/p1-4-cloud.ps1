# verify/checks/p1-4-cloud.ps1 -- PLAN.md P1.4: the default profile is cloud-first (D9) and falls back to the
# local model; the local profile still has no cloud credentials.
# Run in the `operator` account, ELEVATED, in a visible window: the hermes part runs AS hermes via
# scripts/invoke-as-hermes.ps1 (the owner types the password, unless -Password is passed in).
#   - a cloud chat: answered, and logged with the cloud model and "local": false;
#   - a forced cloud failure: model.default is set to a model that doesn't exist (404), a chat must still
#     answer through the local fallback ("local": true); config.yaml is restored from its backup afterwards;
#   - local: no OPENROUTER entry in its .env, no non-local line in usage-local.
# The Telegram half (the default bot answers from the cloud) is in docs/SETUP-GUIDE.md#openrouter.
# Prints PASS/FAIL per check. Never prints .env values. Re-runnable.
param([securestring]$Password)
$ErrorActionPreference = 'Continue'
$results = [ordered]@{}
function Record($name, $ok, $detail) {
  $results[$name] = $ok
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("[{0}] {1}  {2}" -f ($(if ($ok) {'PASS'} else {'FAIL'})), $name, $detail) -ForegroundColor $c
}
if ($env:USERNAME -ne 'operator') { throw "Not running as 'operator' (got '$env:USERNAME')." }
$repo = Split-Path (Split-Path $PSScriptRoot)
$lock = ConvertFrom-StringData ((Get-Content (Join-Path $repo 'versions.lock') | Where-Object { $_ -notmatch '^\s*#' }) -join "`n")
$root = 'C:\Users\hermes\AppData\Local\hermes'
$log = 'C:\agent\shared\logs\usage-default.jsonl'
$before = if (Test-Path $log) { @(Get-Content $log).Count } else { 0 }

$cmd = @'
[Console]::OutputEncoding = [Text.Encoding]::UTF8; $env:NO_COLOR = '1'; $env:PYTHONIOENCODING = 'utf-8'; $env:COLUMNS = '200'
$h = Join-Path $env:LOCALAPPDATA 'hermes\bin\hermes.exe'
function Herm { & $h @args 2>&1 | Where-Object { "$_" -notmatch '^System\.Management\.Automation' -and "$_" -notmatch 'sk-or-' } }
'##### model'; Herm config get model
'##### fallback'; Herm fallback list
'##### usage'; Herm usage --provider openrouter | Select-Object -First 20
'##### chat-cloud'; Herm chat -Q -q 'Reply with exactly the word PONG and nothing else.' | Select-Object -Last 5
'##### chat-fallback'
$cfg = Join-Path $env:LOCALAPPDATA 'hermes\config.yaml'
$bak = "$cfg.p14-check.bak"; Copy-Item $cfg $bak -Force
try {
  Herm config set model.default meta/p14-no-such-model | Out-Null
  Herm chat -Q -q 'Reply with exactly the word PONG and nothing else.' | Select-Object -Last 8
} finally {
  Copy-Item $bak $cfg -Force; Remove-Item $bak -Force
  "##### restored"; Herm config get model.default
}
'##### end'
'@
$args_ = @{ Command = $cmd; TimeoutSeconds = 900 }
if ($Password) { $args_.Password = $Password }
$r = & (Join-Path $repo 'scripts\invoke-as-hermes.ps1') @args_
$out = $r.Output -join "`n"
function Section($n) { if ($out -match "(?s)##### $n\s*(.*?)(?=#####|\z)") { $Matches[1].Trim() } else { '' } }
Write-Host "--- usage --provider openrouter (verify)`n$(Section 'usage')"
Write-Host "--- fallback chat`n$(Section 'chat-fallback')"

$m = Section 'model'
Record 'model-cloud' (($m -match "default:\s*$([regex]::Escape($lock.cloud_model_default))") -and ($m -match 'provider:\s*openrouter')) (($m -split "`n" | Select-Object -First 3) -join ' ')
$fb = Section 'fallback'
Record 'fallback-local' (($fb -match [regex]::Escape($lock.model_default)) -and ($fb -match 'localhost:11434|custom')) (($fb -split "`n" | Where-Object { $_ -match '\S' } | Select-Object -First 3) -join ' | ')
Record 'restored' ((Section 'restored') -eq $lock.cloud_model_default) "model.default=$(Section 'restored')"
Record 'chat-cloud-answers' ((Section 'chat-cloud') -match 'PONG') ''
Record 'chat-fallback-answers' ((Section 'chat-fallback') -match 'PONG') ''

$new = if (Test-Path $log) { @(Get-Content $log -Encoding UTF8 | Select-Object -Skip $before) } else { @() }
$calls = @($new | ForEach-Object { try { $_ | ConvertFrom-Json } catch { } } | Where-Object event -eq 'call')
$cloud = @($calls | Where-Object { $_.local -eq $false -and $_.model -eq $lock.cloud_model_default })
$local = @($calls | Where-Object { $_.local -eq $true -and $_.model -eq $lock.model_default })
$c = $cloud | Select-Object -Last 1
Record 'logged-cloud-call' ($cloud.Count -ge 1) "$($cloud.Count) line(s); last: provider=$($c.provider) base_url=$($c.base_url) tokens=$($c.tokens.input)/$($c.tokens.output)"
Record 'logged-fallback-local' ($local.Count -ge 1) "$($local.Count) local line(s) of $($calls.Count) call line(s)"
$errs = @($new | ForEach-Object { try { $_ | ConvertFrom-Json } catch { } } | Where-Object event -ne 'call')
if ($errs) { Write-Host "  non-call events: $(($errs | ForEach-Object { "$($_.event) model=$($_.model)" }) -join '; ')" }

$localEnv = "$root\profiles\local\.env"
Record 'local-no-openrouter' (-not (Select-String -Path $localEnv -Pattern 'OPENROUTER|sk-or-' -Quiet -ErrorAction SilentlyContinue)) ''
Record 'local-all-local' (-not (Select-String -Path 'C:\agent\shared\logs\usage-local.jsonl' -Pattern '"local": false' -Quiet -ErrorAction SilentlyContinue)) ''

"`n"; $results.GetEnumerator() | ForEach-Object { "{0,-30} {1}" -f $_.Key, $(if ($_.Value) {'PASS'} else {'FAIL'}) }
