# Local-model benchmark (PLAN.md P1.1)

This benchmark decides **D2**, the single local model both profiles use. It runs through Hermes itself on the Legion, with Hermes cut off from the network, so it measures what you'll actually get: the model, the 64K context and the Docker sandbox together. It ships in the package too: preflight plus this benchmark is how a buyer qualifies their own machine (PLAN.md §11).

- `fixtures/`: synthetic inputs, copied into the default profile's workspace. No real personal data; email domains are `example.com` / `.test`.
- `answer_keys/`: expected results. **Never copy these into the workspace**, because the agent would find them.
- `scores.csv`: one row per run, `model,task,run,pass,wall_clock_s,notes`.

## Setup (once per candidate)

1. **Context check (Spike S6).** For each D2 candidate, run `ollama show <tag>` and note the context length. Drop any candidate whose native context is below 65,536 (a tag listed at 40K would only reach 64K by overriding `num_ctx`, which is a quality risk). If `ollama show` doesn't show it, check the tag's page in the Ollama library.
2. **While still online:**
   - Make sure the candidates are pulled (P0.4) and the sandbox image is pre-pulled (P0.5).
   - In `hermes chat`, ask the agent to run `python3 --version` in the sandbox. B2 needs Python 3 in the container. If it's missing, note that, and score B2 as "not runnable" rather than as a model failure.
3. **Copy the fixtures** (PowerShell; repeat before *every* run, because B2 and B3 change files):
   ```powershell
   $repo = "<path to this repo>"
   Remove-Item -Recurse -Force C:\agent\workspace\bench -ErrorAction SilentlyContinue
   New-Item -ItemType Directory -Force C:\agent\workspace\bench\out | Out-Null
   Copy-Item -Recurse "$repo\bench\fixtures" C:\agent\workspace\bench\fixtures
   # B1 depends on modification times, which git does not keep:
   $d = "C:\agent\workspace\bench\fixtures\newest"
   $times = @{ "big-export.csv" = "2026-09-01 10:00"; "meeting-notes.md" = "2026-10-10 09:00";
               "zz-archive.txt" = "2026-06-30 08:00"; "todo.txt" = "2026-10-12 18:00";
               "draft-letter.txt" = "2026-10-14 07:30" }
   foreach ($k in $times.Keys) { (Get-Item (Join-Path $d $k)).LastWriteTime = [datetime]$times[$k] }
   ```
   Check once that `ls -lt /workspace/work/bench/fixtures/newest` in the sandbox shows `draft-letter.txt` first. Times should carry through the bind mount (verify). If they don't, set them inside the container with `touch -d`.
4. **Isolate Hermes from the network** (PLAN.md S14). The on-machine Claude can't run this with Wi-Fi off, because that would cut its own connection. So block only Hermes. The rule's shape, the loopback behaviour and the Hermes executable path are all (verify):
   ```powershell
   New-NetFirewallRule -DisplayName "bench-block-hermes" -Direction Outbound -Action Block -Program "<Hermes exe path>"
   hermes config set terminal.docker_network false      # sandbox gets --network=none (notes F4)
   # when done:
   Remove-NetFirewallRule -DisplayName "bench-block-hermes"; hermes config set terminal.docker_network true
   ```
   Check that `hermes chat` still answers from Ollama on `127.0.0.1`, and that asking the agent to fetch a web page fails. S14 turns this into `bench/isolate.ps1 -On / -Off`. **Fallback, if S14 finds no reliable isolation:** you turn Wi-Fi off, unplug Ethernet, and run the suite yourself at the Legion's keyboard. Telegram and Tailscale are cut off either way, so every task runs in `hermes chat` on the box.
5. **Select the candidate.** Run `hermes config set model.default <tag>`, then open `hermes chat`. In a second window, run `ollama ps`: CONTEXT should be 65536. Note the PROCESSOR split (CPU/GPU %) in `notes`.
6. **Each run:**
   - Start a fresh session (`/new`, or exit and reopen `hermes chat`) and paste the prompt exactly.
   - Time it from sending the prompt to the final answer, using a stopwatch or timestamps.
   - Don't help the agent or answer its questions; if it asks instead of acting, that run fails.
   - If a Hermes approval prompt appears, answer no. The on-machine Claude never approves.

