# Hermes hybrid agent

This repo holds the build plan, and the start of a distributable package, for a personal agent built on Hermes Agent, running on a Windows 11 laptop. The default profile is cloud-first through OpenRouter under a capped key, falling back to a local Ollama model; the private profile is local-only. Every model call is logged.

- [PLAN.md](PLAN.md): the actionable runbook, with decisions, phased tasks, Done-when checks, spikes and autonomy tags. Start here.
- [CLAUDE.md](CLAUDE.md): rules for the Claude agent that sets the machine up.
- [docs/verification-notes.md](docs/verification-notes.md): the source checks behind every command and config key.
- [docs/LESSONS.md](docs/LESSONS.md): what the machine taught us; wins over the notes where they differ.
- [docs/SETUP-GUIDE.md](docs/SETUP-GUIDE.md): the steps that can't be scripted.
- [docs/status-notes.md](docs/status-notes.md): plain-language build facts appended to the agent's STATUS.md.
- [docs/original/](docs/original/hermes_hybrid_agent_plan.html): the original Slack-shared plan, unchanged.
- [templates/](templates/): the approval-policy plugin, call brief, inbox-triage prompt and email allowlist, until their tasks move them into `plugins/` or `config/templates/`.
- [plugins/usage-log](plugins/usage-log): the per-call usage log. [config/templates/](config/templates/): the profile config templates.
- [bench/](bench/README.md): the local-model benchmark, with tasks, synthetic fixtures, answer keys and a scoring sheet.

Templates contain placeholders only (`<your name>`, `<your number>`). Never commit instance data or secrets (see `.gitignore`).

## Setting up the machine

Start the setup on the Legion itself, in the `operator` account, from the Claude desktop app or Claude Code (PLAN.md P0.0a). A cloud session (Slack, or claude.ai on the web) can't reach the machine unless it's linked from the claude.ai composer's + menu → Devices. Even then, computer use can only click in terminals, so commands still need a local session.

### Starter prompt

Before the clone, Claude has no CLAUDE.md, so this prompt points it at GitHub:

> You're the setup operator for this machine. The plan is in the public repo https://github.com/avictorio/sha. Until the repo is cloned, read PLAN.md and CLAUDE.md from GitHub, and follow CLAUDE.md's rules. I've finished P0.0a: this is the `operator` account, with Git, Claude Code, computer use and a browser tool set up. Do P0.0b now: first confirm you're in `operator`, then apply the privacy settings. Create the deploy key and stop to show me the public key so I can add it on GitHub from my phone. Then clone the repo and run the Done-when checks. After that, P0.1.

## Repo conventions

- `main` is protected by a rule requiring a pull request. That's free because the repo is public; on a private repo, branch rules need GitHub Pro or higher (verify the current plan terms). Without the rule, the deploy key could push to `main`.
- In a new repo, push `main` first. Otherwise the first branch pushed becomes the default.
- Branches: `legion/<phase>` for the on-machine Claude, `claude/*` for cloud planning sessions, each with a PR into `main`.

## Working on this repo with Claude

- Install the Claude GitHub App on the repo before using a Claude cloud session with it (https://github.com/apps/claude, or reconnect at https://claude.ai/connect-github). Otherwise pushes fail with 403.
- Share plans and source material as files in the repo or as pasted text, not as Slack file links. Cloud sessions may not be able to open those, because of network policy or a missing connector.
