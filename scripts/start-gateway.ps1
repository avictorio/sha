# scripts/start-gateway.ps1 -- run by the Hermes_Gateway logon task, as hermes (PLAN.md P0.7).
# Installed to C:\agent\bin by installer/steps/05-telegram.ps1.
# Safety default (CLAUDE.md): the gateway never starts without TELEGRAM_ALLOWED_USERS.
$envFile = Join-Path $env:LOCALAPPDATA 'hermes\.env'
$log = Join-Path $env:LOCALAPPDATA 'hermes\logs\start-gateway.log'
function Log($m) { "$(Get-Date -Format o) $m" | Out-File -Append -Encoding utf8 $log }

$allowed = (Get-Content $envFile -ErrorAction SilentlyContinue | Where-Object { $_ -match '^\s*TELEGRAM_ALLOWED_USERS\s*=' } |
  Select-Object -Last 1) -replace '^\s*TELEGRAM_ALLOWED_USERS\s*=\s*', ''
if ($allowed -notmatch '^\s*\d') {
  Log "REFUSED: TELEGRAM_ALLOWED_USERS is not set in $envFile; gateway not started."
  exit 2
}
Log "starting gateway (allowed users set)"
& (Join-Path $env:LOCALAPPDATA 'hermes\bin\hermes.exe') gateway run --quiet
Log "gateway exited with $LASTEXITCODE"
exit $LASTEXITCODE
