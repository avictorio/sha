> The verification notes behind PLAN.md, with source URLs and VERIFIED / INFERRED / NOT FOUND tags as read from each source. The cloud model identifier in the `fallback_providers` snippet (item 4) is the placeholder `<cloud-model-id>`.
>
> **On this machine.** The notes were checked against Hermes `main` @ `275c211` and stable tag `v2026.9.24`. The machine runs **Hermes Agent v0.22.4**. Behaviour found on the machine is recorded in [docs/LESSONS.md](LESSONS.md) and PLAN.md Appendix A; **they win where they differ from these notes**. Short "On this machine:" lines below flag the known differences.

# Hermes hybrid agent plan: verification against primary sources

**How this was checked.** The live docs site (hermes-agent.nousresearch.com), ollama.com, learn.microsoft.com and developer.chrome.com could not be reached from this sandbox: WebFetch DNS failed and the egress proxy refused the connections. I used the documentation source in the official GitHub repos instead.

- **Hermes Agent**
  - `NousResearch/hermes-agent` at `main` @ `275c211` (2026-10-22), files under `website/docs/` (the source of the docs site) plus code.
  - Key claims were also checked against the latest stable tag, `v2026.9.24`. Where stable and `main` differ, it's noted below.
  - Site URL = `https://hermes-agent.nousresearch.com/docs/<path>`. GitHub = `https://github.com/NousResearch/hermes-agent/blob/main/website/docs/<path>.md`.
- **Ollama**: `ollama/ollama` @ `8cc68d2` (2026-10-21), `docs/` and `envconfig/config.go`.
- **WSL**: `MicrosoftDocs/WSL` @ `50342fc` (2026-10-16).
- **Docker**: `docker/docs` @ `226023f` (2026-10-21).
- **PyPI**: the JSON API, fetched live.
- **Plivo plugin**: GitHub `plivo-dev/hermes-plivo-phone-gateway` @ `8a91a3b`.
- **Fetched through the search index only**: the Chrome blog, OpenRouter docs and Ollama library tags. These are labeled as such below.

Confidence tags:
- **VERIFIED**: read in the primary source.
- **INFERRED**: deduced from the source or code, but not stated outright.
- **NOT FOUND**: no primary source located.

---

## Hermes Agent

