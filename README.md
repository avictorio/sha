# Hermes hybrid agent

This repo holds the build plan, and the start of a distributable package, for a personal agent built on Hermes Agent. The agent runs on a Windows 11 laptop with a local Ollama model, and uses the cloud only by explicit escalation or on errors, both logged.

- [PLAN.md](PLAN.md): the actionable runbook, with decisions, phased tasks, Done-when checks, spikes and autonomy tags. Start here.
- [CLAUDE.md](CLAUDE.md): rules for the Claude agent that sets the machine up.
- [docs/verification-notes.md](docs/verification-notes.md): the source checks behind every command and config key.
- [docs/original/](docs/original/hermes_hybrid_agent_plan.html): the original Slack-shared plan, unchanged.
- [templates/](templates/): the approval-policy and usage-log plugins, the call brief, the inbox-triage prompt and the email allowlist.
- [bench/](bench/README.md): the local-model benchmark, with tasks, synthetic fixtures, answer keys and a scoring sheet.

Templates contain placeholders only (`<your name>`, `<your number>`). Never commit instance data or secrets (see `.gitignore`).
