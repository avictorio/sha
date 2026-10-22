# scripts/start-gateway.ps1 -- run by the Hermes_Gateway[_private] logon tasks, as hermes (PLAN.md P0.7, P1.3).
# Installed to C:\agent\bin by installer/steps/05-telegram.ps1 and 06-private-profile.ps1.
# Safety default (CLAUDE.md): the gateway never starts without TELEGRAM_ALLOWED_USERS.
# The profile is always named (-p), so a sticky `hermes profile use` can't change what a task runs.
param([ValidateSet('default', 'private')][string]$Profile = 'default')
$root = Join-Path $env:LOCALAPPDATA 'hermes'
$home_ = if ($Profile -eq 'default') { $root } else { Join-Path $root "profiles\$Profile" }
$envFile = Join-Path $home_ '.env'
$log = Join-Path $home_ 'logs\start-gateway.log'
New-Item -ItemType Directory -Force (Split-Path $log) | Out-Null
function Log($m) { "$(Get-Date -Format o) [$Profile] $m" | Out-File -Append -Encoding utf8 $log }

$allowed = (Get-Content $envFile -ErrorAction SilentlyContinue | Where-Object { $_ -match '^\s*TELEGRAM_ALLOWED_USERS\s*=' } |
  Select-Object -Last 1) -replace '^\s*TELEGRAM_ALLOWED_USERS\s*=\s*', ''
if ($allowed -notmatch '^\s*\d') {
  Log "REFUSED: TELEGRAM_ALLOWED_USERS is not set in $envFile; gateway not started."
  exit 2
}
# A non-default profile must stay out of the default gateway (config/templates/private.config.yaml).
if ($Profile -ne 'default' -and -not (Select-String -Path (Join-Path $home_ 'config.yaml') -Pattern '^\s+standalone:\s*true\b' -Quiet)) {
  Log "REFUSED: gateway.standalone is not true in $home_\config.yaml; gateway not started."
  exit 3
}
Log "starting gateway (allowed users set)"
& (Join-Path $root 'bin\hermes.exe') -p $Profile gateway run --quiet
Log "gateway exited with $LASTEXITCODE"
exit $LASTEXITCODE
