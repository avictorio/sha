# verify/checks/s4-backup-profiles.ps1 -- PLAN.md S4: does `hermes backup` cover all profiles?
# Run in the `operator` account, ELEVATED, in a visible window; the owner types the hermes password.
# As hermes: makes a test archive in C:\agent\backup-stage, lists what's in it (names only), then DELETES it
# (it holds .env and auth.json). Prints the exit code and whether profiles\private\ and the key files are inside.
param([securestring]$Password)
$ErrorActionPreference = 'Continue'
if ($env:USERNAME -ne 'operator') { throw "Not running as 'operator' (got '$env:USERNAME')." }
$repo = Split-Path (Split-Path $PSScriptRoot)
$cmd = @'
[Console]::OutputEncoding = [Text.Encoding]::UTF8; $env:NO_COLOR = '1'; $env:PYTHONIOENCODING = 'utf-8'; $env:COLUMNS = '200'
$h = Join-Path $env:LOCALAPPDATA 'hermes\bin\hermes.exe'
$stage = 'C:\agent\backup-stage'; New-Item -ItemType Directory -Force $stage | Out-Null
$zip = Join-Path $stage 's4-test.zip'
'##### help'; & $h backup --help 2>&1 | Select-Object -First 30
try {
  '##### run'; & $h backup -o $zip 2>&1 | Select-Object -Last 8; "BACKUPRC=$LASTEXITCODE"
  if (Test-Path $zip) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $z = [IO.Compression.ZipFile]::OpenRead($zip)
    try {
      $names = @($z.Entries | ForEach-Object FullName)
      "SIZE_MB=$([math]::Round((Get-Item $zip).Length / 1MB, 1)) ENTRIES=$($names.Count)"
      '##### top-level'
      $names | ForEach-Object { $p = ($_ -replace '\\', '/') -split '/'; if ($p.Count -gt 2) { "$($p[0])/$($p[1])/" } else { $_ -replace '\\', '/' } } | Sort-Object -Unique | Select-Object -First 60
      '##### checks'
      foreach ($pat in 'profiles/private/', 'profiles/private/config.yaml', 'profiles/private/state.db', 'profiles/private/memories', 'config.yaml', 'state.db', 'memories/USER.md', '.env', 'auth.json', 'plugins/usage-log') {
        $hit = @($names | Where-Object { ($_ -replace '\\', '/') -match "(^|/)$([regex]::Escape($pat))" }).Count
        "HAS $pat = $hit"
      }
    } finally { $z.Dispose() }
  } else { 'NOZIP' }
} finally {
  Remove-Item $zip -Force -ErrorAction SilentlyContinue
  "DELETED=$(-not (Test-Path $zip))"
}
'@
$args_ = @{ Command = $cmd; TimeoutSeconds = 900 }
if ($Password) { $args_.Password = $Password }
$r = & (Join-Path $repo 'scripts\invoke-as-hermes.ps1') @args_
$r.Output | Where-Object { $_ -notmatch 'sk-or-|\d{6,12}:[A-Za-z0-9_-]{30,}' } | ForEach-Object { Write-Host "  $_" }
