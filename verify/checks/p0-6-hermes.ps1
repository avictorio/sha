# verify/checks/p0-6-hermes.ps1 -- PLAN.md P0.6 (Hermes installed and configured as hermes) checks
# Run in the `operator` account, in an ELEVATED Windows PowerShell, in a visible window:
# everything below runs AS hermes via scripts/invoke-as-hermes.ps1 (the owner types the password).
# Prints PASS/FAIL per check. Re-runnable; removes the hello.txt it asks the agent to create.
param([string]$LogPath)
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
$p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw "Run this elevated (Run as administrator)." }
$repo = Split-Path (Split-Path $PSScriptRoot)
$hello = 'C:\agent\workspace\hello.txt'
Remove-Item $hello -Force -ErrorAction SilentlyContinue

Step "As hermes: doctor, chat, hello.txt, host-folder probes, live container mounts"
$cmd = @'
# UTF-8 end to end, or doctor's check marks arrive as mojibake and can't be matched.
[Console]::OutputEncoding = [Text.Encoding]::UTF8; $OutputEncoding = [Text.Encoding]::UTF8
$env:NO_COLOR = '1'; $env:PYTHONIOENCODING = 'utf-8'; $env:PYTHONUTF8 = '1'
$h = Join-Path $env:LOCALAPPDATA 'hermes\bin\hermes.exe'
$docker = Join-Path $env:ProgramFiles 'Docker\Docker\resources\bin\docker.exe'
function Ask($q) { & $h chat -Q -q $q 2>&1 | Where-Object { "$_" -notmatch '^System\.Management\.Automation' } | Select-Object -Last 15 }
"##### doctor"
& $h doctor 2>&1
"##### chat"
Ask 'Reply with exactly the word PONG and nothing else.'
"##### hello"
# No double quotes in prompts: PS 5.1 mangles them when passing arguments to native programs.
Ask 'Use your terminal tool to run this one command: echo hello-from-hermes > /workspace/work/hello.txt'
"##### mntc"
Ask 'Use your terminal tool to run this one command and show its raw output, including any error: ls /mnt/c'
"##### mnt"
Ask 'Use your terminal tool to run this one command and show its raw output, including any error: ls -la /mnt'
"##### denyglob"
# Does a deny glob ("dd if=*") match only a whole command, or also part of a chained one?
Ask 'Use your terminal tool to run this one command: dd if=/dev/zero of=/workspace/work/dd-whole bs=1 count=1'
Ask 'Use your terminal tool to run this one command: true && dd if=/dev/zero of=/workspace/work/dd-chained bs=1 count=1'
"##### mounts"
# Hermes removes its container when a chat ends, so inspect while one is running.
$job = Start-Job -ScriptBlock { param($h) & $h chat -Q -q 'Use your terminal tool to run this one command: sleep 45' 2>&1 } -ArgumentList $h
$deadline = (Get-Date).AddSeconds(120); $seen = $false
while (-not $seen -and (Get-Date) -lt $deadline) {
  Start-Sleep 2
  $ids = & $docker ps --filter 'ancestor=nousresearch/hermes-sandbox:desktop' --format '{{.ID}}' 2>$null
  foreach ($id in $ids) {
    $seen = $true
    & $docker inspect --format '{{range .Mounts}}MOUNT={{.Type}}|{{.Source}}|{{.Destination}}|rw={{.RW}}{{println}}{{end}}' $id 2>&1
  }
}
if (-not $seen) { 'MOUNT=none-seen' }
Stop-Job $job -ErrorAction SilentlyContinue; Remove-Job $job -Force -ErrorAction SilentlyContinue
"##### end"
'@
try {
  $r = & (Join-Path $repo 'scripts\invoke-as-hermes.ps1') -Command $cmd -TimeoutSeconds 1800
} catch { Record 'run-as-hermes' $false $_.Exception.Message; $r = $null }

