# verify/checks/p1-2-model.ps1 -- PLAN.md P1.2: Hermes runs the D2 model (versions.lock model_default).
# Run in the `operator` account, ELEVATED, in a visible window: the hermes part runs AS hermes via
# scripts/invoke-as-hermes.ps1 (the owner types the password, unless -Password is passed in).
# Checks: model.default is the D2 tag; `hermes doctor` has no failures; `hermes chat` answers; and
# Ollama serves the tag with a 65536 context. Prints PASS/FAIL per check. Re-runnable.
param([securestring]$Password, [string]$LogPath)
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
$tag = $lock.model_default

$cmd = @'
[Console]::OutputEncoding = [Text.Encoding]::UTF8; $OutputEncoding = [Text.Encoding]::UTF8
$env:NO_COLOR = '1'; $env:PYTHONIOENCODING = 'utf-8'; $env:PYTHONUTF8 = '1'
$h = Join-Path $env:LOCALAPPDATA 'hermes\bin\hermes.exe'
"##### model"
& $h config get model.default 2>&1
"##### doctor"
& $h doctor 2>&1
"##### chat"
& $h chat -Q -q 'Reply with exactly the word PONG and nothing else.' 2>&1 | Where-Object { "$_" -notmatch '^System\.Management\.Automation' } | Select-Object -Last 5
'@
$args_ = @{ Command = $cmd; TimeoutSeconds = 600 }
if ($Password) { $args_.Password = $Password }
$r = & (Join-Path $repo 'scripts\invoke-as-hermes.ps1') @args_
$out = $r.Output -join "`n"
function Section($n) { if ($out -match "(?s)##### $n\s*(.*?)(?=#####|\z)") { $Matches[1].Trim() } else { '' } }

$model = (Section 'model') -split "`n" | Select-Object -Last 1
Record 'model-default' ($model.Trim() -eq $tag) "config=$($model.Trim()) want=$tag"
$doc = Section 'doctor'
# Same rule as p0-6: readable (several check marks) and no failure marks; warnings are allowed.
$nOk = @($doc -split "`n" | Where-Object { $_ -match [char]0x2713 }).Count
$fails = @($doc -split "`n" | Where-Object { $_ -match "[$([char]0x2717)$([char]0x2718)]" })
Record 'doctor-clean' (($nOk -gt 5) -and $fails.Count -eq 0) $(if ($fails) { ($fails | Select-Object -First 3) -join ' | ' } else { "$nOk ok" })
Record 'chat-answers' ((Section 'chat') -match 'PONG') ((Section 'chat') -replace 'session_id:\s*\S+', '' -replace '\s+', ' ').Trim()
try {
  $m = (Invoke-RestMethod http://127.0.0.1:11434/api/ps -TimeoutSec 10).models | Where-Object name -eq $tag
  Record 'ollama-ctx-65536' ($m -and $m.context_length -eq 65536) "loaded=$([bool]$m) context=$($m.context_length)"
} catch { Record 'ollama-ctx-65536' $false "api/ps failed: $($_.Exception.Message)" }

"`n"; $results.GetEnumerator() | ForEach-Object { "{0,-30} {1}" -f $_.Key, $(if ($_.Value) {'PASS'} else {'FAIL'}) }
} finally {
  if ($LogPath) { Stop-Transcript | Out-Null }
}
