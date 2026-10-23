# scripts/invoke-as-hermes.ps1 -- run commands AS `hermes`, from `operator`, through the owner's
# credential prompt (CLAUDE.md rule 1).
#
# Why a scheduled task: on this machine, Start-Process -Credential and runas.exe fail with
# "Access is denied" (Win32 error 5) after a successful logon, from any window
# (diagnosed 2026-10-21; Security log shows 4624 type 2 succeeding). A one-shot task runs
# as hermes in its own non-interactive logon, with no desktop involved.
#
# Usage (from an ELEVATED Windows PowerShell in `operator`):
#   $r = & scripts\invoke-as-hermes.ps1 -Command 'docker ps; docker images'
#   $r.ExitCode; $r.Output
#
# The owner types the hermes password at a hidden prompt. It is held only in memory, used to
# register the task, and dropped with the task when the run ends. Nothing is logged.
param(
  [Parameter(Mandatory)] [string]$Command,
  [int]$TimeoutSeconds = 300,
  [securestring]$Password     # optional: reuse one prompt across several calls in the same script
)

$ErrorActionPreference = 'Stop'
if ($env:USERNAME -ne 'operator') { throw "Not running as 'operator' (got '$env:USERNAME'). Stop: CLAUDE.md rule 1." }
$p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw "Run this elevated (Run as administrator)." }

if (-not $Password) {
  Write-Host "Type the hermes password (hidden):" -ForegroundColor Yellow
  $Password = Read-Host -AsSecureString "hermes password"
}

# A run that was killed mid-way leaves its task (with the stored credential) and folder behind: remove them.
Get-ScheduledTask -TaskName 'hermes-oneshot-*' -ErrorAction SilentlyContinue | ForEach-Object {
  Write-Host "removing a leftover one-shot task: $($_.TaskName)" -ForegroundColor Yellow
  Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false -ErrorAction SilentlyContinue
}
Get-ChildItem $env:PUBLIC -Directory -Filter 'hermes-oneshot-*' -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

$id   = [guid]::NewGuid().ToString('N')
$task = "hermes-oneshot-$id"
$dir  = Join-Path $env:PUBLIC "hermes-oneshot-$id"
New-Item -ItemType Directory $dir | Out-Null
# Only hermes (to run and write), SYSTEM and Administrators: nobody else can swap the script.
icacls $dir /inheritance:r /grant:r "hermes:(OI)(CI)M" "SYSTEM:(OI)(CI)F" "Administrators:(OI)(CI)F" | Out-Null

$wrapper = @"
`$ErrorActionPreference = 'Continue'
try {
  & { $Command } *>&1 | ForEach-Object { "`$_" } | Out-File -Encoding utf8 '$dir\out.txt'
  `$rc = if (`$LASTEXITCODE -ne `$null) { `$LASTEXITCODE } elseif (`$?) { 0 } else { 1 }
} catch { "`$_" | Out-File -Append -Encoding utf8 '$dir\out.txt'; `$rc = 1 }
"`$rc" | Out-File -Encoding ascii '$dir\rc.txt'
"@
# A command that doesn't parse (e.g. "$name:" in a string) would otherwise end the task with no result.
$parseErrors = $null
[Management.Automation.Language.Parser]::ParseInput($wrapper, [ref]$null, [ref]$parseErrors) | Out-Null
if ($parseErrors) {
  Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
  throw ("the command doesn't parse: " + (($parseErrors | ForEach-Object { "line $($_.Extent.StartLineNumber): $($_.Message)" }) -join '; '))
}
Set-Content -Path "$dir\run.ps1" -Value $wrapper -Encoding UTF8

$bstr = [IntPtr]::Zero
try {
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
  $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
  $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$dir\run.ps1`"" -WorkingDirectory $dir
  $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Seconds $TimeoutSeconds)
  Register-ScheduledTask -TaskName $task -Action $action -Settings $settings `
    -User "$env:COMPUTERNAME\hermes" -Password $plain -RunLevel Limited | Out-Null
  $plain = $null

  Start-ScheduledTask -TaskName $task
  $started  = Get-Date
  $deadline = $started.AddSeconds($TimeoutSeconds + 15)
  $neverRan = [datetime]'2000-01-01'
  Write-Host "running as hermes " -NoNewline
  do {
    Start-Sleep -Milliseconds 500
    Write-Host '.' -NoNewline
    $done = Test-Path "$dir\rc.txt"
    $info = Get-ScheduledTaskInfo -TaskName $task
    # Fail fast if Task Scheduler couldn't start it (e.g. no SeBatchLogonRight: result stays 0x41303).
    if (-not $done -and $info.LastRunTime -lt $neverRan -and ((Get-Date) - $started).TotalSeconds -gt 20) {
      Write-Host ''
      throw ("the task did not start within 20 s (LastTaskResult=0x{0:X8}). Is hermes granted 'Log on as a batch job' (installer/steps/01-host.ps1)?" -f $info.LastTaskResult)
    }
    # Ended without writing rc.txt (e.g. the command doesn't parse): stop waiting instead of sitting out the timeout.
    if (-not $done -and $info.LastRunTime -gt $neverRan -and ((Get-Date) - $started).TotalSeconds -gt 10 -and
        (Get-ScheduledTask -TaskName $task).State -eq 'Ready' -and -not (Test-Path "$dir\rc.txt")) {
      Write-Host ''
      Write-Host ("the task ended without a result (LastTaskResult=0x{0:X8}); does the command parse?" -f $info.LastTaskResult) -ForegroundColor Red
      break
    }
  } until ($done -or (Get-Date) -gt $deadline)
  Write-Host ''

  $info = Get-ScheduledTaskInfo -TaskName $task
  [pscustomobject]@{
    ExitCode   = if ($done) { [int](Get-Content "$dir\rc.txt" | Select-Object -First 1) } else { $null }
    # Secrets never reach the caller's log: OpenRouter keys, Telegram bot tokens.
    Output     = if (Test-Path "$dir\out.txt") { Get-Content "$dir\out.txt" | ForEach-Object { $_ -replace 'sk-or-[A-Za-z0-9_-]+|\d{6,12}:[A-Za-z0-9_-]{30,}', '<redacted>' } } else { @() }
    TimedOut   = -not $done
    TaskResult = $info.LastTaskResult
  }
} finally {
  if ($bstr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
  Unregister-ScheduledTask -TaskName $task -Confirm:$false -ErrorAction SilentlyContinue   # drops the stored credential
  Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
}