if ($r) {
  $out = @($r.Output)
  function Section($name) {
    $i = [array]::IndexOf($out, "##### $name"); if ($i -lt 0) { return @() }
    $sec = @(); for ($j = $i + 1; $j -lt $out.Count -and $out[$j] -notlike '##### *'; $j++) { $sec += $out[$j] }; $sec
  }
  $ok = [char]0x2713; $warn = [char]0x26A0

  # doctor: must show check marks (proves the output is readable) and no failure marks
  $doc = Section 'doctor'
  $nOk = @($doc | Where-Object { $_ -match $ok }).Count
  $fails = @($doc | Where-Object { $_ -match "[$([char]0x2717)$([char]0x2718)]" })
  $nWarn = @($doc | Where-Object { $_ -match $warn }).Count
  Record 'doctor-no-failures' (($nOk -gt 5) -and ($fails.Count -eq 0)) $(if ($fails) { ($fails | Select-Object -First 3) -join ' | ' } else { "$nOk ok, $nWarn warnings (optional packages / unused auth)" })
  if ($nWarn) { $doc | Where-Object { $_ -match $warn } | ForEach-Object { Write-Host "    $($_.Trim())" } }

  # chat answers from the local model
  $chat = (Section 'chat') -join ' '
  Record 'chat-local-model' ($chat -match 'PONG') ($chat.Substring(0, [Math]::Min(80, $chat.Length)))

  # hello.txt lands on the host
  $hok = (Test-Path $hello) -and ((Get-Content $hello -Raw) -match 'hello-from-hermes')
  Record 'hello-txt-on-host' $hok $hello
  if (-not $hok) { Section 'hello' | ForEach-Object { Write-Host "    agent: $_" } }

  # host folders not visible: positive evidence that /mnt/c doesn't exist (raw error or the model's
  # paraphrase of it), and no Windows names under /mnt
  $mntc = (Section 'mntc') -join ' '
  $mnt  = (Section 'mnt') -join ' '
  Record 'no-mnt-c' ($mntc -match '(?i)No such file or directory|does not exist|cannot access') ($mntc.Substring(0, [Math]::Min(120, $mntc.Length)))
  Record 'no-windows-folders-under-mnt' ($mnt -notmatch '(?i)\b(c|d|wsl|wslg|Users|Windows)\b/?\s' -and $mnt.Length -gt 0) ($mnt.Substring(0, [Math]::Min(160, $mnt.Length)))

  # live container mounts. Allowed bind sources: C:\agent\workspace (the one user folder),
  # C:\ProgramData\hermes-status read-only (the build status), and
  # Hermes's own working subfolders under %LOCALAPPDATA%\hermes, which Hermes mounts itself
  # (sandboxes, attachments, images, skills, caches...). Never: secrets, config, memories,
  # sessions, the state DB, or anything else in the profile or on the disk.
  $mounts = (Section 'mounts') | Where-Object { $_ -like 'MOUNT=*' } | ForEach-Object { $_ -replace '^MOUNT=', '' }
  $binds = @($mounts | Where-Object { $_ -like 'bind|*' })
  $hermesHome = '(?i)^C:\\Users\\hermes\\AppData\\Local\\hermes\\'
  $sensitive  = '(?i)\\(\.env|auth\.json|config\.yaml|memories|sessions|state\.db|pairing|hooks|logs)(\\|$)|\\hermes\\?$'
  $badBinds = @($binds | Where-Object {
    $src = ($_ -split '\|')[1]
    $statusRo = $src -match '(?i)^C:[\\/]ProgramData[\\/]hermes-status$' -and $_ -like '*|rw=false'   # STATUS.md, read-only only
    -not ($src -match '(?i)^C:[\\/]agent[\\/]workspace$' -or $statusRo -or ($src -match $hermesHome -and $src -notmatch $sensitive)) })
  $seen = $mounts -and ($mounts -notcontains 'none-seen')
  Record 'container-mounts-restricted' ($seen -and $badBinds.Count -eq 0) $(if (-not $seen) { 'no running sandbox container seen' } elseif ($badBinds) { 'NOT ALLOWED: ' + ($badBinds -join '; ') } else { "$($binds.Count) binds: C:\agent\workspace + Hermes's own subfolders" })
  $binds | ForEach-Object { $f = $_ -split '\|'; Write-Host ("    {0} -> {1}  {2}" -f $f[1], $f[2], $f[3]) }
}
Remove-Item $hello -Force -ErrorAction SilentlyContinue

# approvals.deny glob semantics (finding, not pass/fail): which dd runs were blocked?
$ddWhole   = Test-Path 'C:\agent\workspace\dd-whole'
$ddChained = Test-Path 'C:\agent\workspace\dd-chained'
Write-Host ("  [INFO] deny 'dd if=*': whole command {0}; chained after 'true &&' {1}" -f `
  $(if ($ddWhole) { 'RAN (not blocked)' } else { 'blocked' }), $(if ($ddChained) { 'RAN (not blocked)' } else { 'blocked' })) -ForegroundColor Yellow
if ($r) { Section 'denyglob' | ForEach-Object { Write-Host "    agent: $_" } }
Remove-Item 'C:\agent\workspace\dd-whole', 'C:\agent\workspace\dd-chained' -Force -ErrorAction SilentlyContinue

Step "Summary"
$results.GetEnumerator() | ForEach-Object { "{0,-30} {1}" -f $_.Key, $(if ($_.Value) {'PASS'} else {'FAIL'}) }
} finally {
  if ($LogPath) { Stop-Transcript | Out-Null }
}
