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

## domain-and-mailbox

PLAN.md P0.2, per D4 and D5: the AgentMail Free plan, with one inbox and no custom domain. Everything is done in the AgentMail web console by the owner; there is nothing to script.

1. Sign up at agentmail.to on the Free plan.
2. Create one inbox, `<name>@agentmail.to`. It receives everything; there are no per-designation addresses.
3. Create an API key and store it in your password manager. It goes into Hermes's `.env` later (P2.2), typed into a hidden prompt.
4. From your personal address, send a test message to the inbox and check that it appears in the console.

There is no DNS to set up: MX, SPF, DKIM and DMARC are AgentMail's on `agentmail.to`.

## host-prep

PLAN.md P0.3. The scripted parts are in `installer/steps/01-host.ps1` and the checks in `verify/checks/p0-3-host.ps1`.

### Running 01-host.ps1

- `operator` must be in the local Administrators group. If it was added during the current sign-in, the admin prompt asks for credentials: enter **`operator`** and its password, not the owner's account. The script refuses to run as any other user.
- It asks for the `hermes` password at a hidden prompt. The owner types it there and also saves it in their password manager.
- `hermes` is created with a password that never expires, because an expiring password would quietly stop Autologon from working.

### Autologon (Sysinternals)

The script installs it with winget, to `%LOCALAPPDATA%\Microsoft\WinGet\Packages\Microsoft.Sysinternals.Autologon_*\Autologon64.exe`. Run it as administrator, accept the license, enter username `hermes`, the computer name as the domain and the `hermes` password, then click **Enable**. The password is stored as an LSA secret, not in plain text in the registry.

### Device encryption (owner's account)

Sign in to the owner's Microsoft account, then go to Settings → Privacy & security → Device encryption and turn it on. Windows 11 Home backs up the recovery key to the account that turns encryption on, so check that it's listed at account.microsoft.com/devices/recoverykey.

### Windows Update

Settings → Windows Update → **Download & install all**. Driver updates can sit under Advanced options → Optional updates. Set active hours under Advanced options → Active hours.

### Battery conservation

Turn it on in Lenovo Vantage or Legion Space from the owner's account; neither app is installed in `operator`.

## router-and-tailscale

### DHCP reservation

In the router's admin page, reserve the laptop's current IPv4 address for its Wi-Fi adapter's MAC address. If Ethernet will be used, reserve the Ethernet adapter's MAC address too. Get both addresses with:

```powershell
Get-NetAdapter -Physical | Format-Table Name, MacAddress, Status
Get-NetIPConfiguration | Where-Object IPv4DefaultGateway
```

### Tailscale

`01-host.ps1` installs it with winget. Don't sign in from a browser in `operator`, because that would leave the owner's account signed in there. Instead, run:

```powershell
& "$env:ProgramFiles\Tailscale\tailscale.exe" up --unattended
```

It prints a `https://login.tailscale.com/a/...` link. The owner opens the link on their phone, signs in and approves the device. `--unattended` keeps Tailscale running when nobody is signed in; `tailscale debug prefs` then shows `"ForceDaemon": true`. The installer's "connect this device" window can be closed.

## ollama

PLAN.md P0.4. The scripted parts are in `installer/steps/02-ollama.ps1` (run elevated; then `-PullOnly`, unelevated, for the models) and the checks in `verify/checks/p0-4-ollama.ps1`. Versions and model tags are pinned in `versions.lock`.

### NVIDIA driver

Ollama's CUDA libraries need a recent driver. With driver 546.92 (CUDA 12.3), GPU detection crashed (`llama-server --list-devices failed: exit status 0xc0000005`), and Ollama fell back to the CPU (`inference compute id=cpu`, `total_vram="0 B"`). Update the driver from the owner's account through Lenovo Vantage → System Update, the NVIDIA app → Drivers, or nvidia.com/drivers. Driver 621.01 (CUDA 13) works. After a reboot, the Ollama log shows `inference compute ... library=CUDA ... NVIDIA GeForce RTX 4080 Laptop GPU`.

## docker-autostart

PLAN.md P0.5. The scripted parts are in `installer/steps/03-docker.ps1` (run elevated: WSL, Docker Desktop, `hermes` added to `docker-users`; reboot afterwards) and the checks in `verify/checks/p0-5-docker.ps1`.

### The owner's sign-in as hermes

Claude never works in `hermes`, so the owner does this once:

1. Sign in as `hermes`, using the `hermes` password from the password manager. After an auto-logon it sits at the lock screen.
2. Privacy settings, the same as `operator` (P0.0b):
   - Settings → Privacy & security → General: advertising ID **off**.
   - Settings → Privacy & security → Diagnostics & feedback: **Required diagnostic data** only.
   - Settings → Accounts → Windows backup: everything **off**.
   - OneDrive: if it's running, quit it and sign nothing in. It was uninstalled machine-wide in P0.0b; if it's present for this account anyway, uninstall it from Settings → Apps.
3. Docker Desktop: start it, accept the Docker Subscription Service Agreement (free for personal use; see D14), and **skip** the Docker sign-in. Then go to Settings → General, tick **"Start Docker Desktop when you sign in to your computer"**, and click Apply.
4. Lock the screen (Win+L). Don't sign out: that would stop Docker and Hermes.

There is no option to start Docker Desktop before sign-in (notes #17), so Docker depends on `hermes`'s auto-logon.
