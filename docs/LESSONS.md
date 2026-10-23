# Lessons learned

Rules for building on the Legion Pro 7i (Windows 11 Home 26200), each with the fact about this machine or Hermes that makes it necessary and, where one exists, the script or check that enforces it. This file is the single home for the why; PLAN.md and docs/SETUP-GUIDE.md point here by section name.

## Running things (elevation, as hermes, PowerShell 5.1)

### Accounts and elevation

- **`operator` must be a local administrator; check it, don't print it.** With `operator` a standard user, admin prompts fall through to the owner's account. Enforced by: `verify/checks/p0-0b-operator.ps1` (`operator-admin`).
- **Right after `operator` joins Administrators, the admin prompt asks for credentials: type `operator`'s, never the owner's.** It stays that way until `operator` signs in again.
- **Run as `hermes` only through `scripts/invoke-as-hermes.ps1`.** `Start-Process -Credential` and `runas` fail with "Access is denied" (Win32 error 5) here, although the logon itself succeeds (Security 4624). The helper runs a one-shot scheduled task and deletes it and its stored password afterwards.
- **`hermes` needs "Log on as a batch job" (`SeBatchLogonRight`).** Without it the one-shot task never starts (`LastTaskResult` 0x00041303) and gives no error. Enforced by: `installer/steps/01-host.ps1`; the helper fails within 20 s if the task hasn't started.
- **Batch all as-`hermes` steps behind one password prompt, and chain the verify script into the same elevated run.** Each prompt is an owner interruption, and a separate verify run means another one.
- **Generated commands are parse-checked before they run.** A command that doesn't parse (e.g. `"$name:"`, which reads as a scope-qualified variable; write `"${name}:"`) makes the task exit without `rc.txt`. Enforced by: `scripts/invoke-as-hermes.ps1`, which also redacts secrets in output.
- **Elevated runs: `Start-Process -Verb RunAs -Wait` with `-File` and a fresh `-LogPath` transcript per run; no `-NoExit`.** Inline `-Command` text mangles double quotes, and a `-NoExit` window that stopped on an error keeps its transcript locked. Use a visible window when the script has a hidden prompt.
- **Don't poll an elevated window from an unelevated shell; wait for the background-task notification.** An unelevated process can't read an elevated one's command line, so "is it still open?" returns false while it is open.
- **Use `Read-Host -AsSecureString` in a visible window, not `Get-Credential`.** Its dialog never appears here (DCOM 10010, ConsentUxService).
- **Paste into a hidden prompt with a right-click.** Ctrl+V can fail without any sign.
- **Clicking in a console window freezes the script at its next write (QuickEdit).** Esc resumes it. Enforced by: `bench/run-bench.ps1`, which turns QuickEdit off.

### What an unelevated `operator` can't see

Decide per verify script whether it runs elevated, and guard for it. Unelevated on Windows 11 Home:

