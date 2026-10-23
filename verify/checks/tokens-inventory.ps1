# verify/checks/tokens-inventory.ps1 -- what each default-profile request carries (token diet, after P1.8).
# Read-only. Run in the `operator` account, ELEVATED; the owner types the hermes password (unless -Password).
# Prints: enabled tools per platform, installed skills, auxiliary routing, compression, session reset and
# prompt-caching settings, plus the commands' help where the setting names aren't known yet.
param([securestring]$Password, [string]$LogPath)
$ErrorActionPreference = 'Continue'
if ($LogPath) { Start-Transcript -Path $LogPath -Force | Out-Null }
try {
if ($env:USERNAME -ne 'operator') { throw "Not running as 'operator' (got '$env:USERNAME')." }
$repo = Split-Path (Split-Path $PSScriptRoot)
$cmd = @'
[Console]::OutputEncoding = [Text.Encoding]::UTF8; $env:NO_COLOR = '1'; $env:PYTHONIOENCODING = 'utf-8'; $env:COLUMNS = '200'
$h = Join-Path $env:LOCALAPPDATA 'hermes\bin\hermes.exe'
function Cap([string]$argline, [int]$sec = 90) {
  $o = [IO.Path]::GetTempFileName(); $e = [IO.Path]::GetTempFileName(); $i = [IO.Path]::GetTempFileName()
  $p = Start-Process $h -ArgumentList $argline -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError $e -RedirectStandardInput $i
  if (-not $p.WaitForExit($sec * 1000)) { taskkill /PID $p.Id /T /F 2>&1 | Out-Null; "TIMEOUT after ${sec}s: hermes $argline" }
  Get-Content $o, $e -Encoding UTF8 | Where-Object { "$_" -notmatch 'sk-or-|\d{6,12}:[A-Za-z0-9_-]{30,}' }
  Remove-Item $o, $e, $i -Force -ErrorAction SilentlyContinue
}
foreach ($a in 'tools list --platform telegram', 'tools list --platform cli', 'tools --help', 'skills --help', 'skills list',
               'config get auxiliary', 'config get compression', 'config get prompt_caching', 'config get session_reset',
               'config get gateway', 'config get skills', 'config get agent', 'config get memory') {
  "##### $a"; Cap $a | Select-Object -First 120
}
$cfg = Join-Path $env:LOCALAPPDATA 'hermes\config.yaml'
'##### config.yaml lines mentioning reset / idle / review / cache'
Select-String -Path $cfg -Pattern '(?i)reset|idle|review|cache|nudge' | Select-Object -First 50 | ForEach-Object { "{0}: {1}" -f $_.LineNumber, $_.Line }
'##### end'
'@
$args_ = @{ Command = $cmd; TimeoutSeconds = 1200 }
if ($Password) { $args_.Password = $Password }
$r = & (Join-Path $repo 'scripts\invoke-as-hermes.ps1') @args_
Write-Host "hermes step: TimedOut=$($r.TimedOut) ExitCode=$($r.ExitCode)"
$r.Output | ForEach-Object { Write-Host "  $_" }
} finally {
  if ($LogPath) { Stop-Transcript | Out-Null }
}
