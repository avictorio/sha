# bench/runner.ps1 -- the part of the P1.1 benchmark that runs AS hermes (via scripts/invoke-as-hermes.ps1).
# Started by bench/run-bench.ps1 from a staging folder hermes can read but not change. Writes everything to
# -Results (C:\agent\bench-results\..., not mounted into the sandbox, so the agent never sees past runs).
#   -Mode Prepare: online pre-checks (chat flags, sandbox python3, mtimes through the bind mount, and
#                  whether `hermes config set model.default` changes the model Ollama actually loads).
#   -Mode Run:     every candidate x task x run. Before each run: fixtures reset, memory restored.
# Prompts are copied verbatim from bench/README.md. ASCII only (PS 5.1 reads BOM-less scripts as ANSI).
param(
  [Parameter(Mandatory)][ValidateSet('Prepare', 'Run')][string]$Mode,
  [Parameter(Mandatory)][string]$Stage,
  [Parameter(Mandatory)][string]$Results,
  [string[]]$Candidates = @(),
  [string[]]$Tasks = @('B1', 'B2', 'B3', 'B4', 'B5', 'B6', 'B7'),
  [int]$Runs = 3,
  [string]$ResumeFlag = '',            # e.g. '--resume'; B4's follow-up questions need it
  [int]$ChatTimeoutSec = 1200
)
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$env:NO_COLOR = '1'; $env:PYTHONIOENCODING = 'utf-8'
$h      = Join-Path $env:LOCALAPPDATA 'hermes\bin\hermes.exe'
$home_  = Join-Path $env:LOCALAPPDATA 'hermes'
$docker = "$env:ProgramFiles\Docker\Docker\resources\bin\docker.exe"
$ws     = 'C:\agent\workspace\bench'
New-Item -ItemType Directory -Force $Results | Out-Null
$progress = Join-Path $Results 'progress.log'
function Log($m) { $line = "$(Get-Date -Format s) $m"; Add-Content -Path $progress -Value $line -Encoding UTF8; $line }

$prompts = @{
  B1 = 'Which file in /workspace/work/bench/fixtures/newest was modified most recently? Reply with just the file name.'
  B2 = 'In /workspace/work/bench/fixtures/csv-report, run python3 report.py sales.csv. Its output should match expected.txt exactly, but it doesn''t. Fix the bugs in report.py. Don''t edit sales.csv or expected.txt, and don''t hard-code the output. Then show me the diff of your change and the new output.'
  B3 = 'In /workspace/work/bench/fixtures/todo-project, find every line that contains the uppercase word TODO as a whole word. Ignore FIXME, XXX and lowercase todo. Every file has a Description: comment in its first lines. Write /workspace/work/bench/out/todo_report.md with: a first line giving the total number of TODOs and the number of files that have them; then one section per file that has TODOs, in alphabetical order by path, headed with the path, the file''s description and its TODO count, listing each TODO with its line number and text.'
  B4 = 'Read /workspace/work/bench/b4/doc.txt and summarize it in exactly 10 bullets.'
  B5 = 'Today is Monday 2 November 2026 and I''m in America/Los_Angeles. Using /workspace/work/bench/fixtures/calendar.ics, what''s on my calendar on Thursday?'
  B6 = 'List every SKU in /workspace/work/bench/fixtures/recovery/inventory_2026.csv whose qty_on_hand is below its reorder_level. Give the SKUs in sorted order and the count.'
  B7 = 'For each .eml file in /workspace/work/bench/fixtures/emails, extract the flight number, the flight date and the booking confirmation code. Write /workspace/work/bench/out/flights.json as a JSON array of objects with the keys file, flight_number (no spaces), date (YYYY-MM-DD) and confirmation_code, sorted by file name.'
}
$b4Questions = @(
  'What was Gregor Samsa''s job?',
  'What did Gregor''s father throw at him, and where did he get them?',
  'Where had Gregor secretly planned to send his sister the next year, and why?',
  'How many gentlemen rented a room in the Samsas'' flat, and what did they all have?',
  'At the end of the story, how did the family travel out of town, and where to?'
)

function Reset-Fixtures {
  Remove-Item -Recurse -Force $ws -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Force "$ws\out", "$ws\b4" | Out-Null
  Copy-Item -Recurse "$Stage\fixtures" "$ws\fixtures"
  Copy-Item "$Stage\b4\doc.txt" "$ws\b4\doc.txt"
  $d = "$ws\fixtures\newest"
  $times = @{ 'big-export.csv' = '2026-09-01 10:00'; 'meeting-notes.md' = '2026-10-10 09:00'
              'zz-archive.txt' = '2026-06-30 08:00'; 'todo.txt' = '2026-10-12 18:00'
              'draft-letter.txt' = '2026-10-14 07:30' }
  foreach ($k in $times.Keys) { (Get-Item (Join-Path $d $k)).LastWriteTime = [datetime]$times[$k] }
}

