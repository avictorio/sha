# verify/checks/p0-3-host.ps1 -- PLAN.md P0.3 (host prep) checks
# Run in the `operator` account, in an ELEVATED Windows PowerShell: C:\agent and the
# hermes lock task are only visible to Administrators when elevated.
# Run it after an untouched reboot: `hermes` should have signed in by itself and locked.
# Prints PASS/FAIL per check. Re-runnable.
$ErrorActionPreference = 'Continue'
$results = [ordered]@{}
function Step($m) { Write-Host "`n== $m" -ForegroundColor Cyan }
function Record($name, $ok, $detail) {
  $results[$name] = $ok
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("[{0}] {1}  {2}" -f ($(if ($ok) {'PASS'} else {'FAIL'})), $name, $detail) -ForegroundColor $c
}
if ($env:USERNAME -ne 'operator') { throw "Not running as 'operator' (got '$env:USERNAME')." }
$p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw "Run this elevated (Run as administrator)." }

# --- hermes account ---
Step "hermes account"
$h = Get-LocalUser -Name hermes -ErrorAction SilentlyContinue
Record 'hermes-exists' ([bool]$h -and $h.Enabled) ''
$isUser  = [bool](Get-LocalGroupMember -SID 'S-1-5-32-545' | Where-Object Name -like '*\hermes')
$isAdmin = [bool](Get-LocalGroupMember -SID 'S-1-5-32-544' | Where-Object Name -like '*\hermes')
Record 'hermes-standard' ($isUser -and -not $isAdmin) "Users=$isUser Administrators=$isAdmin"
Record 'hermes-password-never-expires' ($h -and -not $h.PasswordExpires) "PasswordExpires=$($h.PasswordExpires)"
$opAdmin = [bool](Get-LocalGroupMember -SID 'S-1-5-32-544' | Where-Object Name -like '*\operator')
Record 'operator-admin' $opAdmin ''

# --- Autologon + lock on logon ---
Step "Autologon and lock"
$wl = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
Record 'autologon-hermes' (($wl.AutoAdminLogon -eq '1') -and ($wl.DefaultUserName -eq 'hermes')) "AutoAdminLogon=$($wl.AutoAdminLogon) DefaultUserName=$($wl.DefaultUserName)"
Record 'autologon-no-plaintext' (-not $wl.DefaultPassword) 'no DefaultPassword value (Autologon stores it as an LSA secret)'
$task = Get-ScheduledTask -TaskName 'Hermes lock on logon' -ErrorAction SilentlyContinue
$info = if ($task) { $task | Get-ScheduledTaskInfo } else { $null }
$boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
Record 'lock-task-registered' ([bool]$task) ''
Record 'lock-task-ran-since-boot' ($info -and $info.LastRunTime -gt $boot -and $info.LastTaskResult -eq 0) "boot=$boot lastRun=$($info.LastRunTime) result=$($info.LastTaskResult)"

# --- After an untouched reboot: hermes signed in, screen locked ---
Step "hermes session"
$explorer = Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" | ForEach-Object {
  $o = Invoke-CimMethod -InputObject $_ -MethodName GetOwner; [pscustomobject]@{ User = $o.User; Session = $_.SessionId } }
$hs = $explorer | Where-Object User -eq 'hermes' | Select-Object -First 1
Record 'hermes-signed-in' ([bool]$hs) $(if ($hs) { "session $($hs.Session)" } else { 'no explorer.exe for hermes' })
if ($hs) {
  $logonUI = Get-CimInstance Win32_Process -Filter "Name='LogonUI.exe' AND SessionId=$($hs.Session)"
  Record 'hermes-session-locked' ([bool]$logonUI) "LogonUI.exe in session $($hs.Session): $([bool]$logonUI)"
}

# --- Power ---
Step "Power (AC)"
function AcValue($sub, $setting) {
  # /qh: LIDACTION is a hidden setting on this laptop, so plain /q prints nothing for it
  $line = powercfg /qh SCHEME_CURRENT $sub $setting | Select-String 'Current AC Power Setting Index'
  if ($line -match '0x([0-9a-fA-F]+)') { [Convert]::ToInt32($Matches[1], 16) } else { $null }
}
$standby = AcValue SUB_SLEEP STANDBYIDLE
$hib     = AcValue SUB_SLEEP HIBERNATEIDLE
$lid     = AcValue SUB_BUTTONS LIDACTION
Record 'ac-never-sleep' (($standby -eq 0) -and ($hib -eq 0)) "standby=$standby hibernate=$hib"
Record 'ac-lid-nothing' ($lid -eq 0) "lid=$lid"

# --- Folders ---
Step "Agent folders"
$dirs = 'C:\agent\workspace\calls\briefs','C:\agent\local\workspace','C:\agent\local\config',
        'C:\agent\shared\travel','C:\agent\shared\logs','C:\agent\chrome','C:\agent\bin','D:\ollama\models','D:\backups'
$missing = $dirs | Where-Object { -not (Test-Path $_) }
Record 'folders-exist' (-not $missing) ($missing -join ', ')
$acl = Get-Acl C:\agent
$who = $acl.Access | ForEach-Object { $_.IdentityReference.Value } | Sort-Object -Unique
$extra = $who | Where-Object { $_ -notmatch '\\hermes$|\\Administrators$|\\SYSTEM$' }
Record 'agent-acl' ($acl.AreAccessRulesProtected -and -not $extra) "inheritance off=$($acl.AreAccessRulesProtected) principals=$($who -join ', ')"

# --- Disk encryption (Device encryption on Home) ---
Step "Disk encryption"
$bl = (New-Object -ComObject Shell.Application).NameSpace(17).ParseName('C:').ExtendedProperty('System.Volume.BitLockerProtection')
Record 'c-encrypted' ($bl -eq 1) "BitLockerProtection=$bl (1=on)"
Write-Host "  Manual: the recovery key is listed at account.microsoft.com/devices/recoverykey"

# --- Tailscale ---
Step "Tailscale"
$ts = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
if (Test-Path $ts) {
  $prefs = (& $ts debug prefs 2>$null) -join ''
  Record 'tailscale-unattended' ($prefs -match '"ForceDaemon":\s*true') ''
  $ip = (& $ts ip -4 2>$null) -join ''
  Record 'tailscale-connected' ($LASTEXITCODE -eq 0 -and $ip -match '^100\.') "ip=$ip"
} else { Record 'tailscale-installed' $false $ts }
Write-Host "  Manual: the machine shows as connected in the Tailscale admin console"

# --- Windows Update ---
Step "Windows Update"
try {
  $r = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher().Search("IsInstalled=0 and IsHidden=0")
  Record 'no-pending-updates' ($r.Updates.Count -eq 0) (($r.Updates | ForEach-Object Title) -join '; ')
} catch { Record 'no-pending-updates' $false "search failed: $_" }
$ah = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings' -ErrorAction SilentlyContinue
Write-Host "  active hours: $($ah.ActiveHoursStart):00-$($ah.ActiveHoursEnd):00"

Step "Summary"
$results.GetEnumerator() | ForEach-Object { "{0,-30} {1}" -f $_.Key, $(if ($_.Value) {'PASS'} else {'FAIL'}) }
Write-Host "`nManual checks left: Tailscale admin console shows the machine; recovery key listed online; DHCP reservation; battery conservation."