Paths in the prompts are the sandbox view: `C:\agent\workspace` is mounted at `/workspace/work` (PLAN.md P0.6).

## Tasks

### B1: single tool call
```text
Which file in /workspace/work/bench/fixtures/newest was modified most recently? Reply with just the file name.
```
- **Pass:** `draft-letter.txt`.
- **Traps:** `zz-archive.txt` is last alphabetically and `big-export.csv` is the largest; neither is newest.

### B2: run, debug and fix a script
```text
In /workspace/work/bench/fixtures/csv-report, run python3 report.py sales.csv. Its output should match expected.txt exactly, but it doesn't. Fix the bugs in report.py. Don't edit sales.csv or expected.txt, and don't hard-code the output. Then show me the diff of your change and the new output.
```
- **Pass:** both of the following.
  1. `python3 report.py sales.csv` prints exactly the contents of `expected.txt`.
  2. The **holdout** check (you run it after the turn; it catches hard-coding):
     ```bash
     cd /workspace/work/bench/fixtures/csv-report      # or a copy of the folder on any machine with Python 3
     python3 report.py <repo>/bench/answer_keys/b2_holdout_sales.csv | diff - <repo>/bench/answer_keys/b2_holdout_expected.txt && echo PASS
     ```
- **Bugs to find:**
  - the last data row is skipped (`Rows: 14` instead of `15`)
  - the unit price is truncated to an integer
  - regions are sorted ascending instead of highest first
- In the holdout, a region (`Central`) appears only in the last row.

### B3: multi-step search and report
```text
In /workspace/work/bench/fixtures/todo-project, find every line that contains the uppercase word TODO as a whole word. Ignore FIXME, XXX and lowercase todo. Every file has a Description: comment in its first lines. Write /workspace/work/bench/out/todo_report.md with: a first line giving the total number of TODOs and the number of files that have them; then one section per file that has TODOs, in alphabetical order by path, headed with the path, the file's description and its TODO count, listing each TODO with its line number and text.
```
- **Pass:** compare with `answer_keys/b3_todo_report.json`. You need all of the following:
  - 16 TODOs in 12 files
  - the same set of files
  - the same line numbers in each file
  - each file's description present (wording may differ slightly)
- **Traps:**
  - Two TODOs sit at the end of a code line.
  - `todo_list_enabled`, `fetchTodos` and "todo widget" don't count.
  - `deploy.sh` has its description on line 2.
- Expect at least 8 tool calls, because the descriptions require opening each file. Record the count in `notes`.
- The go rule also needs B3's median time under 10 minutes.

### B4: long-document summary (no fixture)
Choose a long document of about 25–30K tokens, very roughly 100–120K characters of English prose. It can be one of yours, or a public-domain text that Claude picks. Save it as plain text at `C:\agent\workspace\bench\b4\doc.txt`. Before the first run, write down 5 factual questions about it, with answers quoted from the text, so whoever scores can check against the source. Use the same document and questions for every candidate.
```text
Read /workspace/work/bench/b4/doc.txt and summarize it in exactly 10 bullets.
```
Then, in the same session, ask your 5 questions one at a time.
- **Pass:** exactly 10 bullets, no invented facts in them, and at least 4 of the 5 answers correct.
- **Why there's no fixture:** a synthetic document doesn't test real summarization, and a personal document shouldn't be committed. A large document would also bloat the package. This task exercises a large part of the 64K window.

### B5: calendar question
```text
Today is Monday 2 November 2026 and I'm in America/Los_Angeles. Using /workspace/work/bench/fixtures/calendar.ics, what's on my calendar on Thursday?
```
- **Pass:** per `answer_keys/b5_thursday.json`:
  - It lists Recycling pickup (all day), Weekly standup 09:30–09:45, Dentist check-up 14:00–15:00, and Call with contractor 17:30–18:00.
  - It does not present the cancelled lunch, Wednesday's dinner or next week's car service as happening on Thursday.
- **Traps:**
  - The standup is a weekly recurring event.
  - The contractor call is stored in UTC, on Friday.

