# scripts/precommit-check.ps1 -- run before every commit (CLAUDE.md, Finishing a task). Unelevated is fine.
# Checks the STAGED content, and exits 1 on any problem:
#   - forbidden files (CLAUDE.md "Never commit"): .env, auth.json, state.db, instance.yaml, backups, logs, passphrases,
#     and instance data by folder or name (vault, memories, sessions, calls, travel, receipts, brief queue);
#   - secret patterns in added lines: OpenRouter keys, Telegram bot tokens, private keys;
#   - .ps1 files that don't parse, or hold non-ASCII without a BOM (PowerShell 5.1 misreads them);
#   - a Markdown file where one long line repeats many times (a sign of a runaway edit);
#   - unusually large changes, so the diff size gets a second look (-AllowLarge to accept).
param([switch]$AllowLarge, [int]$LargeLines = 400)
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot)
$fail = 0
function Bad($msg) { Write-Host "[FAIL] $msg" -ForegroundColor Red; $script:fail++ }

$files = @(git diff --cached --name-only --diff-filter=ACMR)
if (-not $files) { Write-Host "nothing staged"; exit 0 }

foreach ($f in $files) {
  $leaf = Split-Path $f -Leaf
  if ($leaf -match '\.example$') { continue }   # templates (.env.example), placeholders only
  if ($leaf -match '^\.env|\.env$|^auth\.json$|^state\.db|^instance\.yaml$|passphrase|\.(7z|bak|log|jsonl)$') { Bad "forbidden file staged: $f" }
  # Instance data by folder or name (CLAUDE.md "Never commit"; mirrors .gitignore)
  if ($f -match '(^|/)(vault|memories|sessions|calls|backups|backup-stage|restore-stage|restore-test|logs|travel)/' -or
      $leaf -cmatch '^(receipts\.csv|brief-queue\.md|triage-state\.json|MEMORY\.md|USER\.md)$') { Bad "instance data staged: $f" }
}

$added = @(git diff --cached -U0 | Where-Object { $_ -match '^\+[^+]' })
if ($added -match 'sk-or-[A-Za-z0-9_-]{20,}|\d{6,12}:[A-Za-z0-9_-]{30,}|BEGIN [A-Z ]*PRIVATE KEY') { Bad "a secret pattern appears in the staged changes" }

foreach ($f in $files) {
  $text = (git show ":$f") -join "`n"
  if ($f -like '*.ps1') {
    $errs = $null
    [Management.Automation.Language.Parser]::ParseInput($text, [ref]$null, [ref]$errs) | Out-Null
    if ($errs) { Bad "$f doesn't parse: $($errs[0].Message) (line $($errs[0].Extent.StartLineNumber))" }
    $bytes = [IO.File]::ReadAllBytes((Resolve-Path $f))
    $bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    if (-not $bom -and ($bytes | Where-Object { $_ -gt 127 } | Select-Object -First 1)) { Bad "$f has non-ASCII characters but no BOM" }
  }
  if ($f -like '*.md') {
    $top = $text -split "`n" | Where-Object { $_.Trim().Length -ge 40 } | Group-Object | Sort-Object Count -Descending | Select-Object -First 1
    # Legitimate repeats (e.g. spike Done-when lines) stay well under 20.
    if ($top -and $top.Count -gt 20) { Bad "$f repeats one line $($top.Count) times: $($top.Name.Substring(0, [math]::Min(80, $top.Name.Length)))" }
  }
}

$stat = git diff --cached --numstat | ForEach-Object { $c = $_ -split "`t"; [pscustomobject]@{ Add = $c[0]; Del = $c[1]; File = $c[2] } }
$stat | ForEach-Object { Write-Host ("  +{0,-5} -{1,-5} {2}" -f $_.Add, $_.Del, $_.File) }
$big = $stat | Where-Object { $_.Add -match '^\d+$' -and [int]$_.Add -gt $LargeLines }
if ($big -and -not $AllowLarge) { Bad "large change ($(($big.File) -join ', ')): check the diff is what you meant, then rerun with -AllowLarge" }

if ($fail) { Write-Host "$fail problem(s); fix before committing." -ForegroundColor Red; exit 1 }
Write-Host "precommit-check: OK" -ForegroundColor Green
