# verify/checks/p1-3-private.ps1 -- PLAN.md P1.3: the private profile is local-only and has its own bot.
# Run in the `operator` account, ELEVATED, in a visible window: the hermes part runs AS hermes via
# scripts/invoke-as-hermes.ps1 (the owner types the password, unless -Password is passed in).
# The Done-when itself is manual, in Telegram (docs/SETUP-GUIDE.md#private-bot-tests):
#   /model openrouter:<any> fails in the private chat; with Ollama stopped the private bot errors.
# Prints PASS/FAIL per check. Re-runnable. Never prints .env values.
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
$root = 'C:\Users\hermes\AppData\Local\hermes'; $priv = "$root\profiles\private"

$cmd = @'
[Console]::OutputEncoding = [Text.Encoding]::UTF8; $env:NO_COLOR = '1'; $env:PYTHONIOENCODING = 'utf-8'; $env:COLUMNS = '200'
$h = Join-Path $env:LOCALAPPDATA 'hermes\bin\hermes.exe'
function Herm { & $h @args 2>&1 | Where-Object { "$_" -notmatch '^System\.Management\.Automation' } }
'##### model'; Herm -p private config get model
'##### fallback'; Herm -p private fallback list
'##### delegation'; Herm -p private config get delegation.fallback_providers
'##### auth'; Herm -p private auth list
'##### aux'; Herm -p private config get auxiliary | Where-Object { $_ -match 'provider:|base_url:' }
'##### honcho'; Herm -p private config get honcho
'##### tools-cli'; Herm -p private tools list
'##### tools-telegram'; Herm -p private tools list --platform telegram
'##### envnames'; (Get-ChildItem Env: | Where-Object Name -match 'KEY|TOKEN|SECRET' | ForEach-Object Name) -join ','
'##### profiles'; Herm profile list
'##### end'
'@
$args_ = @{ Command = $cmd; TimeoutSeconds = 600 }
if ($Password) { $args_.Password = $Password }
$r = & (Join-Path $repo 'scripts\invoke-as-hermes.ps1') @args_
$out = $r.Output -join "`n"
function Section($n) { if ($out -match "(?s)##### $n\s*(.*?)(?=#####|\z)") { $Matches[1].Trim() } else { '' } }

$m = Section 'model'
Record 'model-local' (($m -match "default:\s*$([regex]::Escape($lock.model_default))") -and ($m -match 'base_url:\s*http://localhost:11434/v1')) (($m -split "`n" | Select-Object -First 3) -join ' ')
Record 'no-fallback' ((Section 'fallback') -match 'No fallback providers') ''
Record 'no-delegation-fallback' ((Section 'delegation') -match '^\[\]$') (Section 'delegation')
Record 'no-auth' ([string]::IsNullOrWhiteSpace((Section 'auth'))) (Section 'auth')
$aux = Section 'aux'
Record 'aux-auto-or-local' (-not ($aux -split "`n" | Where-Object { ($_ -match 'provider:' -and $_ -notmatch 'provider:\s*(auto|custom)\s*$') -or ($_ -match "base_url:\s*'?http" -and $_ -notmatch 'localhost|127\.0\.0\.1') })) 'auto = the main (local) model first'
Record 'honcho-off' ((Section 'honcho') -match '^\{\}$') (Section 'honcho')
foreach ($pf in 'cli', 'telegram') {
  $t = Section "tools-$pf"
  $on = @('web', 'browser', 'vision', 'image_gen', 'tts' | Where-Object { $t -match "enabled\s+$_\s" -and $t -notmatch "disabled\s+$_\s" })
  Record "cloud-tools-off-$pf" ($on.Count -eq 0 -and $t -match 'disabled\s+web\s') $(if ($on) { "still on: $($on -join ',')" } else { 'web, browser, vision, image_gen, tts off' })
}
Record 'no-key-env-vars' ([string]::IsNullOrWhiteSpace((Section 'envnames'))) (Section 'envnames')

# Files and processes, read as admin (values never printed)
$envNames = @(Get-Content "$priv\.env" -ErrorAction SilentlyContinue | Where-Object { $_ -match '^\s*[A-Z_]+\s*=\s*\S' } | ForEach-Object { ($_ -split '=')[0].Trim() })
Record 'env-telegram-only' (($envNames -contains 'TELEGRAM_BOT_TOKEN') -and ($envNames -contains 'TELEGRAM_ALLOWED_USERS') -and -not ($envNames | Where-Object { $_ -match 'KEY|SECRET' -or ($_ -match 'TOKEN' -and $_ -ne 'TELEGRAM_BOT_TOKEN') })) ($envNames -join ',')
Record 'standalone' ([bool](Select-String -Path "$priv\config.yaml" -Pattern '^\s+standalone:\s*true\b' -Quiet)) ''
# Hermes drops "-p private" when it re-executes, so find the gateway under the private launcher.
$all = @(Get-CimInstance Win32_Process)
$launch = @($all | Where-Object { $_.CommandLine -match 'start-gateway\.ps1\s+-Profile\s+private\b' })
$queue = @($launch | ForEach-Object ProcessId); $tree = @()
while ($queue.Count) { $kids = @($all | Where-Object { $queue -contains $_.ParentProcessId }); $tree += $kids; $queue = @($kids | ForEach-Object ProcessId) }
$gw = @($tree | Where-Object { $_.CommandLine -match 'gateway run' })
Record 'own-gateway-process' ($gw.Count -ge 1) "$($launch.Count) launcher(s), $($gw.Count) gateway process(es) under it"
$task = Get-ScheduledTask -TaskName 'Hermes_Gateway_private' -ErrorAction SilentlyContinue
Record 'task-runs-guard' ($task -and $task.Actions[0].Arguments -match 'start-gateway\.ps1 -Profile private') "$($task.State)"
$conn = Get-Content "$priv\logs\gateway.log" -Tail 300 -ErrorAction SilentlyContinue | Where-Object { $_ -match 'telegram connected' } | Select-Object -Last 1
Record 'telegram-connected' ([bool]$conn) ($conn -replace '\d{6,12}:[A-Za-z0-9_-]{30,}', '<token>')
$cloud = Select-String -Path 'C:\agent\shared\logs\usage-private.jsonl' -Pattern '"local": false' -ErrorAction SilentlyContinue
Record 'usage-private-all-local' (-not $cloud) "$(@($cloud).Count) non-local line(s)"

"`n"; $results.GetEnumerator() | ForEach-Object { "{0,-30} {1}" -f $_.Key, $(if ($_.Value) {'PASS'} else {'FAIL'}) }
