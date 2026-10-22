# Lessons learned

What the first on-machine run (2026-10-21, Legion Pro 7i, Windows 11 Home 26200) taught us, for the next run and for the package. Newest problems at the bottom of each section. The **Fix** lines say what's already in the repo; **Next** lines are improvements not yet made.

## Accounts and running as another user

- **`operator` wasn't an administrator after P0.0a.** `00-operator.ps1` only printed group membership, so P0.0b passed anyway, and P0.3's elevation prompt fell through to the owner's account. The script's account guard caught it before any change.
  - Fix: `verify/checks/p0-0b-operator.ps1` now has a PASS/FAIL `operator-admin` check.
  - After adding `operator` to Administrators mid-session, the admin prompt asks for **credentials**, not Yes/No, until `operator` signs in again. Enter `operator`'s own credentials, never the owner's.
- **`Start-Process -Credential` and `runas` don't work on this machine.** Both fail with Win32 error 5, "Access is denied", for every variant tried (cmd or PowerShell, any working directory, with or without a profile), from Claude's shell and from a Start-menu PowerShell alike. The Security log shows the logon itself **succeeding** (4624, type 2, via seclogon). The process creation after it fails. Root cause not found; the desktop/window-station ACL grant is the main suspect.
  - PLAN.md's "`Start-Process -Credential` or `runas` (verify)" is answered: neither works here.
  - Fix: `scripts/invoke-as-hermes.ps1` runs commands as `hermes` through a one-shot scheduled task registered with the password the owner types; the task and its stored credential are removed afterwards. Verified: `docker ps` as `hermes` ran with exit code 0 (P0.5).
  - **The task needs "Log on as a batch job".** A task with a stored password is a batch logon, and Windows 11 grants that right only to Administrators, Backup Operators and Performance Log Users. Without it, the task silently never starts (`LastTaskResult` 0x00041303, "has not yet run"), and the first version of the helper waited out its timeout with no output. The owner closed the window, so the cleanup never ran and the task holding the password was left registered until it was found and removed.
    - Fix: `installer/steps/01-host.ps1` grants `SeBatchLogonRight` to `hermes` alone, through `secedit`. The helper now prints progress and fails within 20 s if the task hasn't started.
    - **Next:** a cleanup check that no `hermes-oneshot-*` task or `C:\Users\Public\hermes-oneshot-*` folder is left. Run it elevated, since the tasks are hidden from an unelevated `operator`.
- **`Get-Credential`'s dialog doesn't appear.** At each attempt the System log shows DCOM 10010: `Windows.Internal.Shell.ConsentUx.Details.ConsentUxService did not register with DCOM within the required timeout`. Use `Read-Host -AsSecureString` in a visible window instead.
- **The Docker Desktop installer adds the installing user (`operator`) to `docker-users`.** That's harmless, since `operator` is an admin anyway, but note it.

## What an unelevated `operator` can't see

Verify scripts went wrong several times because of this. On Windows 11 Home, unelevated:

- `GetOwner` on another user's process returns 2 (access denied).
- `Get-Process`'s `StartTime` is empty for SYSTEM processes; use `Win32_Process.CreationDate`.
- `Get-ScheduledTask` doesn't list tasks whose principal is `hermes`.
- `C:\agent` is unreadable, by design: only `hermes`, Administrators and SYSTEM.
- `query user` / `quser` don't exist on Home.
- `Win32_LoggedOnUser` only shows your own logons.
- `manage-bde` needs admin. The shell property `System.Volume.BitLockerProtection` works without it.
- `Get-AppxPackage -AllUsers` is denied.

**Next:** decide per verify script whether it runs elevated, say so in its header, and guard for it (`p0-3-host.ps1` and `p0-5-docker.ps1` already do).

## PowerShell 5.1 pitfalls

