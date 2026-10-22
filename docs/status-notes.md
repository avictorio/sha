# Status notes: appended to STATUS.md by scripts/publish-status.ps1. Facts about the build only; no secrets or personal data.
- Local model: qwen3-coder:30b through Ollama on the RTX 4080 Laptop GPU (12 GB), 64K context. Chosen by the owner for the proof of concept (D2): the best benchmark score among the fast models. To revisit with better hardware.
- Benchmark (P1.1, done): no local model met the bar of 6 of 7 tasks. Tasks passed: qwen3-instruct 2, gpt-oss 3, qwen3-coder 4, muse-glimmer 5 (but 2–3 minutes per reply). All four struggled with the calendar question.
- muse-glimmer:30b is installed but not in use. It is the most capable model tested but too slow on this laptop; a candidate for faster hardware or slow background jobs.
- Terminal sandbox: Docker, nousresearch/hermes-sandbox:desktop, 8 CPUs and 16 GB.
- Usage log (P1.5): every model call in the default profile is logged on the laptop (model, local or cloud, tokens, time); the private profile's log comes with P1.3.
- Telegram: one bot (default profile), allow-listed to the owner. The private profile's bot comes in P1.3.
- Not set up yet: cloud models (P1.4), email (Phase 2), calendar (P2.5), browser (Phase 3), phone (Phase 4).
