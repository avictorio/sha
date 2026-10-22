# installer/steps/02-ollama.ps1 -- PLAN.md P0.4: Ollama as a Windows service via NSSM.
# Run from the `operator` account in an ELEVATED Windows PowerShell. Idempotent: safe to re-run.
# Versions come from versions.lock. The model pulls are a separate, unelevated step:
#   installer/steps/02-ollama.ps1 -PullOnly
param([switch]$PullOnly, [string]$LogPath)

$ErrorActionPreference = 'Stop'
if ($LogPath) { Start-Transcript -Path $LogPath -Force | Out-Null }
function Step($msg) { Write-Host "`n== $msg" -ForegroundColor Cyan }

$repo = Split-Path (Split-Path $PSScriptRoot)
$lock = ConvertFrom-StringData ((Get-Content (Join-Path $repo 'versions.lock') |
  Where-Object { $_ -notmatch '^\s*#' }) -join "`n")
$root = 'D:\ollama'
$bin  = Join-Path $root 'bin'
$ollama = Join-Path $bin 'ollama.exe'

if ($env:USERNAME -ne 'operator') { throw "Not running as 'operator' (got '$env:USERNAME'). Stop: CLAUDE.md rule 1." }

if ($PullOnly) {
  # --- Model pulls (unelevated is fine; the service does the downloading) ----
  # `ollama pull` draws its progress on stderr; under 'Stop', PS 5.1 turns the first
  # stderr line into a terminating error. Judge by the exit code instead.
  $ErrorActionPreference = 'Continue'
  foreach ($tag in ($lock.model_candidates -split ',')) {
    Step "ollama pull $tag"
    & $ollama pull $tag
    if ($LASTEXITCODE -ne 0) { throw "pull failed: $tag" }
  }
  & $ollama list
  if ($LogPath) { Stop-Transcript | Out-Null }
  return
}

$p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw "Run this elevated (Run as administrator)." }

# --- Lock D:\ollama: the service runs as SYSTEM, so only admins may write here --
# (D:'s default ACL lets any authenticated user modify; hermes could otherwise swap ollama.exe.)
Step "D:\ollama ACL"
New-Item -ItemType Directory -Force $bin, (Join-Path $root 'models'), (Join-Path $root 'logs') | Out-Null
icacls $root /inheritance:r /grant:r "Administrators:(OI)(CI)F" "SYSTEM:(OI)(CI)F" "Users:(OI)(CI)RX"
if ($LASTEXITCODE -ne 0) { throw "icacls failed" }

# --- Ollama standalone zip, hash-checked --------------------------------------
Step "Ollama $($lock.ollama_version)"
$have = if (Test-Path $ollama) { ((& $ollama --version 2>&1) -join ' ') } else { '' }
if ($have -match [regex]::Escape($lock.ollama_version.TrimStart('v'))) {
  Write-Host "already installed: $have"
} else {
  if (Get-Service Ollama -ErrorAction SilentlyContinue) { & $bin\nssm.exe stop Ollama | Out-Null }
  $dl = Join-Path $env:TEMP ("ollama-dl-" + [guid]::NewGuid())
  New-Item -ItemType Directory $dl | Out-Null
  $base = "https://github.com/ollama/ollama/releases/download/$($lock.ollama_version)"
  $zip = Join-Path $dl 'ollama-windows-amd64.zip'
  $ProgressPreference = 'SilentlyContinue'
  try {
    Invoke-WebRequest "$base/ollama-windows-amd64.zip" -OutFile $zip -UseBasicParsing
    # Save, then read as text: GitHub serves it as octet-stream, so .Content would be bytes in PS 5.1.
    $sumsFile = Join-Path $dl 'sha256sum.txt'
    Invoke-WebRequest "$base/sha256sum.txt" -OutFile $sumsFile -UseBasicParsing
    $want = (Get-Content $sumsFile | Where-Object { $_ -match 'ollama-windows-amd64\.zip\s*$' }) -replace '\s.*$',''
    $got  = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
    if (-not $want -or $got -ne "$want".Trim().ToLower()) { throw "SHA256 mismatch for the Ollama zip: got $got, want '$want'" }
    Write-Host "sha256 ok: $got"
    Expand-Archive $zip -DestinationPath $bin -Force
  } finally {
    Remove-Item $dl -Recurse -Force -ErrorAction SilentlyContinue
  }
  Write-Host "installed: $((& $ollama --version 2>&1) -join ' ')"
}

# --- NSSM, copied into the locked bin folder -----------------------------------
Step "NSSM"
$nssm = Join-Path $bin 'nssm.exe'
if (-not (Test-Path $nssm)) {
  winget install --id NSSM.NSSM -e --source winget --version $lock.nssm_winget_version `
    --accept-package-agreements --accept-source-agreements
  $src = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter nssm.exe |
    Where-Object FullName -match 'win64' | Select-Object -First 1
  if (-not $src) { throw "nssm.exe (win64) not found after winget install" }
  Copy-Item $src.FullName $nssm
}
Write-Host "nssm: $nssm"

# --- The service ----------------------------------------------------------------
Step "Ollama service"
if (-not (Get-Service Ollama -ErrorAction SilentlyContinue)) {
  & $nssm install Ollama $ollama serve
}
& $nssm set Ollama AppEnvironmentExtra OLLAMA_CONTEXT_LENGTH=65536 OLLAMA_KEEP_ALIVE=30m `
  OLLAMA_FLASH_ATTENTION=1 OLLAMA_KV_CACHE_TYPE=q8_0 "OLLAMA_MODELS=$root\models"
& $nssm set Ollama AppStdout "$root\logs\ollama.log"
& $nssm set Ollama AppStderr "$root\logs\ollama.log"
& $nssm set Ollama AppRotateFiles 1
& $nssm set Ollama AppRotateBytes 10485760
& $nssm set Ollama Start SERVICE_AUTO_START
if ((Get-Service Ollama).Status -ne 'Running') { & $nssm start Ollama }
Start-Sleep 5
Get-Service Ollama | Format-Table Name, Status, StartType -AutoSize

# --- D:\ollama\bin on hermes's PATH ---------------------------------------------
Step "hermes PATH"
$sid = (Get-LocalUser hermes).SID.Value
$envKey = "Registry::HKEY_USERS\$sid\Environment"
if (-not (Test-Path "Registry::HKEY_USERS\$sid")) {
  throw "hermes's profile isn't loaded (sign hermes in, e.g. via the auto-logon reboot), then re-run."
}
$cur = (Get-ItemProperty $envKey -Name Path -ErrorAction SilentlyContinue).Path
if (($cur -split ';') -contains $bin) {
  Write-Host "already on hermes's PATH"
} else {
  $new = (@($cur -split ';' | Where-Object { $_ }) + $bin) -join ';'
  New-ItemProperty $envKey -Name Path -Value $new -PropertyType ExpandString -Force | Out-Null
  Write-Host "added $bin to hermes's PATH (takes effect at hermes's next sign-in)"
}

Step "Done (next: 02-ollama.ps1 -PullOnly, unelevated)"
if ($LogPath) { Stop-Transcript | Out-Null }
