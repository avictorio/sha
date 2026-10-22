# scripts/seed-user-memory.ps1 -- PLAN.md P1.6: put a filled-in USER.md (from config/templates/USER.default.md,
# kept OUTSIDE the repo: it holds personal data) into a profile's memories folder, as hermes.
# Run from the `operator` account in an ELEVATED Windows PowerShell, in a visible window; the owner types the
# hermes password. Only cloud-OK facts go into the default profile (F2). Refuses to overwrite an existing
# USER.md unless -Force (the old one is kept as USER.md.bak-<time>).
param([Parameter(Mandatory)][string]$FromFile, [ValidateSet('default', 'private')][string]$Profile = 'default', [switch]$Force,
      [string]$LogPath)
$ErrorActionPreference = 'Stop'
if ($LogPath) { Start-Transcript -Path $LogPath -Force | Out-Null }
$repo = Split-Path $PSScriptRoot
if ($env:USERNAME -ne 'operator') { throw "Not running as 'operator' (got '$env:USERNAME')." }
if ((Resolve-Path $FromFile).Path -like "$repo\*") { throw "Keep the filled-in file outside the repo (it holds personal data)." }
$text = (Get-Content $FromFile -Raw -Encoding UTF8) -replace '(?s)<!--.*?-->', ''
$text = $text.Trim()
if ($text -match '<[^>]+>') { throw "The file still has <placeholders>; fill them in or delete those lines." }
# Hermes's memory files are plain text; pass the content as base64 so no quoting can break it.
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($text))
$dir = if ($Profile -eq 'default') { '$env:LOCALAPPDATA\hermes\memories' } else { "`$env:LOCALAPPDATA\hermes\profiles\$Profile\memories" }
$forceLit = if ($Force) { '$true' } else { '$false' }
$r = & (Join-Path $PSScriptRoot 'invoke-as-hermes.ps1') -Command @"
`$d = "$dir"; New-Item -ItemType Directory -Force `$d | Out-Null
`$f = Join-Path `$d 'USER.md'
if ((Test-Path `$f) -and -not $forceLit) { 'EXISTS'; return }
if (Test-Path `$f) { Copy-Item `$f "`$f.bak-`$(Get-Date -Format yyyyMMdd-HHmmss)" }
[IO.File]::WriteAllText(`$f, [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$b64')), (New-Object Text.UTF8Encoding `$false))
"WROTE `$((Get-Item `$f).Length) bytes"
"@
$r.Output | ForEach-Object { Write-Host "  $_" }
if ($r.Output -contains 'EXISTS') { Write-Host "USER.md already exists in '$Profile'; rerun with -Force to replace it." -ForegroundColor Yellow }
if ($LogPath) { Stop-Transcript | Out-Null }
