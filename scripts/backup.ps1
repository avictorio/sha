# scripts/backup.ps1 -- PLAN.md P1.7: nightly encrypted backup. Installed to C:\agent\bin\backup.ps1 by
# installer/steps/09-backup.ps1 and run AS hermes by the Agent_Backup task (daily 03:30).
#   1. `hermes backup` (covers every profile, S4) into C:\agent\backup-stage\<ts>\ on the system drive;
#   2. 7-Zip packs that zip plus C:\agent\workspace, C:\agent\local and C:\agent\shared into
#      D:\backups\hermes-<ts>.7z, AES-256 with encrypted file names (-mhe=on); -ssw reads files other
#      processes hold open (the usage logs);
#   3. deletes the stage, and .7z files older than 14 days.
# The passphrase file is readable by hermes and admins only. Writes C:\agent\shared\logs\backup.log
# (no secrets). Exit code 0 only when the archive was written.
$ErrorActionPreference = 'Stop'
$ts = Get-Date -Format yyyyMMdd-HHmm
$stage = "C:\agent\backup-stage\$ts"
$dest = "D:\backups\hermes-$ts.7z"
$log = 'C:\agent\shared\logs\backup.log'
$sevenZip = 'C:\Program Files\7-Zip\7z.exe'
$hermes = Join-Path $env:LOCALAPPDATA 'hermes\bin\hermes.exe'
function Log($msg) { Add-Content -Path $log -Value "$(Get-Date -Format s) $msg" -Encoding UTF8 }

try {
  New-Item -ItemType Directory -Force $stage | Out-Null
  Log "start $ts"
  & $hermes backup -o "$stage\hermes-$ts.zip" -k 0 2>&1 | Select-Object -Last 3 | ForEach-Object { Log "  hermes: $_" }
  if ($LASTEXITCODE -ne 0) { throw "hermes backup incomplete (exit $LASTEXITCODE)" }

  $pw = (Get-Content 'C:\agent\bin\backup-passphrase.txt' -Raw -Encoding UTF8).Trim()
  if (-not $pw) { throw "empty passphrase file" }
  $sources = @("$stage\hermes-$ts.zip") + @('C:\agent\workspace', 'C:\agent\local', 'C:\agent\shared' | Where-Object { Test-Path $_ })
  & $sevenZip a -t7z -mhe=on -ssw -bso0 -bsp0 "-p$pw" $dest @sources
  $rc = $LASTEXITCODE; $pw = $null
  # 7-Zip: 0 ok, 1 warning (e.g. a file changed while read), 2+ error
  if ($rc -ge 2 -or -not (Test-Path $dest)) { throw "7-Zip failed (exit $rc)" }
  Log ("wrote {0} ({1:N1} MB, 7z exit {2})" -f $dest, ((Get-Item $dest).Length / 1MB), $rc)

  Get-ChildItem 'D:\backups\hermes-*.7z' | Where-Object LastWriteTime -lt (Get-Date).AddDays(-14) |
    ForEach-Object { Remove-Item $_.FullName -Force; Log "pruned $($_.Name)" }
  Log "done"
  exit 0
} catch {
  Log "FAILED: $($_.Exception.Message)"
  exit 1
} finally {
  Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
}
