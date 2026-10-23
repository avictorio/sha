# verify/checks/s3-cron-help.ps1 -- PLAN.md S3, step 0: print `hermes cron` help and each profile's jobs, so the
# spike uses real flags. Read-only. Run in the `operator` account, ELEVATED; the owner types the hermes password.
param([securestring]$Password)
$ErrorActionPreference = 'Continue'
if ($env:USERNAME -ne 'operator') { throw "Not running as 'operator' (got '$env:USERNAME')." }
$repo = Split-Path (Split-Path $PSScriptRoot)
$cmd = @'
[Console]::OutputEncoding = [Text.Encoding]::UTF8; $env:NO_COLOR = '1'; $env:PYTHONIOENCODING = 'utf-8'; $env:COLUMNS = '200'
$h = Join-Path $env:LOCALAPPDATA 'hermes\bin\hermes.exe'
function Herm { & $h @args 2>&1 | Where-Object { "$_" -notmatch '^System\.Management\.Automation' -and "$_" -notmatch 'sk-or-|\d{6,12}:[A-Za-z0-9_-]{30,}' } }
foreach ($a in @('cron','--help'), @('cron','create','--help'), @('cron','run','--help'), @('cron','runs','--help'), @('cron','remove','--help'), @('cron','list'), @('-p','private','cron','list'), @('cron','status'), @('config','get','cron'), @('config','get','providers')) {
  "##### $($a -join ' ')"; Herm @a | Select-Object -First 70
}
'@
$args_ = @{ Command = $cmd; TimeoutSeconds = 600 }
if ($Password) { $args_.Password = $Password }
$r = & (Join-Path $repo 'scripts\invoke-as-hermes.ps1') @args_
$r.Output | ForEach-Object { Write-Host "  $_" }
