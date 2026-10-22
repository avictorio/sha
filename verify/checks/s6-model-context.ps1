# verify/checks/s6-model-context.ps1 -- PLAN.md S6: each D2 candidate's native context is >= 64K
# and matches what versions.lock records. Run in `operator`, unelevated. Re-runnable.
$ErrorActionPreference = 'Continue'
$results = [ordered]@{}
function Record($name, $ok, $detail) {
  $results[$name] = $ok
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("[{0}] {1}  {2}" -f ($(if ($ok) {'PASS'} else {'FAIL'})), $name, $detail) -ForegroundColor $c
}
$repo = Split-Path (Split-Path $PSScriptRoot)
$lock = ConvertFrom-StringData ((Get-Content (Join-Path $repo 'versions.lock') |
  Where-Object { $_ -notmatch '^\s*#' }) -join "`n")
$pinned = @{}
foreach ($e in ($lock.model_native_context -split ',')) { $t, $n = $e -split '@'; $pinned[$t] = [int]$n }

foreach ($tag in ($lock.model_candidates -split ',')) {
  $show = (& 'D:\ollama\bin\ollama.exe' show $tag 2>&1) -join "`n"
  $ctx = if ($show -match '(?m)context length\s+(\d+)') { [int]$Matches[1] } else { 0 }
  Record "ctx:$tag" ($ctx -ge 65536 -and $ctx -eq $pinned[$tag]) "native=$ctx pinned=$($pinned[$tag])"
}
"`n"; $results.GetEnumerator() | ForEach-Object { "{0,-50} {1}" -f $_.Key, $(if ($_.Value) {'PASS'} else {'FAIL'}) }
