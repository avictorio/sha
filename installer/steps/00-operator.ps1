# installer/steps/00-operator.ps1 -- PLAN.md P0.0b, steps 1-3 (tool check + deploy key)
# Run in the `operator` account, in Windows PowerShell (not as another user).
# It checks that Git for Windows and Claude Code are on PATH (the owner installs
# both in P0.0a; this script installs nothing), then creates the repo deploy key
# and the github-sha SSH alias, and prints the PUBLIC key. Idempotent: safe to re-run.
# The privacy settings (step 2) were applied through Windows Settings; see
# docs/SETUP-GUIDE.md#operator-account.

$ErrorActionPreference = 'Stop'

function Step($msg) { Write-Host "`n== $msg" -ForegroundColor Cyan }

# --- 0. Guard: right account, admin -----------------------------------------
Step "Account check"
$who = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = (New-Object Security.Principal.WindowsPrincipal $who).IsInRole(
  [Security.Principal.WindowsBuiltInRole]::Administrator)
$adminGroup = [bool](Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction SilentlyContinue |
  Where-Object Name -like "*\$env:USERNAME")
Write-Host "whoami: $(whoami)   member of Administrators: $adminGroup   elevated: $isAdmin"
if ($env:USERNAME -ne 'operator') { throw "Not running as 'operator' (got '$env:USERNAME'). Stop: CLAUDE.md rule 1." }

function Refresh-Path {
  $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
              [Environment]::GetEnvironmentVariable('Path','User') + ';' +
              "$HOME\.local\bin"
}

# --- 1a. Git for Windows (installed in P0.0a; check only) ---------------------
Step "Git for Windows"
Refresh-Path
if (Get-Command git -ErrorAction SilentlyContinue) {
  Write-Host "found: $(git --version)"
} else {
  throw "git not found on PATH. The owner installs Git for Windows in P0.0a (PLAN.md; docs/SETUP-GUIDE.md#git-for-windows). Stop and hand back to the owner."
}

# --- 1b. Claude Code (installed in P0.0a; check only) -------------------------
Step "Claude Code"
if (Get-Command claude -ErrorAction SilentlyContinue) {
  Write-Host "found: $(claude --version)"
} else {
  throw "claude not found on PATH. The owner installs Claude Code in P0.0a (PLAN.md; docs/SETUP-GUIDE.md#claude-code). Stop and hand back to the owner."
}

# --- 3. Deploy key + SSH config -----------------------------------------------
Step "OpenSSH client"
$sshKeygen = Get-Command ssh-keygen -ErrorAction SilentlyContinue
if (-not $sshKeygen) { throw "Built-in OpenSSH client not found (Settings > System > Optional features > OpenSSH Client)." }
Write-Host "ssh-keygen: $($sshKeygen.Source)"

Step "Deploy key"
$sshDir = Join-Path $HOME '.ssh'
New-Item -ItemType Directory -Force $sshDir | Out-Null
$key = Join-Path $sshDir 'sha_deploy'
if (Test-Path $key) {
  Write-Host "key exists, leaving it: $key"
} else {
  # Empty passphrase: Windows PowerShell 5.1 needs '""'; PowerShell 7.3+ passes '' correctly.
  $empty = if ($PSVersionTable.PSVersion.Major -ge 7) { '' } else { '""' }
  & ssh-keygen -t ed25519 -f $key -C "legion-operator sha deploy key" -N $empty
  if ($LASTEXITCODE -ne 0) { throw "ssh-keygen failed" }
}

Step "~/.ssh/config (no BOM)"
$cfg = Join-Path $sshDir 'config'
$block = @"
Host github-sha
  HostName github.com
  User git
  IdentityFile ~/.ssh/sha_deploy
  IdentitiesOnly yes
"@
$existing = if (Test-Path $cfg) { [IO.File]::ReadAllText($cfg) } else { '' }
if ($existing -match '(?m)^Host\s+github-sha\s*$') {
  Write-Host "Host github-sha already present"
} else {
  $new = ($existing.TrimEnd() + "`n`n" + $block + "`n").TrimStart()
  [IO.File]::WriteAllText($cfg, $new, (New-Object Text.UTF8Encoding $false))
  Write-Host "written: $cfg"
}
$bytes = [IO.File]::ReadAllBytes($cfg)
$bom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
Write-Host "BOM present: $bom"

Step "PUBLIC key -- paste this into GitHub > avictorio/sha > Settings > Deploy keys (Allow write access)"
Get-Content "$key.pub"
Write-Host "`nFingerprint:"; ssh-keygen -lf "$key.pub"