### B6: recovery from a bad file name
```text
List every SKU in /workspace/work/bench/fixtures/recovery/inventory_2026.csv whose qty_on_hand is below its reorder_level. Give the SKUs in sorted order and the count.
```
- That file doesn't exist. The real one is `inventory-2026.csv`. `inventory_2025.csv` is a distractor that matches the prompt's underscore but is the wrong year.
- **Pass:** per `answer_keys/b6_low_stock.json`, all of the following:
  - It finishes without asking.
  - It says it used `inventory-2026.csv`.
  - It answers A-100, A-103, B-200, B-202, C-302 (count 5).
  - Equal-to-level rows are excluded.

### B7: structured extraction from email
```text
For each .eml file in /workspace/work/bench/fixtures/emails, extract the flight number, the flight date and the booking confirmation code. Write /workspace/work/bench/out/flights.json as a JSON array of objects with the keys file, flight_number (no spaces), date (YYYY-MM-DD) and confirmation_code, sorted by file name.
```
- **Pass:** valid JSON matching `answer_keys/b7_flights.json`. Flight numbers are compared case-insensitively with spaces removed.
- **Traps:**
  - customer, invoice and order numbers
  - an old trip reference
  - an HTML part
  - a forwarded message, whose email date isn't the flight date

## Scoring

- Run every task **3 times per candidate**: 21 rows per candidate in `scores.csv`.
- Fill in `pass` as `1` or `0`, `wall_clock_s` in whole seconds, and anything notable in `notes`: tool-call count, PROCESSOR split, the way it failed.
- A task **passes** for a candidate when at least 2 of its 3 runs pass.

## Go / no-go rule (proposed defaults; adjust before your first run, not after)

A candidate is **GO** if all three hold:
1. At least **6 of 7** tasks pass.
2. **Median per-turn latency ≤ 30 s**, measured as the median `wall_clock_s` over the six B1 and B5 runs. These are single-question tasks, so this is the closest stopwatch proxy for "how long a normal reply takes". If you installed the usage-log plugin (P1.5) first, also note the median per-call `duration` from its log.
3. **B3 median under 10 minutes.**

**Pick the fastest GO candidate**: the lowest median `wall_clock_s` summed across the seven tasks. Write it into D2 and continue with P1.2.

**If no candidate is GO:**
- Record a **revised D2**: the private profile keeps the best local candidate but narrows local work to extraction and summaries, i.e. B4/B5/B7-class tasks such as inbox triage, the morning brief and itinerary extraction.
- The default profile runs **cloud-first**: `model.default` is the D9 cloud model, still under the OpenRouter key cap.
- Re-run the benchmark when a new local model you want to try appears.

## Screening a new model first: `speed-probe.ps1`

Before giving a newly released model a full run, screen it with `bench/speed-probe.ps1 -Models <tag>[,<tag>]`. It asks Ollama directly (not through Hermes) for:
- the native context length;
- the CPU/GPU split at 64K;
- generation and prompt-reading speed;
- 3 simple tool calls.

A model far slower than the current default can't meet the 30 s go rule, so it can skip the full run.

Results on the Legion (RTX 4080 Laptop GPU, 12 GB; 64 GB RAM; Ollama 0.40.8; 64K context; 2026-10-22):

| Model | Native ctx | CPU/GPU | Writing, tok/s | Prompt reading, tok/s | Tool calls | Verdict |
|---|---|---|---|---|---|---|
| `qwen3:30b-a3b-instruct-2507-q4_K_M` (MoE, ~3B active) | 262144 | 53%/47% | 27.3 | 458 | 3/3 | Current default; full run in P1.1 |
| `muse-glimmer:30b` (Meta, dense, Q4_K_M, 18 GB) | 131072 | 48%/52% | 4.7 | 131 | 3/3 | **Screened out.** About 6x slower: a 300-word reply takes about 1.5 min, so it can't meet the 30 s go rule on 12 GB of VRAM. Worth re-testing on a 24 GB+ GPU, where it fits entirely in VRAM. |

`muse-glimmer:30b` stays pulled (18 GB on D:). The owner may use it later in a hybrid setup: qwen3 by default, Glimmer for a few tasks where its quality is worth the wait. The two models don't fit in VRAM together, so switching evicts the other model (about 10 s to reload). That makes Glimmer a better fit for slow, non-interactive work, such as cron jobs or overnight runs, than for chat replies. Benchmark it on those tasks first.
