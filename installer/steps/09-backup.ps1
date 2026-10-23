# installer/steps/09-backup.ps1 -- PLAN.md P1.7: nightly encrypted backup (D10: D:\backups; offsite copy later).
# Run from the `operator` account in an ELEVATED Windows PowerShell, in a visible window. The owner types the
# backup passphrase twice (hidden; also store it in the password manager), then the hermes password.
#   1. installs 7-Zip (versions.lock sevenzip_winget_version) if missing;
#   2. D:\backups: SYSTEM, Administrators and hermes only (no inherited Users access);
#   3. C:\agent\bin\backup-passphrase.txt: ACL set BEFORE the passphrase is written (hermes read,
#      SYSTEM and Administrators full); kept unless -NewPassphrase;
#   4. copies scripts/backup.ps1 to C:\agent\bin and registers Agent_Backup (daily 03:30, as hermes,
#      Interactive like the gateway tasks: hermes is signed in by auto-logon);
#   5. runs it once now, waits, and runs verify/checks/p1-7-backup.ps1.
param([string]$LogPath, [switch]$NewPassphrase)

$ErrorActionPreference = 'Stop'
if ($LogPath) { Start-Transcript -Path $LogPath -Force | Out-Null }
function Step($msg) { Write-Host "`n== $msg" -ForegroundColor Cyan }
$repo = Split-Path (Split-Path $PSScriptRoot)
$lock = ConvertFrom-StringData ((Get-Content (Join-Path $repo 'versions.lock') | Where-Object { $_ -notmatch '^\s*#' }) -join "`n")
if ($env:USERNAME -ne 'operator') { throw "Not running as 'operator' (got '$env:USERNAME'). Stop: CLAUDE.md rule 1." }
$p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw "Run this elevated (Run as administrator)." }
$sevenZip = 'C:\Program Files\7-Zip\7z.exe'
$pwFile = 'C:\agent\bin\backup-passphrase.txt'

Step "7-Zip $($lock.sevenzip_winget_version)"
if (-not (Test-Path $sevenZip)) {
  winget install --id 7zip.7zip --exact --version $lock.sevenzip_winget_version --scope machine --silent --accept-package-agreements --accept-source-agreements
  if (-not (Test-Path $sevenZip)) { throw "7-Zip didn't install ($sevenZip missing)." }
}
Write-Host "  $((Get-Item $sevenZip).VersionInfo.ProductVersion)"

Step "D:\backups: SYSTEM, Administrators, hermes only"
New-Item -ItemType Directory -Force 'D:\backups', 'C:\agent\bin', 'C:\agent\shared\logs' | Out-Null
icacls 'D:\backups' /inheritance:r /grant:r "SYSTEM:(OI)(CI)F" "Administrators:(OI)(CI)F" "hermes:(OI)(CI)M" | Out-Null
icacls 'D:\backups' | Select-Object -First 4 | ForEach-Object { Write-Host "  $_" }

Step "Backup passphrase"
if ((Test-Path $pwFile) -and -not $NewPassphrase) {
  Write-Host "  kept the existing passphrase file (-NewPassphrase to replace it; old backups keep the old one)"
} else {
  Write-Host "Choose the backup passphrase. Store it in your password manager: without it the backups can't be restored." -ForegroundColor Yellow
  $a = Read-Host -AsSecureString "backup passphrase"
  $b = Read-Host -AsSecureString "again"
  $ba = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($a); $bb = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($b)
  try {
    $pa = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ba); $pb = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bb)
    if ($pa -cne $pb) { throw "The two entries differ; nothing written." }
    if ($pa.Length -lt 12) { throw "Use at least 12 characters; nothing written." }
    if ($pa -match '"' -or $pa -ne $pa.Trim()) { throw "No double quotes or leading/trailing spaces (7-Zip's -p argument); nothing written." }
    # ACL first, then the content: the passphrase never sits in a file others can read.
    if (Test-Path $pwFile) { Remove-Item $pwFile -Force }
    New-Item -ItemType File $pwFile | Out-Null
    icacls $pwFile /inheritance:r /grant:r "SYSTEM:F" "Administrators:F" "hermes:R" | Out-Null
    [IO.File]::WriteAllText($pwFile, $pa, (New-Object Text.UTF8Encoding $false))
    Write-Host "  written (not shown)"
  } finally {
    $pa = $null; $pb = $null
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ba); [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bb)
  }
}
icacls $pwFile | Select-Object -First 4 | ForEach-Object { Write-Host "  $_" }

Step "Agent_Backup task (daily 03:30, as hermes)"
Copy-Item (Join-Path $repo 'scripts\backup.ps1') 'C:\agent\bin\backup.ps1' -Force
$hermesId = "$env:COMPUTERNAME\hermes"
Register-ScheduledTask -TaskName 'Agent_Backup' -Force `
  -Action    (New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\agent\bin\backup.ps1') `
  -Trigger   (New-ScheduledTaskTrigger -Daily -At 3:30am) `
  -Principal (New-ScheduledTaskPrincipal -UserId $hermesId -LogonType Interactive -RunLevel Limited) `
  -Settings  (New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
                -ExecutionTimeLimit (New-TimeSpan -Hours 2)) | Out-Null
Write-Host "  registered"

Step "Run it once now"
$before = @(Get-ChildItem 'D:\backups\hermes-*.7z' -ErrorAction SilentlyContinue).Count
Start-ScheduledTask -TaskName 'Agent_Backup'
$deadline = (Get-Date).AddMinutes(20)
do { Start-Sleep 5; Write-Host -NoNewline '.'; $st = (Get-ScheduledTask -TaskName 'Agent_Backup').State } while ($st -eq 'Running' -and (Get-Date) -lt $deadline)
Write-Host ""
$info = Get-ScheduledTaskInfo -TaskName 'Agent_Backup'
Write-Host "  state=$st LastTaskResult=$($info.LastTaskResult)"
Get-Content 'C:\agent\shared\logs\backup.log' -Tail 8 -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  $_" }
if (@(Get-ChildItem 'D:\backups\hermes-*.7z' -ErrorAction SilentlyContinue).Count -le $before) { Write-Host "No new archive in D:\backups." -ForegroundColor Red }

Step "Check (verify/checks/p1-7-backup.ps1)"
& (Join-Path $repo 'verify\checks\p1-7-backup.ps1')
if ($LogPath) { Stop-Transcript | Out-Null }
