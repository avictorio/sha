# installer/steps/03-docker.ps1 -- PLAN.md P0.5: Docker Desktop (WSL 2 backend).
# Run from the `operator` account in an ELEVATED Windows PowerShell. Idempotent: safe to re-run.
# A reboot is needed after the first run (WSL). The autostart setting and first launch happen
# in the owner's one sign-in as `hermes`: see docs/SETUP-GUIDE.md#docker-autostart.
param([string]$LogPath)

$ErrorActionPreference = 'Stop'
if ($LogPath) { Start-Transcript -Path $LogPath -Force | Out-Null }
function Step($msg) { Write-Host "`n== $msg" -ForegroundColor Cyan }

$repo = Split-Path (Split-Path $PSScriptRoot)
$lock = ConvertFrom-StringData ((Get-Content (Join-Path $repo 'versions.lock') |
  Where-Object { $_ -notmatch '^\s*#' }) -join "`n")

if ($env:USERNAME -ne 'operator') { throw "Not running as 'operator' (got '$env:USERNAME'). Stop: CLAUDE.md rule 1." }
$p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw "Run this elevated (Run as administrator)." }

# --- WSL 2 (no distribution; Docker Desktop brings its own) ---------------------
Step "WSL"
$ErrorActionPreference = 'Continue'   # wsl.exe writes UTF-16 to stdout/stderr; judge by exit code
$status = (wsl.exe --status 2>&1 | ForEach-Object { "$_" -replace "`0", '' }) -join ' '
if ($status -match 'not installed') {
  wsl.exe --install --no-distribution
  if ($LASTEXITCODE -ne 0) { throw "wsl --install failed ($LASTEXITCODE)" }
  Write-Host "WSL installed; a reboot is needed before Docker Desktop can start." -ForegroundColor Yellow
} else {
  wsl.exe --update
  Write-Host "WSL present"
}
$ErrorActionPreference = 'Stop'

# --- Docker Desktop -------------------------------------------------------------
Step "Docker Desktop $($lock.docker_desktop_version)"
$dd = Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
if (Test-Path $dd) {
  Write-Host "already installed: $((Get-Item $dd).VersionInfo.ProductVersion)"
} else {
  winget install --id Docker.DockerDesktop -e --source winget --version $lock.docker_desktop_version `
    --scope machine --accept-package-agreements --accept-source-agreements
  if ($LASTEXITCODE -ne 0) { throw "winget install Docker.DockerDesktop failed ($LASTEXITCODE)" }
}

# --- hermes in docker-users -----------------------------------------------------
Step "docker-users"
if (-not (Get-LocalGroup docker-users -ErrorAction SilentlyContinue)) { throw "docker-users group missing (Docker Desktop install incomplete?)" }
if (Get-LocalGroupMember docker-users | Where-Object Name -like '*\hermes') {
  Write-Host "hermes already in docker-users"
} else {
  net localgroup docker-users hermes /add
  if ($LASTEXITCODE -ne 0) { throw "net localgroup failed" }
}
Get-LocalGroupMember docker-users | Format-Table Name -AutoSize

Step "Done (next: reboot, then the owner's hermes sign-in)"
if ($LogPath) { Stop-Transcript | Out-Null }