- **stderr from native tools becomes a terminating error under `$ErrorActionPreference = 'Stop'`.** `ollama pull` draws its progress on stderr, so the first pull died at once while the server kept downloading. Use `'Continue'` around native calls and judge by `$LASTEXITCODE`. `wsl.exe` also writes UTF-16 with NUL bytes; strip `` `0 ``.
- **`Invoke-WebRequest ... .Content` is a byte array for `application/octet-stream`.** GitHub's `sha256sum.txt` parsed as empty, so the hash check failed even though the hash was right. Use `-OutFile` and read the file.
- **`Tee-Object` logs lose terminating errors.** The error goes to the host, not through the pipeline. Three runs of the P0.5 check showed nothing after a step that had thrown. **Next:** use `Start-Transcript` for every logged run, as `01-host.ps1` and `02-ollama.ps1` do.
- **Double quotes inside an argument to a native program are mangled.** `hermes chat -q 'echo "hello from hermes" > …'` reached Hermes as broken arguments (`unrecognized arguments: from hermes > …`), so the model was never asked. Keep prompts free of double quotes, or use `--query-file`.
- **Unicode output arrives as mojibake** unless the as-`hermes` command sets `[Console]::OutputEncoding` to UTF-8 and `PYTHONIOENCODING=utf-8`. Before that, a check looking for `hermes doctor`'s ✗ marks passed only because it couldn't read any marks at all. Checks now also require the ✓ marks to be present.
- `Get-AppxPackage -Name` and `Get-WindowsOptionalFeature -FeatureName` take one name, not an array.
- There's no Python on the machine. Don't plan on it for helper scripts.

## Windows settings and hardware

- **Windows' built-in OpenSSH (9.5p2) once failed GitHub's key exchange** (`unsupported KEX method sntrup761x25519-sha512@openssh.com`) and later connected with `curve25519-sha256`. The repo pins Git's OpenSSH 10.5p1 through `core.sshCommand`.
- **winget installs Git per-user**, under `%LOCALAPPDATA%\Programs\Git`, not `Program Files`.
- **`powercfg /q` hides `LIDACTION` on this laptop.** Use `/qh`.
- **D:'s default ACL lets any authenticated user modify.** A service running as SYSTEM from `D:\ollama` would let `hermes` escalate. Fix: `02-ollama.ps1` locks `D:\ollama` (Administrators/SYSTEM full, Users read/execute) and keeps `nssm.exe` there.
- **NVIDIA driver 546.92 (CUDA 12.3) was too old for Ollama 0.40.8.** GPU discovery crashed (`llama-server --list-devices failed: exit status 0xc0000005`), and Ollama silently fell back to the CPU, also dropping its default context to 4096 (`total_vram="0 B"`). Driver 621.01 (CUDA 13) works.
  - **Next:** a preflight check that `nvidia-smi` reports CUDA 12.8 or higher, before P0.4.
  - Fix: `p0-4-ollama.ps1` has a `gpu-detected` check.
- **Windows 11 Home has no Lenovo app in `operator`.** Battery conservation is set from the owner's account; it's a firmware setting, so it applies to all accounts.

## Tools and services

- **Tailscale:** don't sign in through a browser in `operator`. `tailscale up --unattended` prints a login link the owner opens on their phone, and `ForceDaemon: true` confirms the unattended mode.
- **Ollama tags:** check them and their sizes before pulling, through `https://registry.ollama.ai/v2/library/<name>/manifests/<tag>`. With 12 GB of VRAM, D2's 30B-A3B uses `q4_K_M`. The four candidates are 66 GB together and downloaded in about 8 minutes.
- **NSSM** reports `SERVICE_START_PENDING` right after `nssm start`. That's normal.
- **WSL** wasn't installed. `wsl --install --no-distribution` needs a reboot before Docker Desktop can start, so P0.5 takes **two reboots**: one for WSL, then the owner's `hermes` sign-in, then the unattended test.
- **The Hermes installer (`install.ps1`, 1,672 lines) was read before running.** It needs no admin rights and writes only to the user's profile. Its uv and PortableGit downloads are SHA-256-pinned. It runs code from the cloned repo without a signature check. With `-NonInteractive` it skips `hermes setup` and the gateway. Under `[scriptblock]::Create` it signals failure only through `$LASTEXITCODE`, without throwing. `versions.lock` pins the reviewed copy's hash, and `04-hermes.ps1` refuses any other copy.
- **Configuring Hermes:** `hermes config set` takes `key value`, and its help doesn't say how to set lists. `04-hermes.ps1 -Configure` instead deep-merges `config/templates/default.config.yaml` using Hermes's own Python and `ruamel.yaml`, which keeps comments and other keys. Then `hermes config check` validates the result, and `config get` reads the values back. Hermes's defaults to watch: approvals `smart` (plan: `manual`), the backend `local`, the model set to OpenRouter Claude, and `single_query_mode: deny`, which is good.
- **`hermes chat -Q -q '…'` answers once and exits.** That makes it usable from the windowless as-`hermes` task.
- **Hermes's Docker sandbox mounts 15 folders, not 1.** They are `C:\agent\workspace` and the sandbox's own home (both writable), plus 13 of Hermes's working folders (attachments, images, skills, caches), all **read-only**. Never mounted: `.env`, `config.yaml`, `memories`, `sessions` and the rest of the profile. Hermes removes the container when a chat ends, so inspect the mounts while a chat is running.
- **`approvals.deny` globs match part of a command.** `dd if=*` blocked `true && dd if=…` too (P0.6).
- **`hermes doctor` reports 1 high-severity vulnerability each in its web and terminal-UI dependencies,** which only an upstream lockfile bump fixes. Recheck after each `hermes update`.
- **`hermes chat` leaves a gateway behind.** Each chat auto-starts `hermes gateway run --quiet --idle-exit` (localhost only), which outlives the chat and exits after 600 s idle (`gateway.unmanaged_idle_exit_seconds`). It's harmless without Telegram credentials. But stop it before writing a bot token, so no gateway can pick the token up before `TELEGRAM_ALLOWED_USERS` exists. `05-telegram.ps1` does that.
- **Keep the bot token off command lines and out of files.** `hermes config set TELEGRAM_BOT_TOKEN <token>` would put it on a command line, and the as-`hermes` helper writes its commands to a script file. Instead, `05-telegram.ps1` reads the token at a hidden prompt and writes it straight into `hermes`'s `.env`, which is where `config set` stores UPPER_SNAKE keys, and filters token-shaped strings out of everything it prints.
- **`hermes gateway install` can't run as standard user `hermes`.** It stops at "Open the UAC prompt now? [y/N]", and in a windowless task that waits forever. Instead, `operator` registers `Hermes_Gateway` itself: started at `hermes`'s sign-in, Interactive, in `hermes`'s session, with no stored password. It runs `scripts/start-gateway.ps1`, which refuses to start the gateway without `TELEGRAM_ALLOWED_USERS`.
- **Install the Telegram extra before the first start.** Otherwise the gateway installs `python-telegram-bot` itself on startup, which blocks its event loop, and its own watchdog kills it after about 2 minutes (exit 75, "missed 3 consecutive liveness probes") before Telegram connects. Use `hermes pm install --extra telegram` (pins `python-telegram-bot[webhooks]==22.8`).
- **Restart the gateway cleanly.** `Start-ScheduledTask` does nothing on a task that's already running, and `Stop-ScheduledTask` can leave `hermes.exe`/`python.exe` behind. A gateway started before the Telegram extra was installed kept running without it ("No adapter available for telegram"). Kill `hermes`'s `gateway run` processes, then start the task.
- **Telegram messages sent while the gateway is down are dropped** on a cold start (`drop_pending_on_cold_boot: true`). Resend after a restart.
- **The gateway runs as `hermes.exe gateway run`**, not `python -m hermes_cli.main …`, so match `gateway run` in process checks.
- **Watching an elevated run:** an unelevated process can't read an elevated process's command line. My "is the window still open?" check returned false while it was open, and I unregistered a task the helper was still waiting on. Rely on the background-task notification instead.
- **Inline `-Command` text for elevated runs mangles double quotes** (PS 5.1 again). Write the script to a file and run it with `-File`.
- **P0.5's sandbox image depends on P0.6** (`hermes config get terminal.docker_image`), so P0.5 can't be ticked until after P0.6. **Next:** move that Done-when item into P0.6.

## Plan and process

- **The deploy key can't open PRs.** The owner opens them. Proposed but not built: a GitHub Actions workflow that opens a PR when a `legion/*` branch is pushed (repo setting "Allow GitHub Actions to create and approve pull requests").
- **D4/D5 changed the plan.** On AgentMail Free, P0.2 has no domain, DNS, folders or rules. The email tasks that assume plus-addressed designations (S8, Phase 2) need adapting when they come up.
- **Owner confirmations are recorded as such.** When a Done-when item can only be seen by the owner (the Tailscale console, the recovery key, the router, the AgentMail console), the commit message says the owner confirmed it.
- **Elevated runs:** launch with `Start-Process -Verb RunAs -Wait`, pass a `-LogPath` in the session scratchpad, and read the log afterwards. The owner clicks the admin prompt. Use a visible window when the script needs a hidden password prompt.
- **The verify scripts repeat `Step`/`Record`.** **Next:** move them into a shared `verify/lib.ps1`.
