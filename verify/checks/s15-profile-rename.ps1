# verify/checks/s15-profile-rename.ps1 -- PLAN.md S15: can Hermes rename a profile in place? Read-only.
# Run in the `operator` account, ELEVATED, in a visible window (the owner types the hermes password).
# Prints `hermes profile --help`, the help of any rename-like subcommand, and `hermes profile list`.
param([securestring]$Password)
$ErrorActionPreference = 'Continue'
if ($env:USERNAME -ne 'operator') { throw "Not running as 'operator' (got '$env:USERNAME')." }
$repo = Split-Path (Split-Path $PSScriptRoot)
$cmd = @'
[Console]::OutputEncoding = [Text.Encoding]::UTF8; $env:NO_COLOR = '1'; $env:PYTHONIOENCODING = 'utf-8'; $env:COLUMNS = '200'
$h = Join-Path $env:LOCALAPPDATA 'hermes\bin\hermes.exe'
function Cap([string]$argline, [int]$sec = 90) {
  $o = [IO.Path]::GetTempFileName(); $e = [IO.Path]::GetTempFileName(); $i = [IO.Path]::GetTempFileName()
  $p = Start-Process $h -ArgumentList $argline -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError $e -RedirectStandardInput $i
  if (-not $p.WaitForExit($sec * 1000)) { taskkill /PID $p.Id /T /F 2>&1 | Out-Null; "TIMEOUT after ${sec}s: hermes $argline" }
  Get-Content $o, $e -Encoding UTF8
  Remove-Item $o, $e, $i -Force -ErrorAction SilentlyContinue
}
'##### profile --help'; $help = @(Cap 'profile --help'); $help
$subs = ($help -join ' ') -replace '[{}]', ' ' -split '[\s,]+' | Where-Object { $_ -match '^(rename|mv|move|copy|clone|export|import)$' } | Sort-Object -Unique
foreach ($s in $subs) { "##### profile $s --help"; Cap "profile $s --help" }
'##### profile list'; Cap 'profile list'
'##### profile create --help'; Cap 'profile create --help'
'##### end'
'@
$args_ = @{ Command = $cmd; TimeoutSeconds = 600 }
if ($Password) { $args_.Password = $Password }
$r = & (Join-Path $repo 'scripts\invoke-as-hermes.ps1') @args_
Write-Host "hermes step: TimedOut=$($r.TimedOut) ExitCode=$($r.ExitCode)"
$r.Output | ForEach-Object { Write-Host "  $_" }