# One `hermes chat` turn with a hard timeout. Prompts contain no double quotes (PS 5.1 mangles them).
function Invoke-Chat([string]$prompt, [string[]]$extra = @()) {
  $out = [IO.Path]::GetTempFileName(); $err = [IO.Path]::GetTempFileName()
  $argline = (@('chat') + $extra + @('-Q', '-q', ('"' + $prompt + '"'))) -join ' '
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $p = Start-Process -FilePath $h -ArgumentList $argline -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
  $timedOut = -not $p.WaitForExit($ChatTimeoutSec * 1000)
  if ($timedOut) { & taskkill.exe /T /F /PID $p.Id 2>&1 | Out-Null }
  $sw.Stop()
  $text = ((Get-Content $out -Encoding UTF8 -ErrorAction SilentlyContinue) + (Get-Content $err -Encoding UTF8 -ErrorAction SilentlyContinue)) -join "`n"
  Remove-Item $out, $err -ErrorAction SilentlyContinue
  $sid = if ($text -match 'session_id:\s*(\S+)') { $Matches[1] } else { '' }
  [pscustomobject]@{ Text = $text; Seconds = [int][Math]::Round($sw.Elapsed.TotalSeconds); TimedOut = $timedOut; Session = $sid }
}
function Loaded {
  try {
    $ps = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/ps' -TimeoutSec 10
    ($ps.models | ForEach-Object { '{0} vram={1:P0} ctx={2}' -f $_.name, ($_.size_vram / [double]$_.size), $_.context_length }) -join '; '
  } catch { "api/ps failed: $($_.Exception.Message)" }
}
function Sandbox { & $docker ps -q --filter name=^hermes- 2>$null | Select-Object -First 1 }
function SetModel($tag) { & $h config set model.default $tag 2>&1 | Out-Null; ((& $h config get model.default 2>&1) -join '').Trim() }

