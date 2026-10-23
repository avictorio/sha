# verify/checks/p1-7-backup.ps1 -- PLAN.md P1.7 Done when: an encrypted .7z exists in D:\backups; it won't list
# or extract without the passphrase; with it, it shows config.yaml, state.db and the local profile's files.
# Run in the `operator` account, ELEVATED (reads the passphrase file). The inner hermes zip is extracted to
# operator's temp folder, listed by name only, and deleted. Prints PASS/FAIL per check; never prints the passphrase.
$ErrorActionPreference = 'Continue'
$results = [ordered]@{}
function Record($name, $ok, $detail) {
  $results[$name] = $ok
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("[{0}] {1}  {2}" -f ($(if ($ok) {'PASS'} else {'FAIL'})), $name, $detail) -ForegroundColor $c
}
$sevenZip = 'C:\Program Files\7-Zip\7z.exe'
$a = Get-ChildItem 'D:\backups\hermes-*.7z' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1
Record 'archive-exists' ([bool]$a) $(if ($a) { "{0} ({1:N1} MB, {2})" -f $a.Name, ($a.Length / 1MB), $a.LastWriteTime } else { 'none in D:\backups' })
if (-not $a) { return }

$wrong = & $sevenZip l -p'not-the-passphrase' $a.FullName 2>&1; $rcWrong = $LASTEXITCODE
Record 'no-list-without-passphrase' ($rcWrong -ne 0 -and -not ($wrong -match 'hermes-.*\.zip')) "7z exit $rcWrong"
$t = Join-Path $env:TEMP ("p17-" + [guid]::NewGuid().ToString('N'))
& $sevenZip x -p'not-the-passphrase' "-o$t" $a.FullName 2>&1 | Out-Null; $rcX = $LASTEXITCODE
Record 'no-extract-without-passphrase' ($rcX -ne 0 -and -not (Get-ChildItem $t -Recurse -File -ErrorAction SilentlyContinue | Where-Object Length -gt 0)) "7z exit $rcX"
Remove-Item -Recurse -Force $t -ErrorAction SilentlyContinue

$pw = (Get-Content 'C:\agent\bin\backup-passphrase.txt' -Raw -Encoding UTF8).Trim()
try {
  $list = & $sevenZip l -slt "-p$pw" $a.FullName 2>&1
  $paths = @($list | Where-Object { $_ -match '^Path = ' } | ForEach-Object { $_ -replace '^Path = ', '' } | Select-Object -Skip 1)
  $inner = $paths | Where-Object { $_ -match '^hermes-.*\.zip$' } | Select-Object -First 1
  Record 'lists-with-passphrase' ($LASTEXITCODE -eq 0 -and $inner) "$($paths.Count) entries; inner: $inner"
  foreach ($d in 'workspace', 'local', 'shared') { Record "has-agent-$d" ([bool]($paths | Where-Object { $_ -eq $d -or $_ -like "$d\*" })) '' }
  New-Item -ItemType Directory $t | Out-Null
  try {
    & $sevenZip e "-p$pw" "-o$t" $a.FullName $inner -y 2>&1 | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $z = [IO.Compression.ZipFile]::OpenRead((Join-Path $t $inner))
    try { $names = @($z.Entries | ForEach-Object { $_.FullName -replace '\\', '/' }) } finally { $z.Dispose() }
    foreach ($n in 'config.yaml', 'state.db', 'profiles/local/config.yaml', 'profiles/local/state.db', 'memories/USER.md') {
      Record "inner-has-$n" ($names -contains $n) ''
    }
  } finally { Remove-Item -Recurse -Force $t -ErrorAction SilentlyContinue }
} finally { $pw = $null }
Record 'temp-cleaned' (-not (Test-Path $t)) ''
$task = Get-ScheduledTask -TaskName 'Agent_Backup' -ErrorAction SilentlyContinue
Record 'task-daily-0330' ($task -and ($task.Triggers[0].StartBoundary -match 'T03:30')) "$($task.Triggers[0].StartBoundary) as $($task.Principal.UserId)"

"`n"; $results.GetEnumerator() | ForEach-Object { "{0,-34} {1}" -f $_.Key, $(if ($_.Value) {'PASS'} else {'FAIL'}) }