### 1. Install method; native Windows vs WSL2
- **Answer.** Native Windows 10/11 (x86_64 and ARM64) is **Tier 1**, on both `main` and stable `v2026.9.24`. WSL2 is not required. Linux/WSL2 is also Tier 1.
  - Native guide: "Hermes runs natively on Windows 10 and Windows 11 — no WSL, no Cygwin, no Docker."
  - Shell commands run through Git Bash. The installer downloads a pinned Git for Windows if Git is missing.
  - No admin rights are needed. It installs to `%LOCALAPPDATA%\hermes\` and adds `%LOCALAPPDATA%\hermes\bin` to the User PATH.
  - Installs via pip, uv or brew are explicitly **unsupported**.
- **Commands**
  ```powershell
  # Windows native (PowerShell)
  iex (irm https://hermes-agent.nousresearch.com/install.ps1)
  # with options:
  & ([scriptblock]::Create((irm https://hermes-agent.nousresearch.com/install.ps1))) -NonInteractive -Channel stable
  ```
  ```bash
  # Linux / macOS / WSL2
  curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
  ```
  The installer also has an MSIX/App Installer desktop package, which needs Windows 11 22H2 or later.
- **Native Windows feature limits.**
  - On stable, the dashboard's `/chat` embedded terminal pane is the only thing that doesn't work natively. On `main` it uses ConPTY.
  - The Matrix encrypted adapter is Linux-only. The ARM64 exclusions don't apply to this x86_64 laptop.
- **Docs inconsistency.** `integrations/providers.md` §WSL2 still says "Since Hermes Agent requires a Unix environment, Windows users run it inside WSL2." That line is stale; the platform-support page overrides it.
- **Sources**
  - https://hermes-agent.nousresearch.com/docs/getting-started/installation
  - https://hermes-agent.nousresearch.com/docs/getting-started/platform-support
  - https://hermes-agent.nousresearch.com/docs/user-guide/windows-native
- **VERIFIED**

### 2. Config location and main CLI commands
- **Paths.**
  - POSIX/WSL: `~/.hermes/`.
  - Windows native: **`%LOCALAPPDATA%\hermes\`**, which holds config, credentials, sessions, plugins, skills and logs.
  - `HERMES_HOME` overrides either.
- **Layout under the data directory.**
  - `config.yaml`: all non-secret settings.
  - `.env`: API keys and secrets.
  - `auth.json`: OAuth credentials.
  - `SOUL.md`.
  - `memories/` (MEMORY.md, USER.md), `skills/`, `cron/`, `sessions/`, `logs/`, `state.db`.
- **Precedence**: CLI arguments > `config.yaml` > `.env` > defaults. Secrets must go in `.env`.
- **Commands**
  ```bash
  hermes setup                 # full wizard; sections: hermes setup model|terminal|gateway|tools|agent
  hermes model                 # choose provider + model
  hermes tools                 # enable/disable toolsets
  hermes config edit | get KEY | set KEY VAL | unset KEY | check | migrate
  hermes config set OPENROUTER_API_KEY sk-or-...   # UPPER_SNAKE names are written to .env automatically
  hermes gateway setup         # messaging platforms
  hermes gateway               # or: hermes gateway run  (foreground)
  hermes gateway install|start|stop|restart|status|uninstall
  hermes doctor
  ```
- **Running as a service**
  - **Windows native**: `hermes gateway install` registers `schtasks /Create /SC ONLOGON /RL LIMITED /TN Hermes_Gateway`. If that fails, it falls back to a Startup-folder VBS launcher. Either way it runs **at user logon**, not at boot.
  - Hermes advises against a Windows Service: "If you genuinely want a service, use `nssm` or `sc create` manually — but you probably don't." It also asks that any such service be named `Hermes*` so `hermes update` can recognise it.
  - **Linux/WSL**: `hermes gateway install` installs a systemd user unit. `sudo hermes gateway install --system` installs a boot-time system service.
  - The CLI reference tip for WSL: "Use `hermes gateway run` instead of `hermes gateway start` — WSL's systemd support is unreliable." It suggests tmux.
- **Sources**
  - https://hermes-agent.nousresearch.com/docs/user-guide/configuration
  - https://hermes-agent.nousresearch.com/docs/reference/cli-commands
  - https://hermes-agent.nousresearch.com/docs/user-guide/windows-native (sections "Running the gateway at Windows login" and "Data layout")
- **VERIFIED**

### 3. Pointing Hermes at Ollama or any OpenAI-compatible endpoint; context length
- **Answer.** Use provider `custom` with an OpenAI-compatible `base_url`. Run the `hermes model` wizard and choose "Custom endpoint", or edit the YAML directly.
  ```yaml
  model:
    default: qwen3:32b            # whatever tag you serve
    provider: custom
    base_url: http://localhost:11434/v1
    context_length: 65536         # explicit "pin"; must be >= 64000
    # ollama_num_ctx: 65536       # the window the local server really serves (honoured on any local endpoint)
  ```
- **Alternative**: a named provider block, `providers.ollama.base_url: "http://localhost:11434/v1"`, used with `hermes chat --provider ollama`.
- **Per-model context** for named custom providers:
  ```yaml
  providers:
    <name>:
      api: http://localhost:11434/v1
      models:
        <id>:
          context_length: 64000
  ```
- **Context resolution order**:
  1. `model.context_length`
  2. `providers.<name>.models.<id>.context_length`
  3. The cache
  4. The endpoint's `/models`, then model registries
- **What Hermes does on its own.** For local endpoints it queries Ollama's `/api/show` and sends `num_ctx` with each request. `model.context_length` caps that value.
- **What the docs still require.** Set the context on the server as well: `OLLAMA_CONTEXT_LENGTH` or a Modelfile `num_ctx`. Docs: "You cannot set context length through the OpenAI-compatible API." Then check `ollama ps`, CONTEXT column.
- **Sources**
  - https://hermes-agent.nousresearch.com/docs/integrations/providers (sections "Ollama — Local Models" and "Context Length Detection")
  - https://hermes-agent.nousresearch.com/docs/guides/local-ollama-setup
  - Code: `agent/agent_init_ollama.py`
- **VERIFIED**

### 4. Fallback, routing and mid-session switching (what is native)
- **Native: automatic failover to other providers** through the top-level `fallback_providers` list (ordered). Manage it with `hermes fallback` (`add`, `list`, `remove`, `clear`).
  ```yaml
  fallback_providers:
    - provider: openrouter
      model: <cloud-model-id>
  fallback:
    min_switch_reset_seconds: 0
  ```
- **What triggers it**:
  - 429 and 500/502/503, after retries.
  - 401/403 and 404, immediately.
  - Malformed or empty responses that keep repeating.
  - On this machine: an unknown OpenRouter model returns 400, not 404, and Hermes still falls back to the local model at once (docs/LESSONS.md).
- **How it behaves.**
  - **Turn-scoped**: "each new user message starts with the primary model restored." It switches at most once per turn.
  - It works in the CLI, the gateway (Telegram), subagents and unpinned cron jobs.
  - There are no environment variables for it, by design.
  - The legacy key `fallback_model` is still honoured.
- **Native: manual switching mid-session**:
  - `/model provider:model`. It can only use providers that are already configured.
  - Flags: `--global` (persist), `--session`, `--once` (next turn only), `--provider`, `--reasoning`.
  - `/model` also works in messaging chats. Custom aliases are supported.
- **Native: static per-surface routing**:
  - Per channel or chat: `platforms.<platform>.channel_overrides.<chat_id>.{model,provider,system_prompt}`. The doc example is Discord. Telegram support is INFERRED because the logic lives in shared gateway code.
  - Subagents: `delegation.model` / `delegation.provider` / `delegation.fallback_providers`.
  - Cron: per-job `provider`/`model`, or `cron.model` / `cron.model_provider`.
  - Side tasks: `auxiliary.<task>` (vision, compression, approval, and so on), each with its own `fallback_chain`.
  - OpenRouter `provider_routing` only chooses which *upstream* serves an OpenRouter model. It doesn't choose between local and cloud.
- **Not native**:
  - No escalation on complexity, task type, private tags or context size.
  - No "local-only mode" switch was found.
  - `pre_llm_call` hooks can only append context; they can't change the model.
  - `pre_gateway_dispatch` can rewrite or skip incoming messages. Using it to inject a `/model --once` command is an untested idea (INFERRED).
  - A `smart_model_routing` key exists in code, but the setup wizard only ever writes `enabled: False`, and no runtime code reads it. It is undocumented; **do not use**.
- **Conclusion.** Error-driven failover is configuration. An escalation policy beyond that is **custom code**: a plugin or wrapper, or an operator using `/model`.
- **Sources**
  - https://hermes-agent.nousresearch.com/docs/user-guide/features/fallback-providers
  - https://hermes-agent.nousresearch.com/docs/reference/slash-commands
  - https://hermes-agent.nousresearch.com/docs/user-guide/messaging (section "Per-Channel Model & System Prompt Overrides")
  - https://hermes-agent.nousresearch.com/docs/user-guide/features/hooks
- **VERIFIED** (the `smart_model_routing` status is INFERRED from code).

### 5. Minimum context and tool-calling requirement
- **Answer.** **64,000 tokens**: `MINIMUM_CONTEXT_LENGTH = 64_000` in `agent/model_metadata.py`, on both `main` and stable.
  - Below that, Hermes **refuses to start**. `_enforce_minimum_context` raises an error such as "Model X has a context window of N tokens, which is below the minimum 64,000 required by Hermes Agent."
  - For a local Ollama endpoint, a Modelfile or `model.ollama_num_ctx` of at least 64K counts, "even when the metadata says 40K."
- **Tool calling.** The docs require it for agentic work but don't hard-check it.
  - Docs: "Models without tool-call support can only chat; they can't take actions."
  - Hermes auto-repairs malformed tool calls.
  - Server-side flags are needed on some servers: llama.cpp needs `--jinja`; vLLM needs `--enable-auto-tool-choice --tool-call-parser hermes`.
- **Sources**
  - https://hermes-agent.nousresearch.com/docs/integrations/providers
  - https://hermes-agent.nousresearch.com/docs/guides/local-ollama-setup
  - Code: `agent/agent_init.py::_enforce_minimum_context`
- **VERIFIED**

### 6. Terminal backends: selecting Docker; is the home directory persisted?
- **Answer.** There are 7 backends: `local | docker | ssh | modal | daytona | vercel_sandbox | singularity`.
  ```yaml
  terminal:
    backend: docker
    docker_image: "nousresearch/hermes-sandbox:desktop"   # optional; see doc note on recreation
    container_persistent: true          # default: persist /workspace + /root, one shared container
    docker_persist_across_processes: true
    docker_mount_cwd_to_workspace: false
    docker_volumes: ["C:/path/on/host:/workspace/projects"]   # standard -v syntax (Windows-path handling INFERRED from code)
    docker_forward_env: ["GITHUB_TOKEN"]
    docker_network: true
    container_cpu: 1
    container_memory: 5120
  ```
  Or run `hermes config set terminal.backend docker`. The same keys can be set through `TERMINAL_*` environment variables.
- **Persistence.**
  - With `container_persistent: true`, Hermes bind-mounts **`/workspace` and `/root`** from `~/.hermes/sandboxes/docker/<task_id>/`. Override the location with `TERMINAL_SANDBOX_DIR`.
  - One long-lived container is shared across sessions and subagents. It is not created with `--restart=always`, so after a reboot it sits Exited and is restarted on next use.
  - The Hermes data directory itself is **not** mounted into the container. Hermes runs on the host, and its data stays on the host. The plan's wording ("~/.hermes persists on the host as a mounted volume") should be reworded.
  - `home_mode: auto` makes containers use `{HERMES_HOME}/home` as HOME.
  - Requirement: "Docker Desktop or Docker Engine installed and running."
- **Native-Windows caveat.** The docs don't explicitly confirm the Docker backend on native Windows. The code handles Windows drive paths in mounts (INFERRED as supported). Generated files that Telegram should send must go to a host-visible mount.
- **Sources**
  - https://hermes-agent.nousresearch.com/docs/user-guide/configuration (sections "Terminal Backend Configuration" and "Docker Backend")
  - https://hermes-agent.nousresearch.com/docs/user-guide/security (section "Filesystem Persistence")
- **VERIFIED**, except native-Windows Docker, which is INFERRED.

### 7. Telegram gateway and the user allowlist
- **Setup.**
  1. Create a bot with @BotFather.
  2. Get your numeric user ID from @userinfobot.
  3. Run `hermes gateway setup` and choose Telegram, or edit `.env` by hand.
  4. Start the gateway with `hermes gateway`.
- **`.env` entries** (on Windows native this is `%LOCALAPPDATA%\hermes\.env`):
  ```dotenv
  TELEGRAM_BOT_TOKEN=123456789:ABC...
  TELEGRAM_ALLOWED_USERS=123456789          # comma-separated numeric user IDs; covers DMs, groups, forums
  # optional: TELEGRAM_GROUP_ALLOWED_USERS=...  (group-only senders)
  # optional gateway-wide: GATEWAY_ALLOWED_USERS=...
  # NEVER for a terminal-capable bot: GATEWAY_ALLOW_ALL_USERS=true
  ```
- **Access behaviour.**
  - "Without [TELEGRAM_ALLOWED_USERS], the gateway denies all users by default."
  - Alternative: DM pairing, approved with `hermes pairing approve telegram <CODE>`. Related: `hermes pairing list` and `hermes pairing revoke telegram <id>`.
  - An admin vs regular-user split is also available.
- **Docs inconsistency.** The Ollama guide shows `platforms.telegram.token` in `config.yaml`. Prefer `.env`, per the precedence rules.
- **Sources**
  - https://hermes-agent.nousresearch.com/docs/user-guide/messaging/telegram
  - https://hermes-agent.nousresearch.com/docs/user-guide/messaging (Security section)
- **VERIFIED**

### 8. Built-in cron syntax and Telegram delivery
- **Answer.** Cron runs **inside the gateway process**, which ticks every 60 s. No gateway means no cron.
- **Jobs** are stored in `~/.hermes/cron/jobs.json`, with output in `cron/output/`.
  - On this machine (v0.22.4): jobs live in a database, not `cron/jobs.json` (PLAN.md Appendix A, S3).
- **Schedule formats**:
  - One-shot delays: `in 30m`.
  - Intervals: `every 2h`, `30m`.
  - Natural language: `every day at 9am`, `weekdays at 7am`.
  - Standard 5-field cron: `0 7 * * *`.
  - ISO timestamps.
- **Commands**
  ```bash
  hermes cron create "every day at 7am" "Morning brief: ..." --name brief --deliver telegram
  hermes cron list | edit | pause | resume | run <id> | remove | status | runs | doctor | tick
  # in chat: /cron add "every 2h" "Check server status"
  ```
- **Delivery targets.**
  - `telegram` sends to the home channel. Set it with `/sethome` in the chat, or `TELEGRAM_HOME_CHANNEL=<chat_id>` in `.env`. For a DM, the chat ID equals your user ID.
  - `telegram:<chat_id>` and `telegram:<chat_id>:<thread_id>` target a specific chat or topic.
  - `TELEGRAM_CRON_THREAD_ID` sets the topic for cron deliveries.
  - Output is secret-redacted on the way out.
- **Approvals in cron.** `approvals.cron_mode: deny` is the default. A cron job that hits a dangerous command is blocked; nobody is prompted.
- **Sources**
  - https://hermes-agent.nousresearch.com/docs/user-guide/features/cron
  - https://hermes-agent.nousresearch.com/docs/reference/cli-commands (section `hermes cron`)
- **VERIFIED**

### 9. Command approval; hooks and plugins for custom gates and tools
- **Approval settings**
  ```yaml
  approvals:
    mode: smart          # smart (auxiliary LLM decides) | manual | off  (off == --yolo)
    timeout: 300         # fail-closed on timeout
    cron_mode: deny
    unattended_mode: deny
    deny:                # user globs, enforced even under yolo, on ALL backends
      - "git push --force*"
  command_allowlist: []  # "always" approvals persist here
  ```
  - On Telegram you approve by replying `yes`/`y`/`approve` or `no`/`n`/`deny`.
  - `/yolo` toggles YOLO mode for the session.
  - A hardline blocklist always applies and can't be overridden.
- **Critical caveat.** "Container bypass: When running in `docker`, `singularity`, `modal`, `daytona`, or `vercel_sandbox` backends, dangerous command checks are **skipped**."
- **Custom approval gate: native plugin hook** `pre_tool_call`. It fires before every tool, built-in or plugin.
  - On this machine: `approvals.deny` is enforced before plugin hooks, so a denied command never reaches the plugin and leaves no `policy-*.jsonl` line (docs/LESSONS.md, Hermes).
  ```python
  # ~/.hermes/plugins/call-gate/__init__.py  (+ plugin.yaml with name/version/description)
  def gate(tool_name, args, task_id, **kwargs):
      if tool_name in ("make_call", "call_place"):
          return {"action": "approve", "message": "Outbound call needs approval", "rule_key": "phone:outbound"}
      # or: return {"action": "block", "message": "..."}
  def register(ctx):
      ctx.register_hook("pre_tool_call", gate)
  ```
  - `block` beats `approve`.
  - Denial, timeout or an exception fails **closed**.
  - Callbacks time out after `plugins.hook_callback_timeout` (default 30 s).
  - `pre_approval_request` / `post_approval_response` are observe-only.
  - Shell hooks and gateway event hooks (`~/.hermes/hooks/<name>/HOOK.yaml` + `handler.py`) also exist.
- **Custom tool such as `call.place`**: a plugin directory `~/.hermes/plugins/<name>/` containing `plugin.yaml` and `__init__.py`. In `register(ctx)`, call `ctx.register_tool(name=..., toolset=..., schema=..., handler=...)`.
  - Plugins are **off until enabled**: `hermes plugins enable <name>`, or add the name to `plugins.enabled` in config.
  - The gateway doesn't load project-local `./.hermes/plugins/`.
  - Name the tool `call_place`; a dot in the name may not be valid (INFERRED).
- **MCP servers** can also be gated: `trust: untrusted` sends every write-capable tool call to approval, and `spend_limit` caps per-chat spend.
- **Sources**
  - https://hermes-agent.nousresearch.com/docs/user-guide/security
  - https://hermes-agent.nousresearch.com/docs/user-guide/features/hooks (`pre_tool_call`; also present in stable)
  - https://hermes-agent.nousresearch.com/docs/user-guide/features/plugins
  - https://hermes-agent.nousresearch.com/docs/developer-guide/adding-tools
- **VERIFIED**

### 10. Local Chrome over CDP
- **Config key**: `browser.cdp_url` in `config.yaml`. **Env var**: `BROWSER_CDP_URL`.
- **Precedence** (from code): a live `/browser connect` > `BROWSER_CDP_URL` > `browser.cdp_url`.
- **Accepted values**: `http://127.0.0.1:9222`, a bare `ws://host:port`, or a full `ws://…/devtools/browser/…` URL. HTTP and bare forms are resolved through `/json/version`.
  ```yaml
  browser:
    cdp_url: "http://127.0.0.1:9222"
    dialog_policy: must_respond
  ```
- **Launching Chrome.** Use a dedicated profile so the debug port actually opens. The documented flags:
  `--remote-debugging-port=9222 --user-data-dir=<dedicated dir> --no-first-run --no-default-browser-check`
  - The docs show Linux and macOS commands. The Windows `chrome.exe` equivalent is INFERRED.
  - `/browser connect` with no argument auto-launches a Chromium-family browser on 9222, but it is an **interactive-CLI-only** command: "it is not dispatched by the gateway."
- **Other options.**
  - The `browser_cdp` raw tool is available when a CDP endpoint is reachable at session start.
  - `browser.use_real_profile` snapshots your real profile into a copy.
  - With Hermes in WSL2 and Chrome on Windows, the docs suggest `chrome-devtools-mcp` over MCP instead of `/browser connect`.
- **Sources**
  - https://hermes-agent.nousresearch.com/docs/user-guide/features/browser (section "Local Chromium-family browser via CDP")
  - https://hermes-agent.nousresearch.com/docs/user-guide/configuration (Browser section)
  - https://hermes-agent.nousresearch.com/docs/reference/environment-variables
  - Code: `tools/browser_tool_cdp.py`
- **VERIFIED**

### 11. MCP server configuration
- **Answer.** A top-level `mcp_servers:` map in `config.yaml`. Each entry is one of two kinds:
  - **stdio**: `command`, `args`, `env`.
  - **HTTP**: `url`, `headers`; add `transport: sse` for SSE.
- **Optional keys**: `enabled`, `timeout` (300), `connect_timeout` (60), `tools.include` / `tools.exclude`, `auth: oauth`, `trust: full|untrusted`, `spend_limit`, `lazy`.
- **Secrets**: reference them as `${VAR}` or `${env:VAR}`. Values resolve from the profile's `.env` or secret source.
  ```yaml
  mcp_servers:
    github:
      command: "npx"
      args: ["-y", "@modelcontextprotocol/server-github"]
      env:
        GITHUB_PERSONAL_ACCESS_TOKEN: "${env:GITHUB_TOKEN}"
      trust: untrusted
  ```
- **Commands**: `hermes mcp …` on the CLI, and `/reload-mcp` in chat.
- **Sources**
  - https://hermes-agent.nousresearch.com/docs/reference/mcp-config-reference
  - https://hermes-agent.nousresearch.com/docs/user-guide/features/mcp
- **VERIFIED**

### 12. Secret and credential handling
- **Default.** `.env` for API keys and tokens; `auth.json` for OAuth.
- **Built-in options beyond `.env`**:
  - **Secret sources.** Keys are pulled from an external manager at startup:
    - Bitwarden Secrets Manager: `hermes secrets bitwarden setup|status|token|sync|install|disable`.
    - 1Password: `op://` references.
    - A "command helper" for any command-line vault (`keepassxc-cli`, `pass`, …) that prints `KEY=VALUE` lines.
    - Configured under `secrets:` (`sources`, `bitwarden`, `preserve_existing`, …).
    - The manager's bootstrap token still lives in `.env`.
  - **Credential vault ("Passwords & Logins").** Website logins, TOTP seeds and cards.
    - Encrypted under `~/.hermes/vault/` with a Fernet key plus a vault file, both `0600`.
    - Filled through CDP, so the model never sees the password.
    - Commands: `hermes vault list|add|rm <handle>|sources`. Detected 1Password/Bitwarden logins can also be used.
    - Present in stable.
    - Note: the Fernet key sits next to the vault file. That is encryption at rest, not a hardware-backed store (INFERRED from the docs' description).
  - **Child processes**: terminal and `execute_code` run with credentials stripped. Only `terminal.env_passthrough` / `docker_forward_env` names are forwarded.
- **Sources**
  - https://hermes-agent.nousresearch.com/docs/user-guide/secrets
  - https://hermes-agent.nousresearch.com/docs/user-guide/features/credential-vault
  - https://hermes-agent.nousresearch.com/docs/reference/cli-commands (section `hermes secrets`)
- **VERIFIED**

### 13. Memory and session storage; backup and export
- **What to back up**: the whole data root.
  - `~/.hermes/` (Windows native: `%LOCALAPPDATA%\hermes\`).
  - `state.db` (SQLite with FTS5: sessions and messages), `memories/MEMORY.md`, `memories/USER.md`, `SOUL.md`, `skills/`, `cron/jobs.json`, `config.yaml`, `.env`, `auth.json`, `vault/`, `profiles/<name>/`.
- **Commands**
  ```bash
  hermes backup                      # full zip -> ~/hermes-backup-<ts>.zip (includes .env and auth.json!)
  hermes backup -o D:\backups\hermes.zip -k 7
  hermes backup --quick --label pre-upgrade   # config.yaml, state.db, .env, auth, cron only
  hermes import <zip> [--force]      # stop the gateway first
  hermes profile export <name> <file.tar.gz>  # one profile, credentials EXCLUDED
  hermes snapshot list               # referenced by import output
  ```
- **Backup behaviour.**
  - `hermes backup` uses SQLite's `backup()`, so it is safe while Hermes is running.
  - It exits 1 if the archive is incomplete.
  - It excludes browser profiles, models, runtimes and the code checkout.
  - The zip contains secrets, so encrypt it at rest.
- **Sources**
  - https://hermes-agent.nousresearch.com/docs/reference/cli-commands (sections `hermes backup` and `hermes import`)
  - https://hermes-agent.nousresearch.com/docs/reference/faq (section "`hermes backup` vs `hermes profile export`")
  - https://hermes-agent.nousresearch.com/docs/user-guide/sessions
- **VERIFIED**

---

## Ecosystem

### 14. `hermes-plivo-phone-gateway` on PyPI; Twilio/Vapi
- **Exists. VERIFIED.**
  - Version **0.2.1**, uploaded 2026-09-07. Earlier releases run from 0.1.0 to 0.2.0, starting 2026-09-03.
  - Author "Plivo"; MIT licence; Python >= 3.11.
  - Repo: https://github.com/plivo-dev/hermes-plivo-phone-gateway. PyPI: https://pypi.org/project/hermes-plivo-phone-gateway/
- **What it does.**
  - A real-time Plivo Audio Streaming voice channel (a platform plugin `plivo_voice`), **inbound and outbound**.
  - Supports barge-in and DTMF digits.
  - Uses Hermes' own STT and TTS settings, and needs Hermes' `voice` extra.
- **Tunnel.** "`cloudflared` is fetched automatically when no public URL is configured." The code has a Windows AMD64 asset. Set `PLIVO_VOICE_PUBLIC_URL` for production; quick tunnels are "development only."
- **Wiring.** It auto-configures the Plivo application and number on every start (`PLIVO_VOICE_AUTO_WIRE=true`).
- **Install per the README**
  ```bash
  pip install hermes-plivo-phone-gateway          # pulls hermes-plivo-tools>=0.1.3 (make_call, send_sms, lookup_number)
  hermes plugins enable plivo_voice-platform      # exact name incl. -platform suffix
  hermes plugins enable plivo-tools               # outbound calling tools
  ```
- **`.env` settings**
  ```dotenv
  PLIVO_AUTH_ID=...
  PLIVO_AUTH_TOKEN=...
  PLIVO_PHONE_NUMBER=+1...
  PLIVO_VOICE_ALLOWED_USERS=<digits,...>          # inbound allowlist; EMPTY = anyone may call
  PLIVO_VOICE_ALLOWED_DESTINATIONS=<digits,...>   # outbound allowlist; EMPTY = all outbound refused
  PLIVO_VOICE_PUBLIC_URL=https://...              # else temporary cloudflared tunnel
  PLIVO_VOICE_STREAMING_TTS=true                  # ~3 s vs 27 s to first audio; else needs ffmpeg
  # also: PLIVO_VOICE_WS_PORT (8791), _IDLE_TIMEOUT (60), _MAX_CALL_SECONDS (600), _MAX_CONCURRENT_CALLS (20)
  ```
- **Running and checking it.**
  - Start with `hermes gateway run` or `hermes gateway install`, then wait for `[plivo_voice] READY.`
  - Check with `python -m hermes_plivo_voice.doctor`.
  - Remove the Plivo wiring with `python -m hermes_plivo_voice.unwire`.
  - Limit what callers can reach through `platform_toolsets.plivo_voice: [...]`.
- **Gaps for the runbook.**
  - **Install path (INFERRED risk).** Current Hermes docs say "Do not mutate a Hermes environment with raw pip," and entry-point discovery "is discovery, not permission to inject packages into a PM-selected generation." A supported way to install this pip-layout plugin into a PM-managed native Windows install is **NOT FOUND**. Expect to re-install after `hermes update`, or wrap it as a directory plugin.
  - **Approval gate.** The plugin has destination allowlists but no per-call approval. Add the `pre_tool_call` hook from §9 to `make_call`.
- **Twilio/Vapi.** There is an official Hermes **optional skill** `telephony` (Nous Research):
  - Install: `hermes skills install official/productivity/telephony`.
  - It covers Twilio numbers and SMS, Twilio direct calls (TwiML), and outbound AI calls through **Vapi** (Twilio number imported into Vapi; `VAPI_PHONE_NUMBER_ID`) or Bland.ai.
  - It is **not** a real-time inbound phone gateway. The skill's own rule: "Always confirm before placing a call."
  - Hermes also ships an SMS gateway over Twilio. No first-party Vapi or Twilio *voice* gateway plugin was found.
  - Sources: https://hermes-agent.nousresearch.com/docs/user-guide/skills/optional/productivity/productivity-telephony and https://hermes-agent.nousresearch.com/docs/user-guide/messaging/sms
  - **VERIFIED**

### 15. Ollama settings and model tags
- **Default context. VERIFIED.** Set by VRAM:
  - Under 24 GiB: **4k**.
  - 24–48 GiB: 32k.
  - 48 GiB or more: 256k.
  - So this 12 GB laptop gets **4,096**.
  - Ollama itself says agents need "at least 64000 tokens."
  - The plan's "2,048" is outdated. Hermes' own `guides/local-ollama-setup.md` also still says 2048; its `providers.md` has the newer table.
- **Environment variables. VERIFIED**, from `envconfig/config.go` and `docs/faq.mdx`:

  | Variable | Behaviour |
  |---|---|
  | `OLLAMA_CONTEXT_LENGTH` | Default context. Defaults to 4k/32k/256k by VRAM. |
  | `OLLAMA_KEEP_ALIVE` | Default `"5m"`. Takes a duration (`30m`, `24h`), seconds, or a negative number for "forever". The API `keep_alive` parameter overrides it. |
  | `OLLAMA_FLASH_ATTENTION` | Used automatically when the backend supports it. `1` forces it on; `0` turns it off. |
  | `OLLAMA_KV_CACHE_TYPE` | Default `f16`. **`q8_0`** uses about half the memory with little loss; `q4_0` is also available. Applies to all models, and only when Flash Attention is active. |
  | `OLLAMA_HOST` | Default `127.0.0.1:11434`. |

- **Setting them on Windows (native).**
  1. Quit Ollama from the taskbar.
  2. Open Settings, search "environment variables", then "Edit environment variables for your account".
  3. Add the variables.
  4. Start Ollama again from the Start menu.
  - The PowerShell equivalent, `[Environment]::SetEnvironmentVariable('OLLAMA_CONTEXT_LENGTH','65536','User')`, is INFERRED.
  - The Ollama app also has a context-length slider in its settings.
  - The standard installer runs Ollama in the user session. To run it as a service, use the standalone `ollama-windows-amd64.zip` plus `ollama serve` under **NSSM**; this is documented.
  - Check with `ollama ps`, CONTEXT and PROCESSOR columns.
  - Sources: https://github.com/ollama/ollama/blob/main/docs/context-length.mdx, …/docs/faq.mdx, …/docs/windows.mdx (site: https://docs.ollama.com/…)
- **Model tags.** INFERRED from search-index snippets of ollama.com library pages; the pages themselves were not reachable. Confirm with `ollama show <tag>` or the tags page before pinning.

  | Tag | Exists? | Approx. download | Listed context | Fit on 12 GB VRAM |
  |---|---|---|---|---|
  | `qwen3:32b` | yes | ~20 GB (Q4_K_M) | **40K** | Partial offload |
  | `qwen3:30b-a3b` | yes | ~19 GB | Snippets conflict: 256K on the tags page vs 40K on the `-q4_K_M` page. The default may now point to the 2507 refresh; `qwen3:30b-a3b-instruct-2507-*` tags also exist. | Partial offload |
  | `qwen3:14b` | yes | ~9.3 GB (Q4_K_M) | **40K** | Fits, but a 64K KV cache adds VRAM pressure |
  | `gpt-oss:20b` | yes | ~14 GB (MXFP4) | 128K | Partial offload |

  - The 40K context on the dense qwen3 tags runs into Hermes' 64K floor (§5).
  - Search-result sources: https://ollama.com/library/qwen3/tags, https://ollama.com/library/qwen3:14b, https://ollama.com/library/gpt-oss/tags

### 16. Chrome 136 remote-debugging change
- **Answer.** From Chrome 136, `--remote-debugging-port` and `--remote-debugging-pipe` "will no longer be respected if attempting to debug the default Chrome data directory." The flag is silently ignored.
  - You must pass a non-default `--user-data-dir`, or use Chromium or Chrome for Testing.
  - Google's stated reason is cookie theft by infostealers.
  - Hermes docs add that Chrome 144+ has an opt-in "Allow remote debugging?" approval flow for the *real* profile (`chrome://inspect/#remote-debugging`). A dedicated `--user-data-dir` avoids that flow.
- **Snippet**
  ```text
  chrome.exe --remote-debugging-port=9222 --user-data-dir="%LOCALAPPDATA%\hermes\chrome-debug" --no-first-run --no-default-browser-check
  ```
  The directory path is your choice. The flags are the documented ones.
- **Sources**
  - https://developer.chrome.com/blog/remote-debugging-port (via search index; quoted verbatim in Hermes docs)
  - https://issues.chromium.org/issues/417456892
  - https://hermes-agent.nousresearch.com/docs/user-guide/features/browser
- **VERIFIED** (the Chrome blog through the search index plus Hermes' verbatim quote).

### 17. WSL2 networking; starting at boot without login; Docker Desktop
- **Mirrored mode. VERIFIED.**
  - Needs Windows 11 22H2 or later. Set it in `%USERPROFILE%\.wslconfig`:
    ```ini
    [wsl2]
    networkingMode=mirrored
    ```
    Then run `wsl --shutdown`.
  - Microsoft: "Connect to Windows servers from within Linux using the localhost address `127.0.0.1`. IPv6 localhost address `::1` is not supported."
  - So WSL can reach Ollama at `127.0.0.1:11434` and Chrome CDP at `127.0.0.1:9222`. Use `127.0.0.1`, not `::1`.
  - Inbound connections may need Hyper-V firewall rules (`Set-NetFirewallHyperVVMSetting …`).
  - `hostAddressLoopback=true` additionally allows the host's other IPv4 addresses.
  - Known problem: DNS issues with VPNs.
  - Hermes adds a caveat: for Hermes in WSL driving Windows Chrome, prefer `chrome-devtools-mcp`.
  - Sources: https://github.com/MicrosoftDocs/WSL/blob/main/WSL/networking.md, …/wsl-config.md (site: https://learn.microsoft.com/windows/wsl/networking); https://hermes-agent.nousresearch.com/docs/user-guide/windows-wsl-quickstart
- **systemd in WSL. VERIFIED.**
  - Put this in `/etc/wsl.conf`:
    ```ini
    [boot]
    systemd=true
    ```
  - Then `hermes gateway install` offers a systemd user unit.
  - The CLI reference contradicts this: "WSL's systemd support is unreliable", and suggests `hermes gateway run` in tmux. The two Hermes pages disagree.
  - WSL shuts idle VMs down. `vmIdleTimeout` defaults to 60000 ms and `instanceIdleTimeout` to 15000 ms; `-1` disables the instance timeout.
- **Starting WSL and its services without a user login. NOT FOUND.**
  - Hermes' documented recipe is Task Scheduler with the trigger **"At log on (your user)"**, running `C:\Windows\System32\wsl.exe -d Ubuntu --exec /bin/sh -c "sleep infinity"`. That is at logon, not boot.
  - Microsoft docs don't cover starting a distro before login. A "Run whether user is logged on or not" task is a community pattern, unverified here.
  - The Windows-native gateway (`schtasks /SC ONLOGON`) and the Ollama tray app both start at logon too.
  - The documented no-login options are: Ollama via NSSM; Hermes via `nssm` / `sc create` (Hermes discourages this). Windows auto-logon plus a locked screen is a possible workaround (INFERRED; not from these sources).
- **Docker Desktop. INFERRED** that it needs a signed-in user.
  - Its only auto-start setting is "**Start Docker Desktop when you sign in to your computer**" (off by default).
  - No documented pre-login or service mode for the Linux engine was found. `com.docker.service` is a helper used for Windows containers and the Hyper-V backend.
  - Windows Home runs Linux containers only, through the WSL 2 backend.
  - A pre-login alternative is Docker Engine installed inside the WSL distro under systemd. That is INFERRED and inherits the WSL boot problem above.
  - Sources: https://github.com/docker/docs/blob/main/content/manuals/desktop/settings-and-maintenance/settings.md, …/setup/install/windows-install.md (site: https://docs.docker.com/desktop/…)

### 18. OpenRouter per-key spend limit
- **Answer.** Yes.
  - Each API key can have an optional USD credit **`limit`** and a **`limit_reset`** of `daily`, `weekly`, `monthly` or `null`. Resets happen at midnight UTC.
  - Limits can be set when creating a key, edited later, or set through the Management (provisioning) API: `POST /api/v1/keys` and `PATCH /api/v1/keys/{hash}`.
  - `GET /api/v1/key` returns `limit_remaining`.
  - An exhausted key returns 402 with `limit_source: openrouter_key_limit`. One OpenRouter guide says 403 "Key limit exceeded"; the docs disagree.
  - Hermes' fallback treats 401/403 as an immediate switch; 402 counts as a capacity error for auxiliary tasks.
  - BYOK usage only counts toward the limit if `include_byok_in_limit` is enabled.
- **On this machine:** `GET /api/v1/key` returns `limit` but no `limit_reset` (`hermes usage --provider openrouter` does show "resets monthly"). An unknown model returns 400, which still triggers Hermes' fallback (docs/LESSONS.md).
- **Sources** (via search index; pages not fetchable from the sandbox)
  - https://openrouter.ai/docs/api_reference/limits
  - https://openrouter.ai/docs/api/api-reference/api-keys/create-a-new-api-key
  - https://openrouter.ai/docs/guides/overview/auth/management-api-keys
  - https://openrouter.ai/docs/guides/best-practices/capping-shared-agent-keys
- **VERIFIED** (official docs via the search index).

---

## Agent-owned email

**Main conclusion.** Hermes has two separate email features, and the docs say to use different accounts for each:
- **Email gateway**: people chat with the agent by emailing it.
- **Mailbox skill** (Himalaya, or the AgentMail optional skill): the agent operates an inbox as part of its tasks.

For the user's use case (receipts, travel confirmations, OTP codes, auto-forwards), the gateway is the **wrong tool**. Its code silently drops automated mail: `noreply@`, `notifications@`, `List-Unsubscribe`, `Auto-Submitted`, `Precedence: bulk`. That covers most receipts, confirmations and OTP mail. Use a skill polled by cron, or AgentMail's webhook/WebSocket events.

### 19. Hermes email as a gateway platform
- **Why it doesn't fit.** It's IMAP/SMTP with a password only, and it silently drops automated mail (`noreply@`, `List-Unsubscribe`, `Auto-Submitted`, `Precedence: bulk`), which covers most receipts, confirmations and OTP mail. Possible later use: chat-by-email (PLAN.md §13).
- **Relevant to S7:** Gmail filter auto-forwards are INFERRED to keep the original `From:` and headers; a manual forward from the user has From = the user (INFERRED).
- Docs: https://hermes-agent.nousresearch.com/docs/user-guide/messaging/email; code: `plugins/platforms/email/adapter.py`. **VERIFIED**; the forwarding behaviour is INFERRED.

### 20. Other ways to ingest a mailbox; AgentMail
- **Options in the Hermes docs**:
  - **Himalaya skill.** Bundled and installed by default; platforms linux/macos/windows. It drives the `himalaya` CLI over IMAP/SMTP with an app password, configured in `~/.config/himalaya/config.toml`.
    - The guide "Give Your Agent Its Own Email Address" pairs it with a cron poll every 15–30 minutes. The prompt should say not to act on instructions found inside mail.
    - The guide's install command is for Linux/macOS only (`curl … install.sh`). A Windows binary install is INFERRED.
    - The guide also warns: "Don't attach the agent's address to password resets, banking, or account recovery for anything that matters."
    - https://hermes-agent.nousresearch.com/docs/guides/agent-email-address and https://hermes-agent.nousresearch.com/docs/user-guide/skills/bundled/email/email-himalaya
    - **VERIFIED**
  - **Google Workspace skill** (`skills/productivity/google-workspace/`). Uses the Gmail API with OAuth2 and needs your own Google Cloud project. Example search command: `$GAPI gmail search "is:unread"`. The docs suggest Himalaya instead for email-only use. https://hermes-agent.nousresearch.com/docs/user-guide/skills/google-workspace. **VERIFIED**
  - **Hosted "gmail" connector** through the Nous tool gateway. Needs a Nous Portal sign-in; set up with `hermes connectors connect gmail [--alias NAME]`. https://hermes-agent.nousresearch.com/docs/reference/cli-commands (section `hermes connectors`). **VERIFIED**
  - **Google-hosted MCP servers (Gmail, Calendar)** are mentioned in the MCP docs, with no URL; they may need your own OAuth client (relevant to S9). https://hermes-agent.nousresearch.com/docs/user-guide/features/mcp. Mention VERIFIED; a Gmail MCP URL is **NOT FOUND** in the docs.
  - A widely used generic IMAP MCP server documented by Hermes: **NOT FOUND**.
- **AgentMail** (agentmail.to). An official Hermes **optional skill**: `optional-skills/email/agentmail`, authored by AgentMail, platforms linux/macos/windows. Its stated purpose: "AgentMail gives an agent its own email inbox for sending mail, receiving replies, completing email OTP flows…" (VERIFIED from the skill files).
  - **Setup**: `npm install -g agentmail-cli@latest`, put `AGENTMAIL_API_KEY=am_...` in `.env`, then check with `agentmail inboxes list --format json`. The skill install command is INFERRED by analogy: `hermes skills install official/email/agentmail`.
  - **API**: REST; the CLI is the skill's preferred interface. Docs at https://docs.agentmail.to.
  - **MCP**: hosted at `https://mcp.agentmail.to/mcp`. Authentication by OAuth, `?apiKey=`, or an `x-api-key` header. VERIFIED from the skill's `references/mcp.md`. Hermes config would be `mcp_servers.agentmail.url: https://mcp.agentmail.to/mcp` with `headers: {x-api-key: "${AGENTMAIL_API_KEY}"}`; that wiring is INFERRED.
  - **Inbound events**: webhooks to a public HTTPS server, and WebSockets at `wss://ws.agentmail.to/v0?api_key=…` with a `message.received` subscription (Python SDK `pip install agentmail`). VERIFIED from the skill references. WebSockets suit a home box with no public URL.
  - **Custom domains: yes.** Create the domain, add MX (receiving), MAIL FROM MX/SPF, DKIM and DMARC records, then verify.
    - Statuses run NOT_STARTED → … → VERIFIED.
    - Send-only domains are supported.
    - The docs recommend a subdomain (e.g. `agents.yourdomain.com`) so your root MX isn't replaced.
    - Optional `subdomains_enabled` with a wildcard MX allows inboxes on any subdomain.
    - VERIFIED via the search index of https://docs.agentmail.to/knowledge-base/custom-domain-setup and https://www.agentmail.to/docs/custom-domains.
  - **Pricing** (vendor blog via search index; INFERRED; AM1, read from the pricing page, takes precedence):
    - **Free**: 3 inboxes, about 3,000 emails/month, 100/day, webhooks and WebSockets included, **no custom domains**.
    - **Developer**: $20/month for 10 inboxes, 10,000 emails/month, custom domains (10).
    - **Startup**: $200/month. Enterprise: custom pricing.
    - A single inbox on `@agentmail.to` fits the Free plan. One inbox on your own domain needs Developer.
    - Sources: https://www.agentmail.to/blog/free-email-api-for-developers, https://www.agentmail.to/blog/trigger-ai-agent-when-email-arrives

### 21. Gmail forwarding verification; plus-addressing and wildcards
- **Gmail auto-forwarding needs a verified destination.**
  - Add the address under Settings → Forwarding and POP/IMAP. Gmail sends a confirmation message to it, and you must click the **verification link** in that message. Then choose "Forward a copy of incoming mail".
  - To forward only some mail, create a filter with a forward action; the destination must already be verified.
  - Gmail shows forwarding reminders in the inbox for the first week.
  - The destination's agent or tool must be able to receive and open that confirmation email. The Hermes gateway would *ignore* it if it comes from a noreply sender (INFERRED).
  - https://support.google.com/mail/answer/10957 (via search index). **VERIFIED**
- **Gmail plus-addressing: yes.** Mail to `you+anything@gmail.com` arrives in the same inbox, and Google suggests filtering on it.
  - The Workspace Learning Center page covers the same feature for Workspace users.
  - Sources: https://support.google.com/a/users/answer/9308648 and https://support.google.com/mail/answer/7436150 (dots). **VERIFIED** (search index).
- **AgentMail**:
  - Plus-addressing: **NOT FOUND** in the docs.
  - Catch-all: **not offered**, according to an AgentMail vendor blog (INFERRED).
  - The closest substitute is subdomain inboxes through `subdomains_enabled` plus a wildcard MX (VERIFIED, search index).
  - https://www.agentmail.to/docs/custom-domains

### 22. Gmail/Workspace bot mailbox: IMAP + app password vs OAuth
- The agent's mailbox is AgentMail (D4), which avoids Google auth. Gmail app passwords need 2-Step Verification and are revoked when the account password changes; the OAuth paths are the Google Workspace skill, the hosted `gmail` connector or a Google MCP server. Sources: https://support.google.com/mail/answer/185833, https://support.google.com/a/answer/14114704. **VERIFIED** (search index).

---

## Follow-ups

Same sources as above: Hermes `main` @ `275c211` docs and code, plus `plivo-dev/hermes-plivo-tools` @ `0123831` and `hermes-plivo-phone-gateway` @ `8a91a3b`.

### F1. Several independent instances on one machine
- **Answer.** Native and fully configured: **profiles**. "A profile is a separate Hermes home directory," with its own `config.yaml`, `.env`, `SOUL.md`, memories, sessions, skills, cron jobs, `state.db`, logs and gateway state.
- **How it works.** The profile boundary is the `HERMES_HOME` environment variable. The wrapper sets `HERMES_HOME=~/.hermes/profiles/<name>`.
- **Commands**
  ```bash
  hermes profile create local              # blank profile (no --clone, so no keys/memory copied)
  hermes -p local setup                    # or: local setup   (auto-created alias)
  hermes --profile=local doctor            # -p / --profile works in any position
  hermes -p local gateway install          # Windows task name: Hermes_Gateway_<profile>
  ```
  - `--clone` copies `config.yaml`, `.env`, `SOUL.md`, skills and MEMORY.md/USER.md.
  - `--clone-all` copies everything except history and cron jobs.
  - **For the local (no cloud keys) profile, use neither.**
- **Gateway: one process by default.**
  - `hermes update` folds profile gateways into **one multiplexed host gateway** (`gateway.multiplex_profiles`).
  - Each turn still resolves "the routed profile's config, skills, memory, SOUL, **and provider keys** — credentials are never shared across profiles."
  - A missing key stays unresolved: "never the default profile's value."
  - Allowlists, approvals and MCP connections are also per profile.
  - For a separate OS process instead, set `gateway.standalone: true` in that profile.
  - **On this machine (v0.22.4):** the default gateway multiplexes every profile regardless, and ignores `multiplex_profiles: false`. `gateway.standalone: true` is required for a profile to get its own process and bot; `hermes config get` calls it unrecognized, but the gateway log confirms it (docs/LESSONS.md, Hermes).
- **Bot tokens.** Each profile needs its own bot token. Two profiles using the same token are blocked by "token locks."
- **Risks for a "no cloud keys" profile** (INFERRED):
  1. **OAuth logins.** Anthropic, Codex and xAI OAuth logins are shared through the root `~/.hermes/auth.json` for clones ("the new profile keeps reading the login from the root"). Check with `hermes -p local auth list`. **On this machine (v0.22.4):** every profile lists the root credential pool, including the cloud profile's `env:`-sourced OpenRouter key, even with its own empty `auth.json`; from local it isn't usable (`/model openrouter:…` still goes to `localhost:11434`, 400). An OAuth login in the root would be the real risk.
  2. **Fallback.** Set `model.provider: custom` and no `fallback_providers`. The built-in auxiliary discovery chain (OpenRouter → Nous → …) runs "only when no main provider is selected."
  3. **Windows environment.** Don't put cloud keys in Windows User environment variables.
  4. **External CLIs.** `HOME` stays shared by default. Use `terminal.home_mode: profile` for strict per-profile tool configuration.
- **Sources**
  - https://hermes-agent.nousresearch.com/docs/user-guide/profiles
  - https://hermes-agent.nousresearch.com/docs/user-guide/multi-profile-gateways (section "What is isolated per profile")
  - https://hermes-agent.nousresearch.com/docs/user-guide/features/fallback-providers
- **VERIFIED**, except the risk notes, which are INFERRED.

### F2. Is memory sent with every model call?
- **Answer: yes.**
  - MEMORY.md and USER.md "are injected into the system prompt as a frozen snapshot at session start."
  - The system prompt is sent on **every** API call, along with `SOUL.md`, the project context file and the full conversation history.
  - Honcho (when enabled, in `hybrid`/`context` mode) injects "two layers of context … into the system prompt" **every turn**. Honcho also sends turns to the Honcho API.
  - `session_search` recall is on demand (a tool call). Its results go into the conversation, and so to whatever model is active.
- **Implication.** A `/model <cloud> --once` escalation, or any fallback, sends the memory snapshot plus the whole session history to the cloud provider (INFERRED, but it follows directly from the above).
- **Mitigations**
  - A separate local-only profile (F1).
  - `memory.memory_enabled: false` / `memory.user_profile_enabled: false` in the cloud-capable profile.
  - `/new` before escalating. This still includes the memory snapshot.
- **Sources**
  - https://hermes-agent.nousresearch.com/docs/user-guide/features/memory (section "How Memory Appears in the System Prompt")
  - https://hermes-agent.nousresearch.com/docs/user-guide/features/honcho (section "Two-Layer Context Injection")
  - https://hermes-agent.nousresearch.com/docs/user-guide/configuration (section "Memory Configuration")
- **VERIFIED**. The implication is INFERRED.

### F3. Scope of `fallback_providers`; `channel_overrides` vs `/model`; disabling `/model`
- **`fallback_providers` is global** (top-level), with two scoped exceptions:
  - **Subagents**: `delegation.fallback_providers`. Setting it to `[]` disables fallback for them.
  - **Cron**: an *unpinned* job inherits the global chain. A job pinned with `--model` / `--provider` **never** falls back ("if that route fails, the run fails").
  - No per-channel fallback key was found. `channel_overrides` accepts only `model`, `provider` and `system_prompt`. So **per-channel fallback: NOT FOUND**.
- **`channel_overrides` doesn't lock a chat.** Docs: "Resolution priority for the model is: session `/model` override → `channel_overrides` → global config. A user running `/model` in a chat still wins over the channel default."
- **Disabling `/model`.**
  - A dedicated off switch is **NOT FOUND**. The docs list "model switching" as something that "may be gated in the future."
  - Today's workaround uses the gateway's admin/user split:
    ```yaml
    gateway:
      platforms:
        telegram:
          extra:
            allow_admin_from: ["<id>"]
            user_allowed_commands: [status]
    ```
    Non-admins get only the listed commands plus `/help` and `/whoami`.
  - To block `/model` for yourself, you would have to make yourself a non-admin (INFERRED).
  - The docs example uses `discord`; Telegram support is stated ("Every messaging platform that supports a per-user allowlist (Telegram, …)").
- **Sources**
  - https://hermes-agent.nousresearch.com/docs/user-guide/features/fallback-providers
  - https://hermes-agent.nousresearch.com/docs/user-guide/messaging (sections "Per-Channel Model…" and "Admins vs Regular Users")
  - https://hermes-agent.nousresearch.com/docs/reference/slash-commands
- **VERIFIED**

### F4. Docker backend on native Windows; default mounts; one-folder restriction
- **Native Windows: INFERRED yes.**
  - The docs don't say it outright. They do say "Docker Desktop or Docker Engine installed and running."
  - The code handles Windows drive paths (`_is_windows_drive_path`).
  - A dedicated test, `tests/tools/test_docker_windows_cwd_mount.py`, covers binding a Windows workspace (`D:\Work\proj`) into the container.
  - The docs also give `C:\Users\me\project` as a `terminal.cwd` example on the Docker page.
- **Default mounts (VERIFIED from docs and code)**
  - With `container_persistent: true` (the default), `/root` and `/workspace` are bind-mounted from `~/.hermes/sandboxes/docker/<task_id>/`. With `false`, they are tmpfs instead.
  - **Read-only** mounts:
    - The skills directory.
    - Credential files that skills or config declare (`terminal.credential_files`).
    - Cache directories.
  - **No host project directory** is mounted unless `docker_mount_cwd_to_workspace: true`. Docs: "Hermes does **not** pass your current host working directory into the container unless you explicitly opt in."
  - No environment secrets are passed except `docker_forward_env` / `docker_env`.
- **Restricting to one folder: yes.** Leave `docker_mount_cwd_to_workspace: false` and mount exactly one directory:
  ```yaml
  terminal:
    backend: docker
    docker_mount_cwd_to_workspace: false
    docker_volumes: ["C:/Users/me/agent-work:/workspace/work"]   # add :ro for read-only
    docker_network: true          # false = --network=none
    container_persistent: false   # optional: fresh container per session
  ```
  The Windows host-path syntax is INFERRED; the docs examples use POSIX paths.
- **Sources**
  - https://hermes-agent.nousresearch.com/docs/user-guide/configuration (sections "Docker Backend", "Docker Volume Mounts" and "Optional: Mount the Launch Directory")
  - Code: `tools/environments/docker.py` (lines 548–578, 854–926)

### F5. `hermes vault`: does the model see plaintext? Gating TOTP
- **Plaintext: the tool layer fills it in.** Docs: "the password never enters the model's context through Hermes: not in tool results, logs, the session database, or the CLI arguments of any process."
  - The agent calls the `browser_vault` tool (toolset `browser`) with actions `list | fill | save_login | enter_code | unlock`.
  - The result it sees is `{filled_fields: 1, origin: …}`.
  - Fills go over the CDP socket and are refused unless the page origin exactly matches the saved one.
  - **Card** fills require a user confirmation (`_confirm_payment_fill`, which goes through the approval surface).
  - The page itself does receive the secret.
- **TOTP**
  - With a seed stored, `enter_code` generates the code automatically: "Nobody is asked."
  - A built-in setting to gate it or turn TOTP off is **NOT FOUND**.
- **Workarounds (INFERRED)**
  1. Don't store the authenticator key. The user is then asked for the code in a masked prompt.
  2. Add a `pre_tool_call` hook that returns `{"action":"approve"}` when `tool_name == "browser_vault"` and `args.get("action") == "enter_code"` (or `fill`).
  3. Opt out of the detected password managers: `vault.onepassword.enabled: false`, `vault.bitwarden.enabled: false`.
- **Sources**
  - https://hermes-agent.nousresearch.com/docs/user-guide/features/credential-vault
  - Code: `tools/browser_vault_tool.py` (schema at line 589, `_confirm_payment_fill` at line 571)
- **VERIFIED**. The workarounds are INFERRED.

### F6. Cron syntax for a per-job model and Telegram delivery; minimum interval; skills
- **Command**
  ```bash
  hermes cron create "every 10m" "Triage the agent inbox; message me only if something needs action." \
    --name inbox-triage --skill himalaya \
    --model qwen3:30b-a3b --provider <provider-name> \
    --deliver telegram          # or telegram:<chat_id>  /  telegram:<chat_id>:<thread_id>
  # optional: --failure-deliver local  --reasoning-effort low  --pin  --workdir <abs path>
  ```
  - `--model`: "Pin this job to a specific inference model (user-owned; the agent's cronjob tool cannot set this)."
  - `--provider`: the provider paired with `--model`.
  - A pinned job does **not** use `fallback_providers`.
  - There is no `--base-url` flag. Whether a named entry from the `providers:` section can be used as `--provider` for local Ollama is INFERRED, not tested.
  - **On this machine (PLAN.md Appendix A, S3):** `--provider ollama` with `providers.ollama.base_url` runs locally. In the default profile, `--provider custom` goes to the CLOUD, because `custom` takes `model.base_url` (OpenRouter).
  - A config-level default is `cron.model` / `cron.model_provider`.
- **Minimum interval.** No documented minimum. The scheduler "ticks … every 60 seconds," so about 1 minute is the effective floor (INFERRED).
- **Skills: yes.** Use `--skill <name>`, repeatable, plus `--add-skill` / `--remove-skill` on `edit`. In chat: `/cron add "every 1h" "..." --skill blogwatcher`.
- **Cost-saving modes**
  - `--no-agent --script x.sh`: runs the script and delivers its stdout verbatim; no LLM.
  - `--monitor-script`: the agent runs only when the script's output changes.
- **Sources**
  - https://hermes-agent.nousresearch.com/docs/user-guide/features/cron
  - Code: `hermes_cli/subcommands/cron.py` (lines 23–80)
- **VERIFIED**. The minimum interval is INFERRED.

### F7. What the Himalaya skill needs; search capabilities
- **Requirements**
  1. The `himalaya` CLI binary (`himalaya --version`).
     - Documented install options: `curl -sSL https://raw.githubusercontent.com/pimalaya/himalaya/master/install.sh | PREFIX=~/.local sh`, `brew install himalaya`, or `cargo install himalaya --locked`.
     - On native Windows, use `cargo` or a release binary (INFERRED; the skill lists windows as a platform).
  2. A config file at `~/.config/himalaya/config.toml`, with IMAP/SMTP settings and `backend.auth.command` for the app password.
     - Gmail needs `folder.aliases.*` (v1.2.0+ syntax).
     - The config path on native Windows is **NOT FOUND**.
- **Search**
  - **Folder: yes.** `himalaya envelope list --folder "Sent"`, plus `himalaya folder list`.
  - **Sender/subject: yes.** `himalaya envelope list from john@example.com subject meeting`.
  - Paging: `--page`, `--page-size`. Reading: `himalaya message read <id>`.
  - **Date filters: NOT FOUND** in the Hermes skill docs. Upstream himalaya's query language is believed to support `before`/`after` and `order by`; that is INFERRED and not verified here.
  - For OTP lookup, "latest from sender X in INBOX" works with `from` plus default newest-first listing (INFERRED).
- **Source**: https://hermes-agent.nousresearch.com/docs/user-guide/skills/bundled/email/email-himalaya (skill: `skills/email/himalaya/`)
- **VERIFIED**, except where marked.

### F8. Plivo plugin: signatures, tool names, environment variables
- **Webhook signatures: yes.**
  - README: "Answer callbacks are signature-verified against every signature header Plivo sends." Code: `adapter.py::_verify_signature` (line 1363).
  - Each call also mints a short-lived token in the audio WebSocket URL.
  - Verification is turned off only by `PLIVO_VOICE_INSECURE_NO_SIGNATURE=true`, which logs a warning.
  - Caller ID is not verified; the code comment says "caller ID is spoofable."
- **Tools.** Registered by the dependency `hermes-plivo-tools` (plugin `plivo-tools`), each in its own toolset:
  - `make_call` (toolset `plivo_make_call`)
  - `send_sms` (`plivo_send_sms`)
  - `lookup_number` (`plivo_lookup_number`)
  - Each registers with `requires_env=["PLIVO_AUTH_ID","PLIVO_AUTH_TOKEN"]`.
  - So the `pre_tool_call` gate should match **`tool_name == "make_call"`**.
- **Environment variables**
  - Tools: `PLIVO_AUTH_ID`, `PLIVO_AUTH_TOKEN`, `PLIVO_PHONE_NUMBER`, `PLIVO_ANSWER_URL`, `PLIVO_ANSWER_METHOD`, `PLIVO_API_BASE`, `PLIVO_LOOKUP_BASE`.
  - Voice gateway:
    - Required: `PLIVO_AUTH_ID`, `PLIVO_AUTH_TOKEN`, `PLIVO_PHONE_NUMBER`.
    - Optional: `PLIVO_VOICE_PUBLIC_URL`, `_AUTO_WIRE`, `_WS_PORT`, `_ALLOWED_USERS`, `_ALLOWED_DESTINATIONS`, `_INSECURE_NO_SIGNATURE`, `_SILERO_MODEL`, `_IDLE_TIMEOUT`, `_MAX_CALL_SECONDS`, `_MAX_CONCURRENT_CALLS`, `_STREAMING_TTS`, `_SYSTEM_PROMPT`, `_RAW_DUMP` (each with the `PLIVO_VOICE` prefix).
  - Empty `PLIVO_VOICE_ALLOWED_DESTINATIONS` refuses every outbound call.
- **Sources**
  - https://github.com/plivo-dev/hermes-plivo-phone-gateway (README, `hermes_plivo_voice/plugin.yaml`, `adapter.py`)
  - https://github.com/plivo-dev/hermes-plivo-tools (`hermes_plivo_tools/__init__.py` lines 32–55)
- **VERIFIED**

### F9. Skeleton for a `pre_tool_call` approval-policy plugin
- **Layout**: `~/.hermes/plugins/<name>/` (Windows native: `%LOCALAPPDATA%\hermes\plugins\<name>\`) containing `plugin.yaml` and `__init__.py`.
  - A plugin loads **only once enabled**: `hermes plugins enable <name>`, or add it to `plugins.enabled`. Restart Hermes or the gateway afterwards.
  - The gateway does not load project-local `.hermes/plugins/`.
  - The `%LOCALAPPDATA%` path follows from `HERMES_HOME` (INFERRED).
- **Registration**: `register(ctx)` calls `ctx.register_hook("pre_tool_call", fn)`.
  - The callback receives keyword arguments `tool_name`, `args`, `task_id`, plus `**kwargs`.
  - It fires before every tool, built-in or plugin, and fires separately for each parallel call.
- **Return shapes**
  - `{"action": "block", "message": "<non-empty>"}`
  - `{"action": "approve", "message": "...", "rule_key": "optional:scope"}`: escalates to the existing human-approval gate. Denial, timeout or error **fails closed**.
  - `{"action": "modify", "args": {...}}`
  - `None`: no decision.
  - Precedence: `block` > `approve` > nothing.
  - A callback that runs past `plugins.hook_callback_timeout` (default 30 s) or raises → the tool is blocked.
- **Skeleton** (manifest per the docs' minimal example; the hook body is assembled from the documented contract)
  ```yaml
  # plugin.yaml
  name: approval-policy
  version: "0.1"
  description: Draft-first approval gate for outbound side effects
  ```
  ```python
  # __init__.py
  GATED = {"make_call", "send_sms", "call_place"}          # tool names to gate

  def gate(tool_name, args, task_id, **kwargs):
      if tool_name in GATED:
          return {"action": "approve",
                  "message": f"{tool_name} requested: {str(args)[:300]}",
                  "rule_key": f"policy:{tool_name}"}
      if tool_name == "browser_vault" and (args or {}).get("action") == "enter_code":
          return {"action": "approve", "message": "2FA code entry", "rule_key": "policy:totp"}
      return None                                           # no directive

  def register(ctx):
      ctx.register_hook("pre_tool_call", gate)
  ```
  - For the docs' own minimal hook example, see the "warn on dangerous tools" `pre_tool_call` example: `def warn_dangerous(tool_name, **kwargs): ...` with `ctx.register_hook("pre_tool_call", warn_dangerous)`.
  - Custom tools go in the same plugin: `ctx.register_tool(name=..., toolset=..., schema=..., handler=...)`.
  - Whether an "always approve" answer with a `rule_key` persists into `command_allowlist` is INFERRED; test it.
- **Sources**
  - https://hermes-agent.nousresearch.com/docs/user-guide/features/hooks (`pre_tool_call`, in both `main` and stable)
  - https://hermes-agent.nousresearch.com/docs/user-guide/features/plugins (sections "Quick overview" and "Plugins are opt-in")
- **VERIFIED**

### F10. Per-call model/provider/token/cost logging; usage commands
- **Per session (stored): yes.** The `sessions` table in `state.db` has:
  - `model`, `model_config`, `billing_provider`, `billing_base_url`, `billing_mode`
  - `input_tokens`, `output_tokens`, `cache_read_tokens`, `cache_write_tokens`, `reasoning_tokens`
  - `estimated_cost_usd`, `actual_cost_usd`, `cost_status`, `cost_source`, `api_call_count`
  - The docs give an SQL "Token Usage Statistics" query, grouped by model.
  - These are per-session totals. A **per-call** stored log: **NOT FOUND**.
- **Per call (hook): yes.** The observer hook `post_api_request` receives:
  - `session_id`, `platform`, `model`, `provider`, `base_url`, `api_call_count`, `api_duration`, `response_model`, `finish_reason`, `usage`, `context_length`
  - `api_request_error` fires on failures, with status and retry timing.
  - A small plugin writing these to JSONL gives the escalation and cost log. Whether a fallback switch is distinguishable is INFERRED (compare `model`/`provider` against the configured primary).
- **Commands**
  - `/usage` in a session: token usage, estimated cost breakdown, context state, provider account limits.
  - `/insights [days]`, and `hermes insights [--days N] [--source telegram]`: usage analytics.
  - `hermes usage [--provider openrouter] [--json]`: OpenRouter credits and account limits.
  - Logs: `~/.hermes/logs/` (`agent.log`, `errors.log`, `gateway.log`), per profile.
- **Sources**
  - https://hermes-agent.nousresearch.com/docs/developer-guide/session-storage
  - https://hermes-agent.nousresearch.com/docs/user-guide/features/hooks (section "API-request observer hooks")
  - https://hermes-agent.nousresearch.com/docs/reference/cli-commands (sections `hermes usage` and `hermes insights`)
  - https://hermes-agent.nousresearch.com/docs/reference/slash-commands
  - Code: `agent/turn_response_intake.py` (lines 66–95)
- **VERIFIED**

---

## AgentMail (2026-10-22)

For the agent's email (PLAN.md §6). Items are numbered AM1–AM14.

**How this was checked.** docs.agentmail.to, agentmail.to, api.agentmail.to and mcp.agentmail.to couldn't be reached from the sandbox: the egress proxy refused them and WebFetch DNS failed. No live API call was made. Instead:
- **Read in AgentMail's GitHub source** (shallow clones):
  - `agentmail-to/agentmail-python` @ `ddbd79b` (2026-10-19). Its `reference.md` and `src/` are generated by Fern from AgentMail's API definition (PyPI `agentmail` 2.0.18).
  - `agentmail-to/agentmail-mcp` @ `2f4e66d` (2026-10-20), including `mcp-manifest.json`, which is generated from the hosted server.
  - `agentmail-to/agentmail-cli` @ `022b11d` (npm `agentmail-cli` 1.9.0).
  - `agentmail-to/agentmail-skills` @ `cde357f`.
  - `NousResearch/hermes-agent` @ `4e58c72` (2026-10-21), for the optional skill.
- **Read through the search index only:** docs.agentmail.to and agentmail.to pages. These are machine-written summaries, not page text.

Tags:
- **VERIFIED (source):** read in that GitHub source.
- **VERIFIED (search):** a docs snippet that states the fact directly.
- **INFERRED:** a summary that paraphrases or conflicts, or a deduction.
- **NOT FOUND:** not in any source reached.

### AM1. Plans and limits
- **Free, $0:** 3 inboxes, 3,000 emails/month, 100/day, 3 GB storage, no custom domain. VERIFIED (search): https://www.agentmail.to/pricing.md. "Custom domains require a paid plan" is VERIFIED (source): `agentmail-skills/agentmail/references/admin.md`.
- **Developer, $20/month:** 10 inboxes, 10,000/month, 1,000/day, 10 GB, 10 custom domains. VERIFIED (search). **Startup, $200/month:** INFERRED.
- Whether the monthly cap counts received mail: NOT FOUND.
- **API rate limits:** no numbers. `429` with `Retry-After`, and the SDKs retry twice. VERIFIED (source).

### AM2. API keys: scopes and permissions
- **Inbox-scoped keys:** `POST /v0/inboxes/{inbox_id}/api-keys` (also `GET`, `PATCH /{api_key_id}`, `DELETE /{api_key_id}`). CLI: `agentmail inboxes api-keys create --inbox-id <id> --name … --json …`. Pod-scoped and organization keys exist too (`/v0/pods/{pod_id}/api-keys`, `/v0/api-keys`). VERIFIED (source): `reference.md` §Inboxes ApiKeys; `api_keys/types/bearer_api_key.py`.
- **`permissions` is a whitelist:** "When omitted all permissions are granted. Otherwise, only permissions set to true are granted." VERIFIED (source): `api_keys/types/api_key_permissions.py`.
  - Mail and labels: `inbox_read`, `message_read`, `message_send`, `message_reply` (public-key-signed requests only), `message_update` (labels; also needed for threads), `message_delete`, `draft_read` / `draft_create` / `draft_update` / `draft_delete` / `draft_send`, and `label_spam_read` / `label_blocked_read` / `label_unauthenticated_read` / `label_trash_read`.
  - Admin: `list_entry_read` / `list_entry_create` / `list_entry_delete`, `webhook_*`, `api_key_*`, `metrics_read`, `domain_*`, `pod_*`, `inbox_create` / `inbox_update` / `inbox_delete`.
  - `agent_armor_release` is opt-in, even for keys without a `permissions` object.
- **Scope intersection:** an inbox-scoped key can't gain organization-level permissions, and a child key is limited to its parent's effective permissions. VERIFIED (search): https://docs.agentmail.to/permissions.
- **Expiry:** "A key cannot create one that outlives it." `expires_at` is immutable. VERIFIED (source).
- **Drafts:** whether a draft with `send_at` needs `draft_send`: NOT FOUND. Leave `draft_create` out of a receive-only key.

### AM3. Sending
- **Endpoints:**
  - `POST /v0/inboxes/{inbox_id}/messages/send`
  - `POST …/messages/{message_id}/reply`, `…/reply-all`, `…/forward`
  - `POST …/drafts` (`send_at` schedules sending), `PATCH …/drafts/{draft_id}`, `POST …/drafts/{draft_id}/send`
  - VERIFIED (source).
- **Turning sending off for a whole inbox:** NOT FOUND. `status: paused` stops both sending and receiving. VERIFIED (source).
- **Send allowlist:** `POST /v0/inboxes/{inbox_id}/lists/send/allow` (org-wide: `/v0/lists/send/allow`). "The first entry on an allow list turns that list on: from then on every … recipient (send) not on it is rejected." VERIFIED (source): `mcp-manifest.json`, `create_list_entry`.
- **Per send:** 50 recipients at most. VERIFIED (source): Hermes skill `references/core.md`.

### AM4. Addressing
- **Plus-addressing:** NOT FOUND.
- **Aliases:** NOT FOUND. An inbox has one address. VERIFIED (source): `inboxes/types/inbox.py`.
- **Username:** `POST /v0/inboxes {username, domain?, display_name?, client_id?}`. "Randomly generated if not specified"; `domain` defaults to `agentmail.to`. VERIFIED (source).

### AM5. Labels
- **Labels:** a `labels` list on every message and thread. System labels include `received`, `sent`, `unread`, `spam`, `blocked`, `unauthenticated`, `trash` and `agent-armor-held`. "System labels such as received and sent cannot be changed." VERIFIED (source).
- **Set or remove:** `PATCH /v0/inboxes/{inbox_id}/messages/{message_id} {add_labels, remove_labels}`, `POST …/messages/batch-update`, or `PATCH …/threads/{thread_id}`. Needs `message_update`. VERIFIED (source).
- **List:** `GET /v0/inboxes/{inbox_id}/messages` with `labels` (all must match), `before`, `after`, `ascending`, `from`, `to`, `subject`, and `include_spam` / `include_blocked` / `include_unauthenticated` / `include_trash`. VERIFIED (source). A "doesn't have this label" filter: NOT FOUND.

### AM6. Sender authentication, spam, Agent Armor
- **Headers:** `Message.headers` is a `Dict[str, str]`. The raw `.eml` comes from `GET /v0/inboxes/{inbox_id}/messages/{message_id}/raw` (a signed download URL). VERIFIED (source). Whether `headers` holds every `Authentication-Results` line in order: NOT FOUND.
- **Screening:** mail that explicitly fails authentication is dropped with no bounce, and mail with no authentication results is labelled `unauthenticated`. The pages conflict on mail from senders with neither SPF nor DKIM. INFERRED (search): https://docs.agentmail.to/knowledge-base/inbound-emails-missing, https://docs.agentmail.to/knowledge-base/spf-dkim-dmarc.
- **Labels for held-back mail:** `unauthenticated`, `blocked` and `spam` each have their own event (`message.received.*`) and their own `label_*_read` permission, and default lists leave them out. VERIFIED (source).
- **Agent Armor** scans for agent manipulation. Each message gets `agent_armor: {status, verdict: clear|review, reason, …}`. In hold mode, a `review` message is held (`agent-armor-held`) until released. VERIFIED (source). Monitor mode is the default; it's free in AgentMail Labs, which is US-only. INFERRED (search): https://agentmail.to/docs/agent-armor.md.

### AM7. Inbound events
- **WebSockets:** `wss://ws.agentmail.to/v0?api_key=…`, subscribe with `{"type":"subscribe","event_types":["message.received"],"inbox_ids":[…]}`. The connection is outbound only, so no public URL is needed. VERIFIED (source).
- **Webhooks** need a public HTTPS URL; they're signed by Svix (a webhook-delivery service). VERIFIED (source).
- **Events:** `message.received` (plus `.spam`, `.blocked`, `.unauthenticated`), `message.security.*`, `message.sent`, `delivered`, `bounced`, `complained`, `rejected`, `opened`, `domain.verified`. VERIFIED (source): `events/types/event_type.py`.

### AM8. MCP server and local relay
- **Hosted server:** `https://mcp.agentmail.to/mcp`. It authenticates with `?apiKey=`, `x-api-key` or `Authorization: Bearer am_…`, otherwise OAuth. It has no tool filter. VERIFIED (source): `packages/server/src/index.ts`. The deployment provider is Manufact (`docs/architecture.md`).
- **Local relay:** npm `agentmail-mcp` (1.1.0) and PyPI `agentmail-mcp` (1.0.0). They are stdio bridges that read `AGENTMAIL_API_KEY` and fetch the tool list from the hosted server. With `--tools a,b`, the npm bridge lists only those tools and refuses calls to the others. VERIFIED (source): `packages/npm-stdio-bridge/README.md`, `src/index.ts`. `--tools` in the PyPI bridge: NOT FOUND.
- **Tools:** 53 in total (`mcp-manifest.json`).
  - They can send: `send_message`, `reply_to_message`, `forward_message`, `send_draft`, `create_draft` and `update_draft` (with `sendAt`), `agent_attach_human`, and calendar tools that send invites.
  - Read-only: `list_inboxes`, `get_inbox`, `list_messages`, `search_messages`, `get_message`, `list_threads`, `search_threads`, `get_thread`, `get_attachment`, among others.
  - MCP `list_messages` takes `includeSpam` and `includeTrash` only.
  - VERIFIED (source).
- **Hermes naming:** Hermes registers MCP tools as `mcp__<server>__<tool>`. VERIFIED (source): hermes-agent `tools/mcp_tool_schema.py`. The feature docs still show `mcp_<server>_<tool>`.

### AM9. Hermes skill `official/email/agentmail`
- **Install:** `hermes skills install official/email/agentmail`. VERIFIED (source): `website/docs/user-guide/skills/optional/email/email-agentmail.md`.
- **What it is:** it drives the `agentmail` CLI (`npm install -g agentmail-cli@latest`) through the terminal tool, and uses the env var `AGENTMAIL_API_KEY`. It can send, reply, forward and sign up. VERIFIED (source).
- **The CLI:** it also auto-loads a `.env` file from its working directory. REST base: `https://api.agentmail.to/v0`, with `Authorization: Bearer`. VERIFIED (source).
- **Command form:** the skill writes `inboxes:messages`, while the CLI reference writes `inboxes messages`. Which the CLI accepts: NOT FOUND.

### AM10. IMAP and SMTP
- **Servers:** `imap.agentmail.to:993` and `smtp.agentmail.to:465`. The username is the inbox address and the password is an API key. VERIFIED (source): `agentmail-skills/agentmail/references/admin.md`.
- **Folders:** `INBOX`, `Sent`, `Trash`, `Spam`, and an empty `Drafts`. No custom folders. VERIFIED (search): https://docs.agentmail.to/imap-smtp.
- **Permissions:** SMTP needs `message_send`, and IMAP needs some `label_*_read` permissions to stay in sync. INFERRED (search).

### AM11. Allow and block lists
- **Paths:** `/v0/inboxes/{inbox_id}/lists/{send|receive|reply}/{allow|block}[/{entry}]`, plus org-wide and pod-level versions.
- **Entries:** an address or a domain, and "a domain matches only itself". Block beats allow.
- **Permissions:** `list_entry_*`.
- VERIFIED (source).
- **Unclear:** what happens to a sender who isn't on a receive allowlist. One tool description says "blocked inbound mail is kept with the blocked label"; another says the sender is "rejected". INFERRED: test it (PLAN.md S8).
- **Counts:** `MetricEventType` includes `message.received.blocked` and `message.received.unauthenticated` (`GET /v0/inboxes/{inbox_id}/metrics/events`, needs `metrics_read`). VERIFIED (source). The query shape wasn't read.

### AM12. Data handling
- **Deletion:** `DELETE` on messages, threads (permanent) and inboxes, or the `trash` label as a soft delete. VERIFIED (source).
- **Storage:** AWS in the US and EU. The EU API is `api.agentmail.eu`, and EU is listed under Enterprise. The endpoint is VERIFIED (source: SDK `environment.py`); the rest is INFERRED (search): https://www.agentmail.to/legal/subprocessors.
- **Retention:** persistent by default; a 24-hour expiry is available on request; backups are kept 30 days. INFERRED (search): https://www.agentmail.to/legal/privacy-policy.
- **Training on mail content:** NOT FOUND.

### AM13. Attachments
- **Fetch:** `GET …/messages/{message_id}/attachments/{attachment_id}` returns `download_url` (a signed CDN URL), `text_url` (extracted text, when available) and `expires_at`. VERIFIED (source).
- **Size limits:** 6 MB inline per send request, about 30 MB with URLs, 10 MB over SMTP. INFERRED (search). Inbound maximum: NOT FOUND.

### AM14. Server-side forwarding
- **Automatic forwarding:** NOT FOUND. The API has no rules or auto-forward resource; the only forward is the per-message one, which is a send. VERIFIED (source) that the API surface has none.

## Reference design: Muse (2026-10-23)

How another agent product handles the same risks; the source for PLAN.md's hardening items (S16, P2.1b, P3.1, P3.5). Items MU1–MU6. Read with WebFetch on 2026-10-23:
- **[A]** "How We Built Safety Into Muse", Tarek Sheasha, Meta Superintelligence Labs, 2026-09-08: https://research.meta.ai/blog/security-and-safety-for-ai-agents-our-approach-with-muse (`https://security.muse.ai/` redirects here).
- **[B]** "How We Designed Muse", Mona Sarantakos with Christine Awad, 2026-09: https://introducing.muse.ai/

These describe Muse, not Hermes: nothing here is a Hermes command or key. Tags as above; VERIFIED (source) means the post states it.

### MU1. A permission service outside the agent
- "Sentinel" is "a separate host-side agent", outside the agent's isolated runtime cell, and "the sole permission authority" for connector actions and network egress; the safety services run as separate systemd units outside the cell "so attackers cannot disable these protections". VERIFIED (source) [A].
- No hash or signature check on the safety configuration is described. NOT FOUND.

### MU2. Egress
- Sentinel checks every request (hostname, resolved IP, port, protocol, method, path); clean requests within a "narrowly bounded auto allow policy" pass, and a process that has handled untrusted data loses the auto-allow. VERIFIED (source) [A].
- A named-host allowlist: NOT FOUND (the post describes per-request policy instead).
- SSRF: public hostnames that resolve to private addresses are blocked at egress. VERIFIED (source) [A].

### MU3. Credentials
- The agent never sees real credentials: code in the cell holds a surrogate token, swapped for the real one at the network boundary; browser passwords are injected from a separate store. VERIFIED (source) [A].

### MU4. Isolation and prompt injection
- `systemd-nspawn` cell (unprivileged root mapping, own filesystem, virtual NIC, filtered syscalls) inside a per-user VM. VERIFIED (source) [A].
- Assume-breach: external data labelled untrusted, a classifier ensemble, and human approval for data leaving the VM; "Muse isn't immune to attack". VERIFIED (source) [A].
- A reader/actor split (one model reads untrusted content, another acts): NOT FOUND. The nearest measures are the untrusted-data labels, losing auto-allow after untrusted input, and a browser sub-agent. INFERRED.

### MU5. Purchases and approvals
- Muse detects checkout pages and requires approval showing the exact purchase; single-use card numbers per merchant; a classifier flags high-risk form submissions. VERIFIED (source) [A].
- Hard-to-undo actions (an email, a purchase) stop for an approval card by default; browsing doesn't. VERIFIED (source) [B].

### MU6. Data
- VM data is backed up continuously; trajectories may be used for training after PII removal, with an opt-out. VERIFIED (source) [A]. Not related to OpenRouter's retention (PLAN.md D9).