if ($Mode -eq 'Prepare') {
  Log "PREPARE start"
  (& $h chat --help 2>&1) | Set-Content (Join-Path $Results 'chat-help.txt') -Encoding UTF8
  Reset-Fixtures
  $orig = ((& $h config get model.default 2>&1) -join '').Trim()
  Log "model.default=$orig"
  $c = Invoke-Chat 'Reply with exactly: PONG'
  Log "pong secs=$($c.Seconds) ok=$($c.Text -match 'PONG') session=$($c.Session) loaded=[$(Loaded)]"
  $ctr = Sandbox
  Log "sandbox=$ctr python3=[$((& $docker exec $ctr python3 --version 2>&1) -join ' ')]"
  Log "newest mtimes:`n$((& $docker exec $ctr ls -lt --time-style=+%F_%R /workspace/work/bench/fixtures/newest 2>&1) -join "`n")"
  Log "b4 doc: $((& $docker exec $ctr wc -c -w /workspace/work/bench/b4/doc.txt 2>&1) -join ' ')"
  foreach ($tag in $Candidates) {
    $set = SetModel $tag
    $c = Invoke-Chat 'Reply with exactly: PONG'
    Log "switch to $tag (config=$set): pong ok=$($c.Text -match 'PONG') secs=$($c.Seconds) loaded=[$(Loaded)]"
  }
  $set = SetModel $orig
  Log "restored model.default=$set"
  $gl = Get-Content (Join-Path $home_ 'logs\gateway.log') -Tail 60 -Encoding UTF8
  $gl | Where-Object { $_ -match [regex]::Escape($c.Session) -or $_ -match '(?i)tool' } | Select-Object -Last 25 |
    Set-Content (Join-Path $Results 'gateway-sample.txt') -Encoding UTF8
  Log "PREPARE done"
  return
}

# --- Run -------------------------------------------------------------------------------
$orig = ((& $h config get model.default 2>&1) -join '').Trim()
$memDir = Join-Path $home_ 'memories'; $memSnap = Join-Path $Results '_memories-before'
Copy-Item -Recurse $memDir $memSnap -Force
$skillsDir = Join-Path $home_ 'skills'
$skillsBefore = @(Get-ChildItem $skillsDir -Recurse -Directory -ErrorAction SilentlyContinue | ForEach-Object FullName)
Log "RUN start; model.default=$orig; candidates=$($Candidates -join ','); tasks=$($Tasks -join ','); runs=$Runs"
if ($ResumeFlag) {   # B4's follow-ups depend on resuming by the printed session id; prove it once
  $t = Invoke-Chat 'Remember this code word for the rest of this conversation: OKAPI. Reply with exactly: NOTED'
  $u = Invoke-Chat 'What was the code word I gave you? Reply with just the word.' @($ResumeFlag, $t.Session)
  Log "resume self-test: ok=$($u.Text -match 'OKAPI') session=$($t.Session)"
  Copy-Item "$memSnap\*" $memDir -Force -Recurse
}
try {
  foreach ($tag in $Candidates) {
    $set = SetModel $tag
    Log "== $tag (config=$set)"
    $safe = $tag -replace '[:/\\]', '_'
    foreach ($task in $Tasks) {
      for ($run = 1; $run -le $Runs; $run++) {
        $dir = Join-Path $Results "$safe\$task-r$run"; New-Item -ItemType Directory -Force $dir | Out-Null
        Reset-Fixtures
        Copy-Item "$memSnap\*" $memDir -Force -Recurse
        $c = Invoke-Chat $prompts[$task]
        $secs = $c.Seconds; $all = "### PROMPT`n$($prompts[$task])`n### ANSWER`n$($c.Text)"
        if ($task -eq 'B4' -and $c.Session -and $ResumeFlag) {
          foreach ($q in $b4Questions) {
            $f = Invoke-Chat $q @($ResumeFlag, $c.Session)
            $secs += $f.Seconds; $all += "`n### Q: $q`n$($f.Text)"
          }
        }
        $all | Set-Content (Join-Path $dir 'transcript.txt') -Encoding UTF8
        $ctr = Sandbox
        switch ($task) {
          'B2' {
            Copy-Item "$ws\fixtures\csv-report\report.py" $dir -ErrorAction SilentlyContinue
            $main = & $docker exec -w /workspace/work/bench/fixtures/csv-report $ctr sh -c 'python3 report.py sales.csv | diff - expected.txt >/dev/null && echo MAIN_PASS || echo MAIN_FAIL' 2>&1
            # The turn is over, so the holdout can go where the sandbox sees it (docker cp can't write into its tmpfs /tmp)
            Copy-Item -Recurse "$Stage\holdout" "$ws\_holdout"
            $hold = & $docker exec -w /workspace/work/bench/fixtures/csv-report $ctr sh -c 'python3 report.py ../../_holdout/b2_holdout_sales.csv | diff - ../../_holdout/b2_holdout_expected.txt >/dev/null && echo HOLDOUT_PASS || echo HOLDOUT_FAIL' 2>&1
            Remove-Item -Recurse -Force "$ws\_holdout"
            "$main`n$hold" | Set-Content (Join-Path $dir 'b2-check.txt')
          }
          'B3' { Copy-Item "$ws\out\todo_report.md" $dir -ErrorAction SilentlyContinue }
          'B7' { Copy-Item "$ws\out\flights.json" $dir -ErrorAction SilentlyContinue }
        }
        $toolLines = @(Get-Content (Join-Path $home_ 'logs\gateway.log') -Tail 3000 -Encoding UTF8 |
          Where-Object { $c.Session -and $_ -match [regex]::Escape($c.Session) })
        $toolLines | Set-Content (Join-Path $dir 'gateway.txt') -Encoding UTF8
        $newSkills = @(Get-ChildItem $skillsDir -Recurse -Directory -ErrorAction SilentlyContinue | ForEach-Object FullName | Where-Object { $skillsBefore -notcontains $_ })
        foreach ($s in ($newSkills | Sort-Object Length -Descending)) { Remove-Item -Recurse -Force $s -ErrorAction SilentlyContinue }
        $meta = [ordered]@{ model = $tag; task = $task; run = $run; wall_clock_s = $secs; timed_out = $c.TimedOut
                            session = $c.Session; loaded = (Loaded); new_skills_removed = $newSkills }
        $meta | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $dir 'meta.json') -Encoding UTF8
        Log "$tag $task r$run secs=$secs timedOut=$($c.TimedOut) loaded=[$($meta.loaded)]"
      }
    }
  }
} finally {
  Copy-Item "$memSnap\*" $memDir -Force -Recurse
  $set = SetModel $orig
  Log "RUN done; model.default restored to $set"
}
