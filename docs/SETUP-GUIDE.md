# Setup guide

Steps that can't be scripted, or that were done by hand, one section per task. Scripted steps live in `installer/steps/` and their checks in `verify/checks/`.

## operator-account

PLAN.md P0.0a and P0.0b. The owner creates `operator` and installs Claude's tools (P0.0a). Claude then confirms the tools, applies the privacy settings and sets up repo access (P0.0b). Claude's part is scripted in `installer/steps/00-operator.ps1` (tool check, deploy key, SSH alias) and `verify/checks/p0-0b-operator.ps1` (host key, clone, commit identity, Done-when checks); the rest is written down below. The findings are from the Legion on 2026-10-21, when Claude still installed Git and Claude Code itself in P0.0b.

### Owner's steps (P0.0a)

About 20–30 minutes. Claude can't create the account it runs in.

1. **Create `operator`:** Settings → Accounts → Other users → Add account → "I don't have this person's sign-in information" → "Add a user without a Microsoft account". Then change its account type to Administrator (verify the exact labels). Check that the change took: on the Legion, `operator` was first left a standard user, P0.0b passed anyway, and P0.3 then failed until the owner added `operator` to Administrators. The P0.0b verify script now checks this (`operator-admin`).
2. **Sign in as `operator`.** Don't sign in to anything personal there: no Microsoft account, OneDrive, personal browser profile, Telegram or password manager.
3. **Claude desktop app:** install it and sign in. Turn on computer use: Claude desktop app → Settings → This computer → Computer use (off by default).
4. **Git for Windows**, before Claude Code. See [Git for Windows](#git-for-windows).
5. **Claude Code.** See [Claude Code](#claude-code).
6. **Browser tool** for websites (verify the exact install steps): install Chrome plus the Claude in Chrome extension and sign in to it, or enable the desktop app's built-in browser. This is `operator`'s own admin browser, not the agent's Chrome profile (`C:\agent\chrome`, which runs in `hermes`).
7. **Start the session** on the Legion, in `operator`, from the Claude desktop app or Claude Code, with the [starter prompt](../README.md#starter-prompt). A cloud session (Slack, or claude.ai on the web) can't reach the machine unless it's linked from the claude.ai composer's + menu → Devices; even then terminals are click-only, so commands still need a local session.

Done when: the Claude desktop app is running in `operator` with computer use available; `git --version` and `claude --version` work in PowerShell there; and the browser tool can open a web page.

#### Git for Windows

Install it from PowerShell in `operator`:

```powershell
winget install --id Git.Git -e --source winget
```

Run from `operator`, this installs Git **per-user** under `%LOCALAPPDATA%\Programs\Git`, not `C:\Program Files\Git`. `git.exe` is at `...\Programs\Git\cmd\git.exe`, and Git's bundled OpenSSH is in `...\Programs\Git\usr\bin\`. The verify script looks in both locations. P0.0b connects to GitHub with Git's OpenSSH (see [SSH client for GitHub](#ssh-client-for-github)). Git goes first because Claude Code on native Windows is believed to need it (verify).

#### Claude Code

Install it with the official native Windows installer, from PowerShell in `operator`:

```powershell
irm https://claude.ai/install.ps1 | iex
```

On the Legion this installed Claude Code 2.1.307 into `~\.local\bin`. Both P0.0b scripts add `~\.local\bin` to PATH for their own session. If the desktop app's Code mode runs commands locally, it can stand in for the CLI (verify).

### Claude's steps (P0.0b)

1. **Confirm the tools.** `00-operator.ps1` checks that `git` and `claude` are on PATH and prints their versions; running it from Claude's session also shows that the session can run PowerShell. It installs nothing: if either tool is missing, it stops and points back to P0.0a.
2. **Privacy settings**, in Windows Settings. See [Privacy settings](#privacy-settings-windows-settings) and [OneDrive](#onedrive).
3. **Deploy key.** `00-operator.ps1` creates `~\.ssh\sha_deploy` (ed25519, empty passphrase), adds the `github-sha` alias to `~\.ssh\config` without a BOM, and prints the public key and its fingerprint. The private key never leaves `operator`.
   - **Owner:** paste the public key into GitHub → the repo's Settings → Deploy keys → Add deploy key, with "Allow write access" ticked. Do it from your phone or your own account, so your GitHub account is never signed in on `operator`. In the same visit, add a rule on `main` requiring a pull request before merging, because the deploy key could otherwise push to `main`. Branch rules are free on a public repo; a private one needs GitHub Pro or higher (verify the current plan terms).
4. **Host key, clone, commit identity and checks.** Once the deploy key and the `main` rule exist, run `verify/checks/p0-0b-operator.ps1`. It:
   - trusts GitHub's SSH host keys only if every scanned key matches GitHub's published fingerprints (docs.github.com, "GitHub's SSH key fingerprints", read 2026-10-21);
   - clones `git@github-sha:avictorio/sha.git` to `$HOME\sha` (`-CloneDir`);
   - sets the repo-local commit identity (`-CommitName`, default `Claude (Legion operator)`; `-CommitEmail`, default the owner's GitHub noreply address, which keeps a personal email out of the history) and pins `core.sshCommand`;
   - runs the Done-when checks, printing PASS or FAIL for each.
5. **Start `claude` in the clone** and check that it reads CLAUDE.md.

On 2026-10-21 every check passed: `host-key`, `ssh-greeting`, `clone`, `push-legion-test`, `main-rejects-direct-push` (GH013, pull request required), `onedrive-absent`, `advertising-id-off`, `no-microsoft-account` and `claude-code-installed`. Claude started in the clone read CLAUDE.md. `operator-admin` was added later; the same check in `p0-3-host.ps1` passed once the owner had added `operator` to Administrators.

#### Privacy settings (Windows Settings)

- **Advertising ID:** Settings → Privacy & security → General. It was already off. (`HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo` `Enabled` = 0.)
- **Diagnostic data:** Settings → Privacy & security → Diagnostics & feedback. It was already "Required only". (`HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection` `AllowTelemetry` = 1.)
- **Windows Backup / settings sync:** Settings → Accounts → Windows backup. It was already off.

#### OneDrive

Uninstalled from Settings → Apps → Installed apps → Microsoft OneDrive → Uninstall. Afterwards, `OneDrive.exe` is in neither `%LOCALAPPDATA%\Microsoft\OneDrive` nor `%ProgramFiles%\Microsoft OneDrive`.

#### SSH client for GitHub

On 2026-10-21, Windows' built-in OpenSSH (`C:\Windows\System32\OpenSSH\ssh.exe`, OpenSSH_for_Windows 9.5p2) failed to connect to GitHub:

```text
choose_kex: unsupported KEX method sntrup761x25519-sha512@openssh.com
```

A re-test later the same day negotiated `curve25519-sha256` and connected, so the failure doesn't happen every time. Either way, the clone pins Git's newer OpenSSH (10.5p1, installed with Git in P0.0a) for this repo, and the verify script sets it:

```powershell
git config core.sshCommand '"C:/Users/operator/AppData/Local/Programs/Git/usr/bin/ssh.exe"'
```

The `github-sha` alias in `~\.ssh\config` (no BOM) is shared by both clients. `ssh -T git@github-sha` greets with `Hi avictorio/sha! You've successfully authenticated, but GitHub does not provide shell access.`

## domain-and-mailbox

PLAN.md P0.2, per D4 and D5: the AgentMail Free plan, with one inbox and no custom domain. Everything is done in the AgentMail web console by the owner; there is nothing to script.

1. Sign up at agentmail.to on the Free plan.
2. Create one inbox, `<name>@agentmail.to`. This is "main": it receives all designated mail, sorted by sender domain and subject tags (PLAN.md §7). The otp inbox is added in P2.2.
3. Create an API key and store it in your password manager. This full key never goes into Hermes: Claude uses it only through a hidden prompt for admin calls (S8, P2.2), and Hermes gets a separate read-only key scoped to main (PLAN.md §7).
4. From your personal address, send a test message to the inbox and check that it appears in the console.

There is no DNS to set up: MX, SPF, DKIM and DMARC are AgentMail's on `agentmail.to`.

## host-prep

PLAN.md P0.3. The scripted parts are in `installer/steps/01-host.ps1` and the checks in `verify/checks/p0-3-host.ps1`.

### Running 01-host.ps1

- `operator` must be in the local Administrators group ([P0.0a](#operator-account)). If it was added during the current sign-in, the admin prompt asks for credentials: enter **`operator`** and its password, not the owner's account. The script refuses to run as any other user.
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

`01-host.ps1` installs it with winget. Either sign-in route is fine: CLAUDE.md allows the Tailscale device login in `operator`'s browser profile (the owner types the credentials, and signs out afterwards), or the owner approves the device from a phone link. The Legion used the phone link, which leaves nothing signed in on the machine:

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

## telegram-bots

PLAN.md P0.7. The scripted parts are in `installer/steps/05-telegram.ps1` (run elevated, in a visible window) and the checks in `verify/checks/p0-7-telegram.ps1` (run elevated, after an unattended reboot).

### The owner's steps, on the phone

1. **Create the bot.** In Telegram, open **@BotFather** (check the blue verified tick) and send `/newbot`. Give it a display name (e.g. "Hermes") and a username ending in `bot`. BotFather replies with the bot token (`123456789:AA…`). Save it in the password manager as "Hermes Telegram bot token". It is a secret: don't paste it into chat.
2. **Get your numeric ID.** Open **@userinfobot** and send it any message. It replies with your numeric ID. The ID isn't a secret, but it is personal: it goes into `instance.yaml`/`.env`, never into the repo.
3. **Open a chat with your bot** (the `t.me/<username>` link BotFather gives) and press **Start**, so the bot can message you.

### Running 05-telegram.ps1

The owner types three things into its prompts:
- the numeric ID (plain prompt);
- the bot token (hidden prompt; it goes straight into `hermes`'s `.env`, never on a command line or in a log);
- the `hermes` password (hidden, for `scripts/invoke-as-hermes.ps1`).

It writes `TELEGRAM_ALLOWED_USERS` and `TELEGRAM_HOME_CHANNEL` before the token. Then, as `hermes`, it installs the Telegram extra (`hermes pm install --extra telegram`) and confirms that Hermes reads the allow-list back. Finally it registers the `Hermes_Gateway` logon task and waits for "telegram connected" in `gateway.log`. `-GatewayOnly` repeats the last steps without the prompts.

**Don't use `hermes gateway install`, and don't follow its "Repair: hermes gateway start" hint.**
- As a standard user, `gateway install` hangs at a UAC y/N prompt.
- Our `Hermes_Gateway` task instead runs `C:\agent\bin\start-gateway.ps1`. That guard refuses to start the gateway without `TELEGRAM_ALLOWED_USERS` and logs to `start-gateway.log` in `hermes`'s `logs` folder.
- `hermes gateway status` flags our task as "predating the current template". That warning is expected. Following its repair hint would replace the guarded task with Hermes's own.

### Checks

- **On the phone:** the bot answers you. A message from a second Telegram account gets no reply, and `gateway.log` shows `[Telegram] Blocked unauthorized user <id>`.
- **After an unattended reboot:** `verify/checks/p0-7-telegram.ps1` passes, and the bot answers again. Messages sent while the gateway was down are dropped, so send a new one.
