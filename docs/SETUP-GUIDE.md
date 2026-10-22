# Setup guide

Steps that can't be scripted, or that were done by hand, one section per task. Scripted steps live in `installer/steps/` and their checks in `verify/checks/`.

## operator-account

PLAN.md P0.0b. Tools and the deploy key are scripted in `installer/steps/00-operator.ps1`, and the checks are in `verify/checks/p0-0b-operator.ps1`. The steps below were done by hand in the `operator` account.

### Privacy settings (Windows Settings)

- **Advertising ID:** Settings → Privacy & security → General. It was already off. (`HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo` `Enabled` = 0.)
- **Diagnostic data:** Settings → Privacy & security → Diagnostics & feedback. It was already "Required only". (`HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection` `AllowTelemetry` = 1.)
- **Windows Backup / settings sync:** Settings → Accounts → Windows backup. It was already off.

### OneDrive

Uninstalled from Settings → Apps → Installed apps → Microsoft OneDrive → Uninstall. Afterwards, `OneDrive.exe` is in neither `%LOCALAPPDATA%\Microsoft\OneDrive` nor `%ProgramFiles%\Microsoft OneDrive`.

### Git for Windows

`winget install --id Git.Git -e --source winget`, run from `operator`, installs Git **per-user** under `%LOCALAPPDATA%\Programs\Git`, not `C:\Program Files\Git`. `git.exe` is at `...\Programs\Git\cmd\git.exe`, and Git's bundled OpenSSH is in `...\Programs\Git\usr\bin\`. The verify script looks in both locations.

### SSH client for GitHub

On 2026-10-21, Windows' built-in OpenSSH (`C:\Windows\System32\OpenSSH\ssh.exe`, OpenSSH_for_Windows 9.5p2) failed to connect to GitHub:

```text
choose_kex: unsupported KEX method sntrup761x25519-sha512@openssh.com
```

A re-test later the same day negotiated `curve25519-sha256` and connected, so the failure doesn't happen every time. Either way, the clone pins Git's newer OpenSSH (10.5p1) for this repo, and the verify script sets it:

```powershell
git config core.sshCommand '"C:/Users/operator/AppData/Local/Programs/Git/usr/bin/ssh.exe"'
```

The `github-sha` alias in `~\.ssh\config` (no BOM) is shared by both clients. `ssh -T git@github-sha` greets with `Hi avictorio/sha! You've successfully authenticated, but GitHub does not provide shell access.`
