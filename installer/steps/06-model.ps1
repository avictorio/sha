# installer/steps/06-model.ps1 -- PLAN.md P1.2: set the D2 model (versions.lock model_default) as
# Hermes's model.default, restart the Telegram gateway cleanly, then run verify/checks/p1-2-model.ps1.
# Run from the `operator` account in an ELEVATED Windows PowerShell, in a visible window: the owner
# types the hermes password once, at the hidden prompt. Re-runnable.
param([string]$LogPath)

$ErrorActionPreference = 'Stop'
if ($LogPath) { Start-Transcript -Path $LogPath -Force | Out-Null }
function Step($msg) { Write-Host "`n== $msg" -ForegroundColor Cyan }

$repo = Split-Path (Split-Path $PSScriptRoot)
$lock = ConvertFrom-StringData ((Get-Content (Join-Path $repo 'versions.lock') | Where-Object { $_ -notmatch '^\s*#' }) -join "`n")
$tag = $lock.model_default
if ($env:USERNAME -ne 'operator') { throw "Not running as 'operator' (got '$env:USERNAME'). Stop: CLAUDE.md rule 1." }
$p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw "Run this elevated (Run as administrator)." }
if ($tag -notmatch '^[\w.:-]+$') { throw "versions.lock model_default '$tag' doesn't look like an Ollama tag." }

try {
  Step "Check that Ollama has $tag with at least 64K native context"
  $show = Invoke-RestMethod -Method Post http://127.0.0.1:11434/api/show -ContentType application/json -Body (@{ model = $tag } | ConvertTo-Json)
  $ctx = ($show.model_info.PSObject.Properties | Where-Object Name -like '*.context_length' | Select-Object -First 1).Value
  if ($ctx -lt 65536) { throw "$tag has native context $ctx; P1.2 needs at least 65536." }
  Write-Host "native context $ctx"

  Write-Host "Type the hermes password (hidden):" -ForegroundColor Yellow
  $pw = Read-Host -AsSecureString "hermes password"

  Step "Set model.default = $tag (as hermes)"
  $r = & (Join-Path $repo 'scripts\invoke-as-hermes.ps1') -Password $pw -Command @"
`$h = Join-Path `$env:LOCALAPPDATA 'hermes\bin\hermes.exe'
& `$h config set model.default '$tag' 2>&1
"MODEL=`$((& `$h config get model.default 2>&1) -join '')"
"@
  $r.Output | ForEach-Object { Write-Host "  $_" }
  if (($r.Output | Where-Object { $_ -like 'MODEL=*' }) -ne "MODEL=$tag") { throw "model.default didn't read back as $tag; gateway not restarted." }

  Step "Restart the Telegram gateways cleanly (both profiles use model_default)"
  & (Join-Path $repo 'scripts\restart-gateway.ps1') -Profile default
  & (Join-Path $repo 'scripts\restart-gateway.ps1') -Profile local

  Step "Check (verify/checks/p1-2-model.ps1)"
  & (Join-Path $repo 'verify\checks\p1-2-model.ps1') -Password $pw
} finally {
  if ($LogPath) { Stop-Transcript | Out-Null }
}