- `GetOwner` on another user's process returns 2 (access denied); `Get-Process` `StartTime` is empty for SYSTEM processes (use `Win32_Process.CreationDate`).
- `Get-ScheduledTask` doesn't list tasks whose principal is `hermes` (including leftover `hermes-oneshot-*` tasks).
- `C:\agent` is unreadable by design (only `hermes`, Administrators, SYSTEM).
- `query user`/`quser` don't exist on Home; `Win32_LoggedOnUser` shows only your own logons.
- `manage-bde` needs admin (the shell property `System.Volume.BitLockerProtection` doesn't); `Get-AppxPackage -AllUsers` is denied.

### Running hermes from scripts

- **Every hermes CLI call gets a timeout and an empty stdin (the `Cap` helper).** A subcommand can block on a prompt, and in a windowless task that waits forever.
- **Use `hermes chat -Q -q '…'` for one-shot prompts, with no double quotes in the prompt** (or `--query-file`). Double quotes inside a native argument are mangled in PS 5.1.
- **Set `[Console]::OutputEncoding` to UTF-8 and `PYTHONIOENCODING=utf-8` in as-`hermes` commands.** Otherwise ✓/✗ arrive as mojibake, and a check for ✗ passes because it reads nothing; checks also require the ✓ marks.
- **No Python for `operator`; Hermes's venv Python works as `hermes`.** `04-hermes.ps1 -Configure` uses it with `ruamel.yaml` to deep-merge config templates.

### PowerShell 5.1 pitfalls

- **Wrap native calls in `$ErrorActionPreference = 'Continue'` and judge by `$LASTEXITCODE`.** Under `'Stop'`, stderr progress (e.g. `ollama pull`) is a terminating error. `wsl.exe` writes UTF-16: strip `` `0 ``.
- **Download with `-OutFile` and read the file.** `Invoke-WebRequest ... .Content` is a byte array for `application/octet-stream`.
- **Log with `Start-Transcript`, not `Tee-Object`.** Terminating errors bypass the pipeline and vanish from a `Tee-Object` log.
- **Use `-CaseSensitive` and anchor matches to something distinctive.** `Select-String`/`-match` ignore case: `Listening on` also matches model runners' `listening on`, which makes a working GPU read as "no GPU" (anchor on `msg="Listening on`).
- **Keep script files ASCII; write non-ASCII as `[char]0x2014`.** PS 5.1 reads a BOM-less `.ps1` as ANSI, so an em dash in a regex never matches.
- **Copy `$Matches` (`$m = $Matches.Clone()`) before any other `-match`.** Every successful match overwrites it.
- **`$null` passed to a `[string]` parameter arrives as `""`.** Use a `-Remove` switch rather than "pass null to delete".
- **Variable names ignore case:** `$force = '…'` reassigns a `[switch]$Force` parameter.
- **`H` is the alias for Get-History,** so a function named `H` is never called. Use another name (`Herm`).
- **`powershell -File s.ps1 -Tasks B2,B6` passes one string, not an array;** `-Flag --value` fails with "Missing an argument". Split comma lists inside the script.
- **Unroll `ConvertFrom-Json` arrays with `ForEach-Object { $_ }`, and read UTF-8 with `-Encoding UTF8`** (else non-breaking spaces become `Â`).
- **`GetOwner` throws for a process that exited after the listing.** Filter by path first and wrap it in try/catch.
- **`Get-AppxPackage -Name` and `Get-WindowsOptionalFeature -FeatureName` take one name, not an array.**

## Hermes

- **Read the installer before running it, and pin its hash.** `install.ps1` needs no admin and SHA-256-pins its downloads, but runs repo code unsigned and, under `[scriptblock]::Create`, signals failure only via `$LASTEXITCODE`. Enforced by: `04-hermes.ps1` (versions.lock hash).
- **Configure by deep-merging templates, then `hermes config check` and read values back with `config get`.** `hermes config set` takes `key value` and has no documented list syntax. Watch the defaults: approvals `smart` (plan: `manual`), backend `local`.
- **The Docker sandbox mounts 15 folders, not 1:** `C:\agent\workspace` and the sandbox home (writable) plus 13 Hermes working folders (read-only). `.env`, `config.yaml`, `memories` and `sessions` are never mounted. Inspect mounts while a chat runs; the container is removed when it ends.
- **Write `approvals.deny` globs knowing they match part of a command.** `dd if=*` also blocks `true && dd if=…`.
- **Recheck `hermes doctor`'s dependency vulnerabilities after each `hermes update`.** Only an upstream lockfile bump fixes them.
- **Secrets go from a hidden prompt straight into the profile's `.env`, never `hermes config set <secret>`.** A command line and the as-`hermes` script file would both hold it. Enforced by: `05-telegram.ps1` and `07-cloud.ps1`, which also filter token-shaped strings from output.
- **Stop the idle gateway before writing a bot token or starting the real gateway.** Every `hermes chat` leaves an idle-exit gateway (600 s) that holds the profile's gateway lock: a token written while it runs could be picked up before `TELEGRAM_ALLOWED_USERS`, and the real gateway exits 1 while the lock is held. Enforced by: `05-telegram.ps1` and `scripts/restart-gateway.ps1`.
- **Don't use `hermes gateway install`, and ignore `gateway status`'s "Repair: hermes gateway start" hint.** As standard user `hermes`, install hangs at a UAC y/N prompt; the hint would replace the guarded `Hermes_Gateway` task. The line that matters is `✓ Gateway process running (PID: n)`; `Last Run Result: 267009` means "currently running".
- **Install the Telegram extra (`hermes pm install --extra telegram`) before the first gateway start.** Otherwise the gateway installs it on startup, blocks its event loop, and its watchdog kills it (exit 75) before Telegram connects.
- **Restart a gateway only with `scripts/restart-gateway.ps1 -Profile <p>`, never `hermes gateway restart`.** `Start-ScheduledTask` does nothing on a running task, and `Stop-ScheduledTask` can leave `hermes.exe`/`python.exe` behind.
- **Find a profile's gateway as a descendant of its `start-gateway.ps1 -Profile X` launcher.** Hermes drops `-p <profile>` on re-exec and runs as `hermes.exe gateway run`. Enforced by: `scripts/restart-gateway.ps1`.
- **Give each bot's profile `gateway.standalone: true`.** v0.22.4's default gateway serves every profile and ignores `multiplex_profiles: false`; `config get` calls the key unrecognized, but the gateway log confirms "profile 'local' is standalone". Recheck after each `hermes update`. Enforced by: `start-gateway.ps1 -Profile local`.
- **Stagger gateways that start at the same logon.** Two racing gateways make one exit 75, and Task Scheduler doesn't restart it. Enforced by: `start-gateway.ps1` (retries a quick exit 75, 6 × 30 s) and `Hermes_Gateway_local`'s 45 s logon delay.
- **Resend messages sent while a gateway was down.** They are dropped (`drop_pending_on_cold_boot: true`).
- **Judge profile isolation by where requests go (usage log, request dumps), not by `auth list`.** Every profile lists the root `auth.json` credential pool, so `hermes -p local auth list` shows Hermes Cloud's OpenRouter key (the cloud profile is the root); a profile's own empty `auth.json` doesn't hide it. The key isn't usable from local: it is `env:`-sourced, and local's custom localhost provider sends even `/model openrouter:…` to Ollama (400). Enforced by: `p1-3-local.ps1` (`no-auth` fails only on OAuth or stored credentials).
- **Look for a deny-rule block in Hermes's output, not in the policy log.** `approvals.deny` is enforced before plugin `pre_tool_call` hooks, so a denied command leaves no line in `policy-<profile>.jsonl`. Its evidence is Hermes's "Blocked by deny rule: …" text and the missing effect.
- **Treat pattern blocks on terminal command text as a backup layer; gate by tool name and credential permissions.** A model refused at the gate can reach the same effect with another tool (a denied `echo … > file` can be done with `write_file`), and a pattern block (plugin `BLOCK`, `approvals.deny`) can be sidestepped by writing a script and running it under a harmless-looking command. The real controls are tool-name gates (calls, SMS, vault) and credential permissions (AgentMail's receive-only key). Enforced by: `p2-1-policy.ps1` (a WARN).
- **Before believing a Telegram test result, check which gateway logged the inbound message.** Hermes Cloud and Hermes Local are easy to mix up in Telegram, and a message sent to the wrong bot still gets an answer.
- **Each profile's cron jobs run in its own gateway;** a job waits for that gateway and runs on catch-up when it starts.
- **Pin cron jobs local with `--provider ollama` plus `providers.ollama.base_url`.** In the default profile, `--provider custom` takes `model.base_url`, which is OpenRouter, so the job goes to the CLOUD.
- **Test `hermes cron run` on an active job.** It refuses a paused job despite `--paused`'s help text.
- **Seed memory with `scripts/seed-user-memory.ps1 -FromFile` and check the memories folder; a model saying "I'll remember that" proves nothing.** A cloud model (Muse Wonder) can confirm saving facts without writing `USER.md`. Telegram passes the sender's display name to every bot, so "it knows my name" isn't memory either.

## OpenRouter

- **Leave "Zero Data Retention only" off.** With it on, Muse Wonder fails with 404 "ZDR violation (account settings)" (`logs\errors.log`) and every reply silently comes from the local fallback. `GET /api/v1/endpoints/zdr` lists the models available under ZDR.
- **Confirm the key limit's "monthly" reset by hand.** `GET /api/v1/key` returns `limit` but not `limit_reset`; `hermes usage --provider openrouter` shows "resets monthly". Enforced by: `07-cloud.ps1` (asks, and refuses a key over `cloud_key_limit_usd`).
- **An unknown model ID returns 400 "not a valid model ID", not 404.** Hermes still falls back to local at once; `p1-4-cloud.ps1` uses this to test the fallback.

## Windows, hardware and Docker

- **The NVIDIA driver must support CUDA 12.8 or higher for Ollama 0.40.8.** Driver 546.92 (CUDA 12.3) crashes GPU discovery (`0xc0000005`), and Ollama falls back to CPU with a 4096 context; 621.01 (CUDA 13) works. Enforced by: `p0-4-ollama.ps1` (`gpu-detected`).
- **Lock down `D:\ollama`.** D:'s default ACL lets any authenticated user modify, so a SYSTEM service there would let `hermes` escalate. Enforced by: `02-ollama.ps1`.
- **Check Ollama tags and sizes before pulling** via `https://registry.ollama.ai/v2/library/<name>/manifests/<tag>`. With 12 GB VRAM, 30B-A3B models use `q4_K_M`.
- **`SERVICE_START_PENDING` right after `nssm start` is normal.**
- **The WSL and Docker Desktop setup needs two reboots:** WSL's `--install --no-distribution` before Docker Desktop can start, then the unattended test after the owner's `hermes` sign-in.
- **Use `docker create`, `docker cp`, `docker start -a` instead of `-v` for `operator`'s files.** The Docker daemon can't read `operator`'s temp folder for `-v`.
- **Copy into the mounted workspace, not the sandbox's `/tmp`.** `docker cp` can't write into `/tmp` (tmpfs) and fails silently. Enforced by: `bench/runner.ps1`.
- **The Docker Desktop installer adds the installing user to `docker-users`.** Harmless for admin `operator`.
- **Tailscale: `tailscale up --unattended` and approve the printed link on the owner's phone.** Nothing stays signed in on the machine; `ForceDaemon: true` confirms unattended mode.
- **`powercfg /q` hides `LIDACTION` here; use `/qh`.**
- **No Lenovo app in `operator`; set battery conservation from the owner's account.** It's firmware, so it applies to all accounts.

## Git and GitHub

- **Use Git's OpenSSH for GitHub, pinned with `core.sshCommand`.** Windows' built-in OpenSSH 9.5p2 can fail key exchange (`unsupported KEX method sntrup761x25519-sha512@openssh.com`). Enforced by: `verify/checks/p0-0b-operator.ps1`.
- **winget installs Git per-user,** under `%LOCALAPPDATA%\Programs\Git`.
- **Pin byte-exact test data to LF in `.gitattributes`.** A CRLF checkout voids byte-exact benchmark tasks such as B2 and B6 (`"25" < "25\r"`).
- **Repo files are CRLF, so multi-line `sed`/`perl` patterns silently miss.** Use the Edit tool.
- **The deploy key can't open PRs; the owner opens them.** Proposed, not built: an Actions workflow that opens a PR on push to `legion/*`.

## Plan and process

- **Edit repo docs with the Edit tool, and check `git diff --stat` before committing.** A `sed` append can write a line after every line of a file, and the damage is only visible in the diff size.
- **`scripts/precommit-check.ps1` runs before every commit.** It checks staged files for repeated lines, `.ps1` parse errors and secret patterns.
- **A check must observe the effect, never a model's or tool's own claim.** Use the usage log (`base_url`, `local`), the file on disk, or an anchored log line. A ZDR failure and an unsaved memory both look fine from the reply alone.
- **Record owner confirmations as such.** When only the owner can see a Done-when item (Tailscale console, recovery key, router, AgentMail console), the commit message says the owner confirmed it.

## Open follow-ups

Tracked in PLAN.md §13 (tech-debt row) unless noted:

- Shared script libraries, including `verify/lib.ps1` for the repeated `Step`/`Record`.
- One secret-pattern list shared by all scripts.
- A cleanup check (elevated) that no `hermes-oneshot-*` task or `C:\Users\Public\hermes-oneshot-*` folder is left.
- An elevation header and guard in every verify script.
- NVIDIA/CUDA ≥ 12.8 preflight: belongs to the P6.2 preflight.
