# verify/checks/p0-5-docker.ps1 -- PLAN.md P0.5 (Docker Desktop) checks
# Run in the `operator` account, in an ELEVATED Windows PowerShell, after an unattended reboot
# (hermes signed in by itself, so Docker Desktop has autostarted in its session).
# The docker commands run AS hermes via scripts/invoke-as-hermes.ps1: the owner types
# hermes's password at its hidden prompt (CLAUDE.md rule 1). Prints PASS/FAIL per check.
# -SandboxImage: the image from `hermes config get terminal.docker_image` (known after P0.6).
param([string]$SandboxImage, [string]$LogPath)

$ErrorActionPreference = 'Continue'
if ($LogPath) { Start-Transcript -Path $LogPath -Force | Out-Null }
try {
$results = [ordered]@{}
function Step($m) { Write-Host "`n== $m" -ForegroundColor Cyan }
function Record($name, $ok, $detail) {
  $results[$name] = $ok
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("[{0}] {1}  {2}" -f ($(if ($ok) {'PASS'} else {'FAIL'})), $name, $detail) -ForegroundColor $c
}
if ($env:USERNAME -ne 'operator') { throw "Not running as 'operator' (got '$env:USERNAME')." }
$repo = Split-Path (Split-Path $PSScriptRoot)

# --- Install state ---
Step "Install"
$dd = Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
Record 'docker-desktop-installed' (Test-Path $dd) $(if (Test-Path $dd) { (Get-Item $dd).VersionInfo.ProductVersion })
$wsl = (wsl.exe --status 2>&1 | ForEach-Object { "$_" -replace "`0", '' }) -join ' '
Record 'wsl-installed' ($wsl -notmatch 'not installed') ''
$inGroup = [bool](Get-LocalGroupMember docker-users -ErrorAction SilentlyContinue | Where-Object Name -like '*\hermes')
Record 'hermes-in-docker-users' $inGroup ''
$opInGroup = [bool](Get-LocalGroupMember docker-users -ErrorAction SilentlyContinue | Where-Object Name -like '*\operator')
Write-Host "  operator in docker-users: $opInGroup (the Docker installer adds the installing user; harmless, operator is an admin)"

$boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime

# --- Autostart: Docker Desktop running in hermes's session (GetOwner needs elevation) ---
Step "Autostart"
$ddProc = Get-CimInstance Win32_Process -Filter "Name='Docker Desktop.exe'" | Where-Object {
  (Invoke-CimMethod -InputObject $_ -MethodName GetOwner).User -eq 'hermes' } | Sort-Object CreationDate | Select-Object -First 1
Record 'docker-desktop-autostarted-as-hermes' ($ddProc -and $ddProc.CreationDate -gt $boot) "boot=$boot started=$($ddProc.CreationDate)"

# --- docker ps / images, as hermes (owner types the password; scripts/invoke-as-hermes.ps1) ---
Step "docker as hermes"
$docker = Join-Path $env:ProgramFiles 'Docker\Docker\resources\bin\docker.exe'
try {
  $r = & (Join-Path $repo 'scripts\invoke-as-hermes.ps1') -Command @"
& '$docker' ps 2>&1 | Out-Null; "PSRC=`$LASTEXITCODE"
& '$docker' images --format 'IMG={{.Repository}}:{{.Tag}}' 2>&1
"@
  $rc = ($r.Output | Where-Object { $_ -like 'PSRC=*' } | Select-Object -First 1) -replace '^PSRC=', ''
  Record 'docker-ps-as-hermes' ($rc -eq '0') "docker ps exit=$rc task=$($r.TaskResult) timedOut=$($r.TimedOut)"
  if ($rc -ne '0') { $r.Output | ForEach-Object { Write-Host "    $_" } }
  $images = $r.Output | Where-Object { $_ -like 'IMG=*' } | ForEach-Object { $_ -replace '^IMG=', '' }
  if ($SandboxImage) {
    Record 'sandbox-image-present' ($images -contains $SandboxImage -or $images -contains "$SandboxImage`:latest") $SandboxImage
  } else {
    Write-Host "  [PENDING] sandbox-image-present: pass -SandboxImage after P0.6 (images: $($images -join ', '))" -ForegroundColor Yellow
  }
} catch {
  Record 'docker-ps-as-hermes' $false "could not run as hermes: $($_.Exception.Message)"
}

Step "Summary"
$results.GetEnumerator() | ForEach-Object { "{0,-38} {1}" -f $_.Key, $(if ($_.Value) {'PASS'} else {'FAIL'}) }
} finally {
  if ($LogPath) { Stop-Transcript | Out-Null }
}
