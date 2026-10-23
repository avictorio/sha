# verify/checks/p0-0b-operator.ps1 -- PLAN.md P0.0b steps 4-7 + Done-when checks
# Run in the `operator` account, in Windows PowerShell, AFTER the deploy key is on GitHub
# and the `main` ruleset exists. Prints PASS/FAIL per check. Re-runnable.
param(
  [string]$CloneDir    = "$HOME\sha",
  [string]$CommitName  = "Claude (Legion operator)",
  [string]$CommitEmail = "1481051+avictorio@users.noreply.github.com",   # GitHub noreply address
  [string]$LogPath
)
$ErrorActionPreference = 'Continue'   # native tools write to stderr; judge by exit codes
if ($LogPath) { Start-Transcript -Path $LogPath -Force | Out-Null }
try {
$results = [ordered]@{}
function Step($m) { Write-Host "`n== $m" -ForegroundColor Cyan }
function Record($name, $ok, $detail) {
  $results[$name] = $ok
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("[{0}] {1}  {2}" -f ($(if ($ok) {'PASS'} else {'FAIL'})), $name, $detail) -ForegroundColor $c
}
$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
            [Environment]::GetEnvironmentVariable('Path','User') + ";$HOME\.local\bin"

if ($env:USERNAME -ne 'operator') { throw "Not running as 'operator' (got '$env:USERNAME')." }

# Windows' built-in OpenSSH can't negotiate a key exchange with GitHub
# ("choose_kex: unsupported KEX method sntrup761x25519-sha512@openssh.com", seen 2026-10-21),
# so use the newer OpenSSH bundled with Git for Windows. Git uses that one for clone/push anyway.
$gitCmd = Get-Command git -ErrorAction SilentlyContinue
$gitRoots = @()
if ($gitCmd) { $gitRoots += (Split-Path (Split-Path $gitCmd.Source)) }   # ...\Git\cmd\git.exe -> ...\Git
$gitRoots += (Join-Path $env:ProgramFiles 'Git'), (Join-Path $env:LOCALAPPDATA 'Programs\Git')
$gitRoot = $gitRoots | Where-Object { Test-Path (Join-Path $_ 'usr\bin\ssh.exe') } | Select-Object -First 1
if (-not $gitRoot) { throw "Can't find Git for Windows' usr\bin\ssh.exe. git on PATH: $($gitCmd.Source). Tried: $($gitRoots -join '; ')" }
Write-Host "Git for Windows at: $gitRoot"
$gitUsrBin = Join-Path $gitRoot 'usr\bin'
$sshExe     = Join-Path $gitUsrBin 'ssh.exe'
$keyscanExe = Join-Path $gitUsrBin 'ssh-keyscan.exe'
$keygenExe  = Join-Path $gitUsrBin 'ssh-keygen.exe'
foreach ($p in $sshExe, $keyscanExe, $keygenExe) { if (-not (Test-Path $p)) { throw "Missing $p (Git for Windows installed?)" } }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw "git not on PATH even after refresh" }
Write-Host "Using $(& $sshExe -V 2>&1)"
$gitSsh = '"' + ($sshExe -replace '\\','/') + '"'
$env:GIT_SSH_COMMAND = $gitSsh   # make the clone use Git's ssh even if GIT_SSH points elsewhere

# --- Step 4: GitHub host key, checked against docs.github.com before trusting ---
Step "GitHub SSH host keys vs published fingerprints"
$published = @{   # docs.github.com > "GitHub's SSH key fingerprints", read 2026-10-21
  'ED25519' = 'SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU'
  'ECDSA'   = 'SHA256:p2QAMXNIC1TJYWeIOttrVc98/R1BUFWu3/LiyKgUfQM'
  'RSA'     = 'SHA256:uNiVztksCsDhcc0u9e8BujQXVUpKZIDTMczCvj3tD2s'
}
$kh = Join-Path $HOME '.ssh\known_hosts'
$scan = & $keyscanExe -t ed25519,ecdsa,rsa github.com 2>$null | Where-Object { $_ -and $_ -notmatch '^#' }
if (-not $scan) { Write-Host "  ssh-keyscan returned nothing:"; & $keyscanExe -t ed25519 github.com }
$good = @()
foreach ($line in $scan) {
  $tmp = New-TemporaryFile
  [IO.File]::WriteAllText($tmp, "$line`n")
  $fp = (& $keygenExe -lf $tmp) -join ''
  Remove-Item $tmp
  $type = if ($fp -match '\((\w+)\)\s*$') { $Matches[1] } else { '?' }
  $sha  = if ($fp -match '(SHA256:\S+)') { $Matches[1] } else { '' }
  $ok = $published.ContainsKey($type) -and $published[$type] -eq $sha
  Write-Host "  $type $sha  -> $(if ($ok) {'matches'} else {'MISMATCH'})"
  if ($ok) { $good += $line } else { $good = $null; break }
}
if ($good -and $good.Count -gt 0) {
  $existing = if (Test-Path $kh) { Get-Content $kh } else { @() }
  $toAdd = $good | Where-Object { $existing -notcontains $_ }
  if ($toAdd) { [IO.File]::AppendAllText($kh, (($toAdd -join "`n") + "`n"), (New-Object Text.UTF8Encoding $false)) }
  Record 'host-key' $true "all scanned keys match GitHub's published fingerprints"
} else {
  Record 'host-key' $false "scan failed or a key did NOT match -- not trusted, stopping"
  return
}

