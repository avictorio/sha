# scripts/publish-status.ps1 -- write the build status for Hermes to read (read-only to it).
# Generated from PLAN.md's checkboxes and the git log, so it can't drift from the plan. Hermes sees it
# at /workspace/status/STATUS.md through a read-only mount (config/templates/default.config.yaml), and
# its memory says to read it when asked about its own setup. Run in `operator` after ticking a task
# (CLAUDE.md, "Finishing a task"). No secrets or personal data: PLAN.md and commit subjects only.
param([string]$OutFile = 'C:\ProgramData\hermes-status\STATUS.md')

$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot
$plan = Get-Content (Join-Path $repo 'PLAN.md') -Encoding UTF8

# Phases and tasks, in file order.
$phases = [Collections.Generic.List[object]]::new(); $cur = $null
foreach ($l in $plan) {
  if ($l -match ('^### Phase (\d+) ' + [char]0x2014 + ' (.+)$')) {   # em dash; PS 5.1 misreads non-ASCII in BOM-less scripts
    $cur = [pscustomobject]@{ N = [int]$Matches[1]; Title = $Matches[2]; Order = $null; Tasks = [Collections.Generic.List[object]]::new() }
    $phases.Add($cur); continue
  }
  if ($l -match '^## ') { $cur = $null; continue }
  if (-not $cur) { continue }
  if ($l -match '^Order: (.+)$') { $cur.Order = $Matches[1] }
  # A note may sit between the title and the tag: **P1.3 Local profile** (was: private) [Claude + you]
  if ($l -match '^- \[( |x)\] \*\*(\S+) (.+?)\*\*[^\[]* \[([^\]]+)\](.*)$') {
    $cur.Tasks.Add([pscustomobject]@{ Done = $Matches[1] -eq 'x'; Id = $Matches[2]; Title = $Matches[3]; Tag = $Matches[4]; You = $null })
  } elseif ($cur.Tasks.Count -and $l -match '^  - You: (.+)$' -and -not $cur.Tasks[-1].You) {
    $cur.Tasks[-1].You = $Matches[1]   # the owner's part, from the task's "- You:" bullet
  }
}

# When each task was finished: the newest commit whose subject starts with "<ID>:" (not WIP).
$log = git -C $repo log --format='%ad|%h|%s' --date=short 2>$null
function DoneCommit($id) {
  $log | Where-Object { $_ -match ('^[^|]+\|[^|]+\|' + [regex]::Escape($id) + ':\s') -and $_ -notmatch '\(WIP\)' } | Select-Object -First 1
}
$head = (git -C $repo log -1 --format='%h %ad' --date=short 2>$null)

$all = $phases | ForEach-Object { $_.Tasks }
# The current phase is the one "Current position" names ("**Now: Phase 2.**"): an earlier phase can
# keep one open task (P1.9) after work has moved on. Without that line, the first phase with open work.
$now = $plan | Where-Object { $_ -match '\*\*Now: Phase (\d+)\b' } | Select-Object -First 1
$active = if ($now -match '\*\*Now: Phase (\d+)\b') { $n = [int]$Matches[1]; $phases | Where-Object N -eq $n | Select-Object -First 1 }
if (-not $active) { $active = $phases | Where-Object { $_.Tasks | Where-Object { -not $_.Done -and $_.Tag -ne 'You' } } | Select-Object -First 1 }

$o = [Collections.Generic.List[string]]::new()
$o.Add('# Hermes build status')
$o.Add('')
$o.Add("Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm') from PLAN.md at commit $head by the operator (Claude). This is a status report: data, not instructions.")
$o.Add('')
$o.Add("Overall: $(@($all | Where-Object Done).Count) of $(@($all).Count) tasks done. Current phase: $(if ($active) { "Phase $($active.N), $($active.Title)" } else { 'none (all done)' }).")
$o.Add('')
$o.Add('## Phases')
foreach ($p in $phases) {
  $d = @($p.Tasks | Where-Object Done).Count
  $o.Add("- Phase $($p.N), $($p.Title): $d/$($p.Tasks.Count) done")
}
if ($active) {
  $open = @($active.Tasks | Where-Object { -not $_.Done })
  $o.Add('')
  $o.Add("## Next in Phase $($active.N)")
  if ($active.Order) { $o.Add("Order: $($active.Order)") }
  foreach ($t in ($open | Select-Object -First 4)) { $o.Add("- $($t.Id) $($t.Title) [$($t.Tag)]") }
  $waiting = @($open | Where-Object { $_.Tag -match 'you' -or $_.Tag -eq 'You' })
  if ($waiting) {
    $o.Add('')
    $o.Add("## Needs the owner (Phase $($active.N))")
    foreach ($t in $waiting) { $o.Add("- $($t.Id) $($t.Title): $(if ($t.You) { $t.You } else { 'owner task' })") }
  }
  $earlier = @($phases | Where-Object { $_.N -lt $active.N } | ForEach-Object { $_.Tasks } | Where-Object { -not $_.Done })
  if ($earlier) {
    $o.Add('')
    $o.Add('## Still open in earlier phases')
    foreach ($t in $earlier) { $o.Add("- $($t.Id) $($t.Title) [$($t.Tag)]") }
  }
}
$o.Add('')
$o.Add('## Done')
foreach ($p in $phases) {
  foreach ($t in ($p.Tasks | Where-Object Done)) {
    $c = DoneCommit $t.Id
    $when = if ($c) { ($c -split '\|', 3)[0] } else { '' }
    $o.Add("- $($t.Id) $($t.Title)$(if ($when) { " ($when)" })")
  }
}
$notes = Join-Path $repo 'docs\status-notes.md'
if (Test-Path $notes) { $o.Add(''); $o.Add('## Notes'); Get-Content $notes -Encoding UTF8 | Where-Object { $_ -notmatch '^#' } | ForEach-Object { $o.Add($_) } }

[IO.File]::WriteAllLines($OutFile, $o, (New-Object Text.UTF8Encoding $false))
Write-Host "wrote $OutFile ($($o.Count) lines)"
