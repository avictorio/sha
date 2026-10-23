# bench/run-bench.ps1 -- drives the P1.1 benchmark from `operator`, ELEVATED, in a visible window.
# Stages fixtures, the B4 document, the B2 holdout files and bench/runner.ps1 into a folder hermes can
# read but not change (never inside C:\agent\workspace, which the sandbox sees), then runs runner.ps1
# AS hermes through scripts/invoke-as-hermes.ps1 (the owner types the password once).
#   -Prepare: online pre-checks only.
#   -Run:     bench/isolate.ps1 -On, every run, then -Off (always, in finally).
#   -Run -Cloud: the cloud model (versions.lock cloud_model_default) instead of the local candidates, for
#             comparison only (not a D2 candidate). Hermes must reach OpenRouter, so only the sandbox is cut
#             off (isolate.ps1 -SandboxOnly) and each turn runs without the web and browser toolsets; the
#             runner checks both, logs the key's spend per run, and flags any run that fell back to local.
# Results: C:\agent\bench-results\<stamp>\ (not mounted into the sandbox). Score them with the answer keys.
param([switch]$Prepare, [switch]$Run, [switch]$Cloud, [Parameter(Mandatory)][string]$Doc, [string]$LogPath,
      [string[]]$Tasks = @('B1', 'B2', 'B3', 'B4', 'B5', 'B6', 'B7'), [int]$Runs = 3,
      [string]$ResumeFlag = '--resume',   # a default: PS reads "-ResumeFlag --resume" on the command line as a missing value
      [string]$Models,                     # comma-separated tags; default: model_candidates in versions.lock
      [int]$ChatTimeoutSec = 1200,         # per hermes chat turn; raise it for slow models
      [int]$TimeoutSeconds = 36000)        # the whole runner
$ErrorActionPreference = 'Stop'
if ($Prepare -eq $Run) { throw "Use exactly one of -Prepare or -Run." }
$Tasks = $Tasks -split ','   # powershell -File passes "-Tasks B2,B6" as one string
# A click in this window starts a selection (QuickEdit), which freezes the script at its next write: the
# runner carries on as hermes, but isolate.ps1 -Off never runs. Turn QuickEdit off for this console.
Add-Type -Namespace Bench -Name Con -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int h);
[DllImport("kernel32.dll")] public static extern bool GetConsoleMode(IntPtr h, out uint m);
[DllImport("kernel32.dll")] public static extern bool SetConsoleMode(IntPtr h, uint m);
'@
$in = [Bench.Con]::GetStdHandle(-10); $mode = 0
if ([Bench.Con]::GetConsoleMode($in, [ref]$mode)) { [void][Bench.Con]::SetConsoleMode($in, ($mode -band (-bnot 0x40)) -bor 0x80) }
if ($LogPath) { Start-Transcript -Path $LogPath -Force | Out-Null }
$repo = Split-Path $PSScriptRoot
$lock = ConvertFrom-StringData ((Get-Content (Join-Path $repo 'versions.lock') | Where-Object { $_ -notmatch '^\s*#' }) -join "`n")
if ($Cloud -and $Prepare) { throw "-Cloud goes with -Run only." }
$candidates = if ($Models) { $Models -split ',' } elseif ($Cloud) { @($lock.cloud_model_default) } else { $lock.model_candidates -split ',' }
function Say($m) { Write-Host "$(Get-Date -Format HH:mm:ss) $m" -ForegroundColor Cyan }
Say "P1.1 benchmark, $(if ($Prepare) { 'pre-checks' } else { 'full run' }); candidates: $($candidates -join ', ')"
Get-ChildItem $env:PUBLIC -Directory -Filter 'hermes-bench-*' -ErrorAction SilentlyContinue |
  ForEach-Object { Remove-Item $_.FullName -Recurse -Force; Say "removed leftover $($_.Name)" }
Say "checking the B4 document"
$key =Get-Content (Join-Path $repo 'bench\answer_keys\b4_questions.json') -Raw | ConvertFrom-Json
if ((Get-FileHash $Doc -Algorithm SHA256).Hash -ne $key.document.sha256) { throw "B4 document hash differs from b4_questions.json." }

$stage = Join-Path $env:PUBLIC ('hermes-bench-' + [guid]::NewGuid().ToString('N'))
$results = 'C:\agent\bench-results\' + (Get-Date -Format 'yyyyMMdd-HHmmss') + $(if ($Prepare) { '-prepare' } else { '' })
try {
  Say "staging fixtures and runner in $stage"
  New-Item -ItemType Directory $stage | Out-Null
  icacls $stage /inheritance:r /grant:r "hermes:(OI)(CI)RX" "SYSTEM:(OI)(CI)F" "Administrators:(OI)(CI)F" | Out-Null
  Copy-Item -Recurse (Join-Path $repo 'bench\fixtures') "$stage\fixtures"
  New-Item -ItemType Directory "$stage\b4", "$stage\holdout" | Out-Null
  Copy-Item $Doc "$stage\b4\doc.txt"
  Copy-Item (Join-Path $repo 'bench\answer_keys\b2_holdout_*') "$stage\holdout\"   # used only after the turn, via docker cp
  Copy-Item (Join-Path $repo 'bench\runner.ps1') "$stage\runner.ps1"

  if ($Run -and $Cloud) { Say "cutting the sandbox off from the network (Hermes keeps OpenRouter)"; & (Join-Path $repo 'bench\isolate.ps1') -On -SandboxOnly }
  elseif ($Run) { Say "isolating Hermes from the network"; & (Join-Path $repo 'bench\isolate.ps1') -On }
  try {
    $mode = if ($Prepare) { 'Prepare' } else { 'Run' }
    $cmd = "& '$stage\runner.ps1' -Mode $mode -Stage '$stage' -Results '$results' -Candidates '$($candidates -join "','")' " +
           "-Tasks '$($Tasks -join "','")' -Runs $Runs -ChatTimeoutSec $ChatTimeoutSec" + $(if ($ResumeFlag) { " -ResumeFlag '$ResumeFlag'" } else { '' }) +
           $(if ($Cloud) { ' -Cloud' } else { '' })
    Say "results will be in $results"
    Say "starting the runner as hermes: type the hermes password at the prompt below. Then this window stays quiet while it works ($(if ($Prepare) { 'about 5 minutes' } else { 'several hours' })); don't close it."
    $r =& (Join-Path $repo 'scripts\invoke-as-hermes.ps1') -Command $cmd -TimeoutSeconds $TimeoutSeconds
    $r.Output | Select-Object -Last 40 | ForEach-Object { Write-Host "  $_" }
    if ($r.TimedOut) { Write-Host ("runner timed out (task result 0x{0:X8})" -f $r.TaskResult) -ForegroundColor Red }
  } finally {
    if ($Run) { & (Join-Path $repo 'bench\isolate.ps1') -Off }
  }
} finally {
  Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
  Write-Host "results: $results"
  if ($LogPath) { Stop-Transcript | Out-Null }
}
