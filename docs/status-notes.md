# Status notes: appended to STATUS.md by scripts/publish-status.ps1. Facts about the build only; no secrets or personal data.
- Local model: qwen3:30b-a3b-instruct-2507-q4_K_M through Ollama on the RTX 4080 Laptop GPU (12 GB), 64K context. P1.1's benchmark makes the final choice (D2).
- Benchmark candidates (P1.1): qwen3:30b-a3b-instruct-2507, gpt-oss:20b, qwen3-coder:30b. qwen3:32b was dropped in S6 (native context 40K).
- muse-glimmer:30b is installed but not in use. Screened at 4.7 tok/s vs qwen's 27.3. Kept for a possible hybrid later: qwen by default, Glimmer for a few slow tasks.
- Terminal sandbox: Docker, nousresearch/hermes-sandbox:desktop, 8 CPUs and 16 GB.
- Telegram: one bot (default profile), allow-listed to the owner. The private profile's bot comes in P1.3.
- Not set up yet: cloud models (P1.4), email (Phase 2), calendar (P2.5), browser (Phase 3), phone (Phase 4).
