# Setup guide

Owner-facing steps that can't be scripted, one section per task. Scripted steps live in `installer/steps/`, their checks in `verify/checks/`. The reasons behind these steps are in docs/LESSONS.md.

## operator-account

PLAN.md P0.0a (owner) and P0.0b (Claude). Claude's part is scripted in `installer/steps/00-operator.ps1` and `verify/checks/p0-0b-operator.ps1`.

### Owner's steps (P0.0a)

About 20–30 minutes. Claude can't create the account it runs in.

1. **Create `operator`:** Settings → Accounts → Other users → Add account → "I don't have this person's sign-in information" → "Add a user without a Microsoft account". Change its account type to **Administrator** (verify the exact labels), and check that it took.
2. **Sign in as `operator`.** Sign in to nothing personal there: no Microsoft account, OneDrive, personal browser profile, Telegram or password manager.
3. **Claude desktop app:** install it, sign in, and turn on Settings → This computer → Computer use (off by default).
4. **Git for Windows**, before Claude Code. See [Git for Windows](#git-for-windows).
5. **Claude Code.** See [Claude Code](#claude-code).
6. **Browser tool** (verify the exact install steps): Chrome plus the Claude in Chrome extension, signed in, or the desktop app's built-in browser. This is `operator`'s admin browser, not the agent's Chrome profile (`C:\agent\chrome`, in `hermes`).
7. **Start the session** on the Legion, in `operator`, from the desktop app or Claude Code, with the [starter prompt](../README.md#starter-prompt). A cloud session can't run commands on the machine.

Done when: the desktop app runs in `operator` with computer use available; `git --version` and `claude --version` work in PowerShell; the browser tool opens a web page.

#### Git for Windows

From PowerShell in `operator`:

```powershell
winget install --id Git.Git -e --source winget
```

This installs Git per-user under `%LOCALAPPDATA%\Programs\Git`; its OpenSSH is in `...\Programs\Git\usr\bin\`. P0.0b connects to GitHub with it (see [SSH client for GitHub](#ssh-client-for-github)).

#### Claude Code

From PowerShell in `operator`:

```powershell
irm https://claude.ai/install.ps1 | iex
```

It installs into `~\.local\bin`. If the desktop app's Code mode runs commands locally, it can stand in for the CLI (verify).

### Claude's steps (P0.0b)

1. **Confirm the tools.** `00-operator.ps1` checks `git` and `claude` are on PATH. It installs nothing; if one is missing, it hands back to P0.0a.
2. **Privacy settings and OneDrive.** See [Privacy settings](#privacy-settings-windows-settings) and [OneDrive](#onedrive).
3. **Deploy key.** `00-operator.ps1` creates `~\.ssh\sha_deploy` (ed25519), adds the `github-sha` alias to `~\.ssh\config`, and prints the public key. The private key never leaves `operator`.
   - **Owner:** from your phone or your own account (never signed in on `operator`), add the public key at GitHub → the repo's Settings → Deploy keys, with "Allow write access" ticked. In the same visit, add a rule on `main` requiring a pull request before merging. Branch rules are free on a public repo; a private one needs GitHub Pro or higher (verify).
4. **Host key, clone, identity and checks.** `verify/checks/p0-0b-operator.ps1` trusts GitHub's host keys only if they match GitHub's published fingerprints, clones `git@github-sha:avictorio/sha.git` to `$HOME\sha`, sets the repo-local commit identity (default: the owner's GitHub noreply address) and `core.sshCommand`, and prints PASS/FAIL for each Done-when check.
5. **Start `claude` in the clone** and check that it reads CLAUDE.md.

#### Privacy settings (Windows Settings)

The one list, for every account set up on this machine (`operator` in P0.0b, `hermes` in P0.5):

- **Advertising ID:** Settings → Privacy & security → General → **off**.
- **Diagnostic data:** Settings → Privacy & security → Diagnostics & feedback → **Required diagnostic data** only.
- **Windows backup / settings sync:** Settings → Accounts → Windows backup → everything **off**.
- **OneDrive:** sign nothing in; see [OneDrive](#onedrive).

#### OneDrive

Uninstall it: Settings → Apps → Installed apps → Microsoft OneDrive → Uninstall. Afterwards `OneDrive.exe` is in neither `%LOCALAPPDATA%\Microsoft\OneDrive` nor `%ProgramFiles%\Microsoft OneDrive`.

#### SSH client for GitHub

The clone uses Git's OpenSSH, not Windows' built-in client (why: docs/LESSONS.md, Git and GitHub). The verify script sets:

```powershell
git config core.sshCommand '"C:/Users/operator/AppData/Local/Programs/Git/usr/bin/ssh.exe"'
```

`ssh -T git@github-sha` should greet with `Hi avictorio/sha! You've successfully authenticated…`.

## domain-and-mailbox

PLAN.md P0.2, D4 and D5. No custom domain and no DNS (D4): AgentMail Free on `agentmail.to`. Two inboxes (D5), one per profile. Login codes for your accounts come to your own email (D15). Everything here is in the AgentMail web console; nothing to script.

1. Sign up at agentmail.to on the Free plan.
2. Create the first inbox, `<name>@agentmail.to`. This is the **local profile's** inbox (older text calls it "main"). The default profile's inbox follows in P2.2.
3. Create an API key and store it in your password manager. This full key never goes into Hermes: Claude uses it only at a hidden prompt for admin calls (S8, P2.2). Each profile gets its own scoped, receive-only key (PLAN.md §7).
4. From your personal address, send the inbox a test message and check it appears in the console.

## host-prep

PLAN.md P0.3. Scripted in `installer/steps/01-host.ps1`, checked by `verify/checks/p0-3-host.ps1`.

### Running 01-host.ps1

- `operator` must be an administrator ([P0.0a](#operator-account)). If it was added during the current sign-in, the admin prompt asks for credentials: enter **`operator`**'s, not yours.
- Type the `hermes` password at the hidden prompt, and save it in your password manager. It never expires, so Autologon keeps working.

### Autologon (Sysinternals)

The script installs it to `%LOCALAPPDATA%\Microsoft\WinGet\Packages\Microsoft.Sysinternals.Autologon_*\Autologon64.exe`. Run it as administrator, accept the license, enter username `hermes`, the computer name as the domain and the `hermes` password, then click **Enable**. The password is stored as an LSA secret.

### Device encryption (owner's account)

In your own Microsoft account: Settings → Privacy & security → Device encryption → on. Check that the recovery key is listed at account.microsoft.com/devices/recoverykey.

### Windows Update

Settings → Windows Update → **Download & install all**. Driver updates may be under Advanced options → Optional updates. Set Advanced options → Active hours.

### Battery conservation

Turn it on in Lenovo Vantage or Legion Space from your account; neither is installed in `operator`.

## router-and-tailscale

### DHCP reservation

In the router's admin page, reserve the laptop's current IPv4 address for its Wi-Fi MAC address (and the Ethernet MAC, if used). Get both with:

```powershell
Get-NetAdapter -Physical | Format-Table Name, MacAddress, Status
Get-NetIPConfiguration | Where-Object IPv4DefaultGateway
```

### Tailscale

`01-host.ps1` installs it. Approve the device from your phone, so nothing stays signed in on the machine:

```powershell
& "$env:ProgramFiles\Tailscale\tailscale.exe" up --unattended
```

Open the printed `https://login.tailscale.com/a/...` link on your phone, sign in and approve. (The device login in `operator`'s browser profile is also allowed; sign out afterwards.) `tailscale debug prefs` then shows `"ForceDaemon": true`. Close the installer's "connect this device" window.

## ollama

PLAN.md P0.4. Scripted in `installer/steps/02-ollama.ps1` (elevated; then `-PullOnly`, unelevated, for the models), checked by `verify/checks/p0-4-ollama.ps1`. Versions and tags are pinned in `versions.lock`.

### NVIDIA driver

The driver must support CUDA 12.8 or higher, or Ollama silently runs on the CPU (docs/LESSONS.md, Windows, hardware and Docker). Update it from your account through Lenovo Vantage → System Update, the NVIDIA app → Drivers, or nvidia.com/drivers (621.01 works). After a reboot, the Ollama log shows `inference compute ... library=CUDA ... NVIDIA GeForce RTX 4080 Laptop GPU`.

## docker-autostart

PLAN.md P0.5. Scripted in `installer/steps/03-docker.ps1` (elevated; reboot afterwards), checked by `verify/checks/p0-5-docker.ps1`.

### The owner's sign-in as hermes

Claude never works in `hermes`, so you do this once:

1. Sign in as `hermes` with the password from your password manager.
2. Apply the [privacy settings](#privacy-settings-windows-settings). If OneDrive is present for this account, uninstall it.
3. Start Docker Desktop, accept the Docker Subscription Service Agreement (free for personal use; D14), and **skip** the Docker sign-in. In Settings → General, tick **"Start Docker Desktop when you sign in to your computer"** and click Apply.
4. Lock the screen (Win+L). Don't sign out: that stops Docker and Hermes.

Docker can't start before sign-in (notes #17), so it depends on `hermes`'s auto-logon.

## telegram-bots

PLAN.md P0.7. Scripted in `installer/steps/05-telegram.ps1` (elevated, visible window), checked by `verify/checks/p0-7-telegram.ps1` (elevated, after an unattended reboot).

### The owner's steps, on the phone

1. **Create the bot.** In Telegram, open **@BotFather** (blue verified tick), send `/newbot`, and give a display name (e.g. "Hermes") and a username ending in `bot`. Save the token in your password manager as "Hermes Telegram bot token". Never paste it into chat.
2. **Get your numeric ID** from **@userinfobot**. It's personal, not secret: it goes into `instance.yaml`/`.env`, never the repo.
3. **Open a chat with your bot** (`t.me/<username>`) and press **Start**.

### Running 05-telegram.ps1

Type three things at its prompts: your numeric ID; the bot token (hidden prompt, written straight to `hermes`'s `.env`); the `hermes` password. It writes the allow-list before the token, installs the Telegram extra, registers the guarded `Hermes_Gateway` logon task and waits for "telegram connected". `-GatewayOnly` repeats the last steps without the prompts.

**Don't use `hermes gateway install` or follow `gateway status`'s "Repair" hint**; it would replace the guarded task (docs/LESSONS.md, Hermes). Restart a gateway with `scripts/restart-gateway.ps1 -Profile <p>`.

### Checks

- **On the phone:** the bot answers you. A second Telegram account gets no reply, and `gateway.log` shows `[Telegram] Blocked unauthorized user <id>`.
- **After an unattended reboot:** `p0-7-telegram.ps1` passes and the bot answers. Messages sent while the gateway was down are dropped: send a new one.

## local-bot

PLAN.md P1.3 and P1.10. The local profile (`local`, formerly `private`) uses only the laptop's model, with its own bot ("Hermes Local") and its own guarded task, `Hermes_Gateway_local`. Scripted in `installer/steps/06-local-profile.ps1` (elevated, visible window), checked by `verify/checks/p1-3-local.ps1`.

The rule: **if you wouldn't send it to a cloud provider, tell it to the local bot.**

### The owner's steps

1. **Create the bot** as in [telegram-bots](#telegram-bots), named e.g. "Hermes Local". Save the token as "Hermes Local Telegram bot token", open a chat and press **Start**.
2. **Run `06-local-profile.ps1 -Phase Create`** and type the `hermes` password.
3. **Run `06-local-profile.ps1 -Phase Bot`.** Type the `hermes` password, then paste the token at the hidden prompt. Your Telegram ID is copied from the default profile.

### Why `gateway.standalone: true`

It gives the local profile its own gateway; without it, v0.22.4's default gateway would also serve the local bot (docs/LESSONS.md, Hermes). `start-gateway.ps1 -Profile local` refuses to start without it. Recheck after every `hermes update` (P5.2).

### Tests in Telegram (P1.3 Done when)

1. **It answers.** Send "hello". It replies, and `C:\agent\shared\logs\usage-local.jsonl` gets a line with `"platform": "telegram"` and `"local": true`.
2. **It can't switch to a cloud model.** `/model openrouter:openai/gpt-4o-mini` must fail or refuse, and the next reply still comes from the local model.
3. **It doesn't fall back to the cloud.** Run `verify/checks/p1-3-ollama-stop-test.ps1` elevated; it stops Ollama. Ask the local bot something: it must reply with an error. Press Enter to restart Ollama (it restarts by itself after 10 minutes).

## openrouter

PLAN.md P1.4, D9. The cloud profile (`default`) is **cloud-first**: `meta/muse-wonder` through OpenRouter, falling back to the local `qwen3-coder:30b` on cloud errors. The local profile never gets the key. Scripted in `installer/steps/07-cloud.ps1` (elevated, visible window), checked by `verify/checks/p1-4-cloud.ps1`.

### The owner's steps

1. **Account.** Sign up at openrouter.ai and add credit (Claude stops at payment screens).
2. **Privacy** (openrouter.ai/settings/privacy). Turn **off** every option that lets providers train on your prompts. Leave "Zero Data Retention only" **off**: it excludes Muse Wonder (docs/LESSONS.md, OpenRouter).
3. **Key.** Under Keys, create `hermes-default` with a **$50** limit that **resets monthly**, and save it in your password manager.
4. **Run `07-cloud.ps1`.** Paste the key at the hidden prompt with a **right-click**, confirm "monthly" (OpenRouter doesn't report it), then type the `hermes` password. It refuses a key with no limit or one over versions.lock's `cloud_key_limit_usd`. `-SkipKey` reruns everything but the key. Close any earlier window first.

### What the check proves

- **The cloud model answers:** a chat is logged with `"local": false` and `meta/muse-wonder`.
- **The fallback works:** with `model.default` briefly set to a nonexistent model, the reply is logged `"local": true`; then `config.yaml` is restored. A message to the default bot during that minute may get a local answer.
- **`hermes usage --provider openrouter`** shows the limit and "resets monthly".
- **Not tested: an exhausted key** (402, mapped to a billing failover). (verify) when the cap is first reached.

### Costs to watch

After the P1.9 token diet, a fresh chat sends about 10,000 tokens of context, costing Muse Wonder about 4–9¢ per message. Side tasks (titles, compression, vision) run on the local model, and the delegation toolset (subagents) is off. Long chats grow: send `/new` to start fresh. Check spend at openrouter.ai/activity; the key's $50 monthly cap is the hard stop.

## seed-memory

PLAN.md P1.6. The default bot is cloud-first, so its memory goes to OpenRouter with every message. The rule from [local-bot](#local-bot) applies.

1. **Default bot.** Copy `config/templates/USER.default.md` **outside the repo**, fill in only cloud-OK facts, and run `scripts/seed-user-memory.ps1 -FromFile <your copy>` elevated (type the `hermes` password). It writes `USER.md` into the profile's memories folder; `-Force` replaces an existing one (the old one is kept as a backup). Don't rely on telling the bot "remember this": a cloud model claimed to save memory and wrote nothing (docs/LESSONS.md, Hermes).
2. **Local bot.** Tell it anything personal (health, finances) directly, and only there.
3. **Check (Done when).** `USER.md` exists in `%LOCALAPPDATA%\hermes\memories` (as `hermes`). Ask each bot "what do you know about me?": the default bot lists only the cloud-OK facts; the local bot knows only what you told it.

## backup

PLAN.md P1.7. `installer/steps/09-backup.ps1` (elevated) sets up `Agent_Backup`: `C:\agent\bin\backup.ps1` runs as `hermes` at 03:30, writes `D:\backups\hermes-<time>.7z` encrypted, and keeps 14 days. Log: `C:\agent\shared\logs\backup.log`.

- **The passphrase.** Choose it at the hidden prompt: 12+ characters, no double quotes. Keep a copy in your password manager; losing it means the backups can't be opened. The unattended task reads it from `C:\agent\bin\backup-passphrase.txt` (hermes and admins only). `-NewPassphrase` replaces it; older archives keep the old one.
- **Restore.**
  1. Open the `.7z` with 7-Zip and the passphrase.
  2. As `hermes`, `hermes import hermes-<time>.zip` restores Hermes, both profiles included.
  3. Copy `workspace`, `local` and `shared` back to `C:\agent`.
- **Check.** `verify/checks/p1-7-backup.ps1` (elevated) proves the newest archive is locked without the passphrase and complete with it.
