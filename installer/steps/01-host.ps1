# installer/steps/01-host.ps1 -- PLAN.md P0.3 (host prep), the scripted parts.
# Run from the `operator` account in an ELEVATED Windows PowerShell. Idempotent: safe to re-run.
# The owner types the `hermes` password into the hidden prompt below; it is never echoed or logged.
# Not scripted (see docs/SETUP-GUIDE.md): Windows Update + active hours, Device encryption,
# battery conservation, DHCP reservation, Tailscale sign-in, the Autologon dialog.
param([string]$LogPath)

$ErrorActionPreference = 'Stop'
if ($LogPath) { Start-Transcript -Path $LogPath -Force | Out-Null }

function Step($msg) { Write-Host "`n== $msg" -ForegroundColor Cyan }

# --- Guard: right account, elevated -------------------------------------------
Step "Account check"
if ($env:USERNAME -ne 'operator') { throw "Not running as 'operator' (got '$env:USERNAME'). Stop: CLAUDE.md rule 1." }
$p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw "Run this elevated (Run as administrator)." }
Write-Host "operator, elevated"

# --- The `hermes` account (D1): local, standard, nothing linked ----------------
Step "hermes account"
$h = Get-LocalUser -Name hermes -ErrorAction SilentlyContinue
if ($h) {
  Write-Host "hermes exists, leaving its password alone"
} else {
  Write-Host "Type the password for 'hermes' (hidden). Also store it in your password manager." -ForegroundColor Yellow
  $pw = Read-Host -AsSecureString "hermes password"
  # PasswordNeverExpires: an expiring password would silently break Autologon.
  New-LocalUser -Name hermes -Password $pw -FullName 'Hermes agent' `
    -Description 'Runs the Hermes agent (PLAN.md D1)' -PasswordNeverExpires | Out-Null
  Remove-Variable pw
  Write-Host "created hermes"
}
if (-not (Get-LocalGroupMember -SID 'S-1-5-32-545' | Where-Object Name -like '*\hermes')) {
  Add-LocalGroupMember -SID 'S-1-5-32-545' -Member hermes      # Users
}
if (Get-LocalGroupMember -SID 'S-1-5-32-544' | Where-Object Name -like '*\hermes') {
  throw "hermes is in Administrators; it must be a standard account."
}
Write-Host "hermes: member of Users, not Administrators"

# --- hermes: "Log on as a batch job" --------------------------------------------
# scripts/invoke-as-hermes.ps1 runs steps as hermes through a one-shot task with the password
# the owner types; that is a batch logon. Windows 11 grants SeBatchLogonRight only to
# Administrators, Backup Operators and Performance Log Users, so add hermes alone.
Step "hermes: Log on as a batch job"
$sid = (Get-LocalUser hermes).SID.Value
$inf = Join-Path $env:TEMP "secpol-$([guid]::NewGuid()).inf"
$db  = Join-Path $env:TEMP "secpol-$([guid]::NewGuid()).sdb"
secedit /export /cfg $inf /areas USER_RIGHTS | Out-Null
$lines = Get-Content $inf
$cur = $lines | Where-Object { $_ -match '^SeBatchLogonRight\s*=' }
if ($cur -match [regex]::Escape("*$sid")) {
  Write-Host "already granted"
} else {
  $newLine = if ($cur) { "$cur,*$sid" } else { "SeBatchLogonRight = *$sid" }
  $body = @('[Unicode]', 'Unicode=yes', '[Version]', 'signature="$CHICAGO$"', 'Revision=1', '[Privilege Rights]', $newLine)
  Set-Content -Path $inf -Value $body -Encoding Unicode
  secedit /configure /db $db /cfg $inf /areas USER_RIGHTS /quiet
  if ($LASTEXITCODE -ne 0) { throw "secedit /configure failed ($LASTEXITCODE)" }
  Write-Host "granted SeBatchLogonRight to hermes ($sid)"
}
Remove-Item $inf, $db, "$db.jfm" -Force -ErrorAction SilentlyContinue

# --- Lock on logon (pairs with Autologon) --------------------------------------
Step "Lock-on-logon task for hermes"
$task = 'Hermes lock on logon'
$hermesId = "$env:COMPUTERNAME\hermes"
Register-ScheduledTask -TaskName $task -Force `
  -Action    (New-ScheduledTaskAction -Execute 'rundll32.exe' -Argument 'user32.dll,LockWorkStation') `
  -Trigger   (New-ScheduledTaskTrigger -AtLogOn -User $hermesId) `
  -Principal (New-ScheduledTaskPrincipal -UserId $hermesId -LogonType Interactive -RunLevel Limited) `
  -Settings  (New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries) | Out-Null
Write-Host "registered: $task"

# --- Power: never sleep on AC, lid does nothing on AC --------------------------
Step "Power"
powercfg /change standby-timeout-ac 0
powercfg /change hibernate-timeout-ac 0
powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0
powercfg /setactive SCHEME_CURRENT
Write-Host "standby/hibernate on AC: never; lid on AC: do nothing"

# --- Folders, restricted to hermes + Administrators + SYSTEM -------------------
Step "Agent folders"
New-Item -ItemType Directory -Force C:\agent\workspace\calls\briefs, C:\agent\private\workspace, `
  C:\agent\private\config, C:\agent\shared\travel, C:\agent\shared\logs, C:\agent\chrome, C:\agent\bin, `
  D:\ollama\models, D:\backups | Out-Null
icacls C:\agent /inheritance:r /grant:r "hermes:(OI)(CI)F" "Administrators:(OI)(CI)F" "SYSTEM:(OI)(CI)F"
if ($LASTEXITCODE -ne 0) { throw "icacls failed" }

# --- Tools: Tailscale, Sysinternals Autologon ----------------------------------
Step "Tailscale"
if (Get-Command tailscale -ErrorAction SilentlyContinue) { Write-Host "already installed" }
else { winget install --id Tailscale.Tailscale -e --source winget --accept-package-agreements --accept-source-agreements }

Step "Sysinternals Autologon"
winget install --id Microsoft.Sysinternals.Autologon -e --source winget --accept-package-agreements --accept-source-agreements
Write-Host "Next (owner): run Autologon, user 'hermes', domain '$env:COMPUTERNAME', type the password, Enable." -ForegroundColor Yellow

Step "Done"
if ($LogPath) { Stop-Transcript | Out-Null }