# --- Done-when 1: ssh -T greets with the repo name ---
Step "ssh -T git@github-sha"
$greet = (& $sshExe -T -o StrictHostKeyChecking=yes git@github-sha 2>&1) -join ' '
Write-Host "  $greet"
Record 'ssh-greeting' ($greet -match 'avictorio/sha') ''

# --- Step 5: clone ---
Step "Clone"
if (Test-Path (Join-Path $CloneDir '.git')) {
  Write-Host "  clone exists: $CloneDir"; git -C $CloneDir pull --ff-only
} else {
  git clone git@github-sha:avictorio/sha.git $CloneDir
}
Record 'clone' ((Test-Path "$CloneDir\.git") -and (Test-Path "$CloneDir\CLAUDE.md")) $CloneDir

# --- Step 6: commit identity (repo-local) ---
Step "Commit identity"
git -C $CloneDir config user.name  $CommitName
git -C $CloneDir config user.email $CommitEmail
git -C $CloneDir config core.sshCommand $gitSsh   # pin Git's OpenSSH for this repo (Windows' inbox ssh fails KEX)
Write-Host "  $(git -C $CloneDir config user.name) <$(git -C $CloneDir config user.email)>"

# --- Done-when 3: throwaway branch push + delete ---
Step "Test push to legion/test, then delete"
git -C $CloneDir push origin HEAD:refs/heads/legion/test
$pushOk = ($LASTEXITCODE -eq 0)
git -C $CloneDir push origin --delete legion/test
$delOk = ($LASTEXITCODE -eq 0)
Record 'push-legion-test' ($pushOk -and $delOk) "push=$pushOk delete=$delOk"

# --- Done-when 4: direct push to main is rejected (a real new commit) ---
Step "Direct push of a new commit to main must be REJECTED"
$orig = (git -C $CloneDir rev-parse --abbrev-ref HEAD).Trim()
git -C $CloneDir switch -c scratch/branch-rule-test 2>$null
if ($LASTEXITCODE -ne 0) { git -C $CloneDir switch scratch/branch-rule-test }
git -C $CloneDir commit --allow-empty -m "branch-rule test" | Out-Null
$out = (git -C $CloneDir push origin HEAD:main 2>&1) -join ' '
$rejected = ($LASTEXITCODE -ne 0)
Write-Host "  $out"
git -C $CloneDir switch $orig | Out-Null
git -C $CloneDir branch -D scratch/branch-rule-test | Out-Null
if (-not $rejected) { Write-Host "  !! main ACCEPTED the push -- the rule is missing; revert that commit on GitHub" -ForegroundColor Red }
Record 'main-rejects-direct-push' $rejected ''

# --- Done-when 5: OneDrive gone, privacy settings as set (registry reads: verify) ---
Step "Privacy state"
$od = @("$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe",
        "$env:ProgramFiles\Microsoft OneDrive\OneDrive.exe") | Where-Object { Test-Path $_ }
Record 'onedrive-absent' (-not $od) ($od -join ', ')
$adv = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' -ErrorAction SilentlyContinue).Enabled
Record 'advertising-id-off' ($adv -ne 1) "AdvertisingInfo\Enabled=$adv"
$tel = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' -ErrorAction SilentlyContinue).AllowTelemetry
Write-Host "  DataCollection\AllowTelemetry=$tel (1 = Required only; blank = not set via this key, see Settings)"

# --- Done-when 6 (partial): personal sign-ins visible from the shell ---
Step "Personal sign-ins"
$msa = Get-ItemProperty 'HKCU:\Software\Microsoft\IdentityCRL\UserExtendedProperties\*' -ErrorAction SilentlyContinue
Record 'no-microsoft-account' (-not $msa) ''
$opAdmin = [bool](Get-LocalGroupMember -SID 'S-1-5-32-544' | Where-Object Name -like '*\operator')
Record 'operator-admin' $opAdmin 'operator is a local admin (P0.0a)'
Write-Host "  Manual: Chrome signed out of GitHub/Google; no Telegram, no password manager."

# --- Tools ---
Step "Tools"
Write-Host "  $(git --version)"
$cc = Get-Command claude -ErrorAction SilentlyContinue
Record 'claude-code-installed' ([bool]$cc) $(if ($cc) { (claude --version) } else { 'not on PATH' })

Step "Summary"
$results.GetEnumerator() | ForEach-Object { "{0,-28} {1}" -f $_.Key, $(if ($_.Value) {'PASS'} else {'FAIL'}) }
Write-Host "`nManual check left: run 'claude' in $CloneDir and ask it to summarise CLAUDE.md."
} finally {
  if ($LogPath) { Stop-Transcript | Out-Null }
}
