# verify/checks/p1-3-ollama-stop-test.ps1 -- PLAN.md P1.3 Done when: with Ollama stopped, the private bot
# replies with an error instead of an answer (no cloud fallback). Run ELEVATED, in a visible window.
# Stops the Ollama service, waits for the owner to test in Telegram and press Enter, then starts it again.
# Ollama always restarts: after Enter, after 10 minutes, or on any error.
param([string]$LogPath)
$ErrorActionPreference = 'Stop'
if ($LogPath) { Start-Transcript -Path $LogPath -Force | Out-Null }
$p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw "Run this elevated (Run as administrator)." }
$usage = 'C:\agent\shared\logs\usage-private.jsonl'
$before = if (Test-Path $usage) { @(Get-Content $usage).Count } else { 0 }
# The private bot's Telegram calls so far (P1.3/P1.5): platform, model, local; no message content.
$tg = @(Get-Content $usage -ErrorAction SilentlyContinue | Where-Object { $_ -match '"platform": "telegram"' })
$last = $tg | Select-Object -Last 1
$ok = $tg.Count -ge 1 -and $last -match '"local": true' -and $last -match '"profile": "private"'
Write-Host ("[{0}] telegram-call-logged-local  {1} telegram line(s); last: {2}" -f $(if ($ok) {'PASS'} else {'FAIL'}), $tg.Count,
  (([regex]::Matches("$last", '"(ts|profile|platform|model|local)": [^,}]+') | ForEach-Object Value) -join ', ')) -ForegroundColor $(if ($ok) {'Green'} else {'Red'})
try {
  Stop-Service Ollama
  Write-Host "Ollama STOPPED at $(Get-Date -Format HH:mm:ss)." -ForegroundColor Yellow
  Write-Host "Now send the private bot a question in Telegram. It should reply with an error, not an answer."
  Write-Host "Then press Enter here to restart Ollama (it restarts by itself after 10 minutes)."
  $deadline = (Get-Date).AddMinutes(10)
  while ((Get-Date) -lt $deadline) {
    if ([Console]::KeyAvailable -and [Console]::ReadKey($true).Key -eq 'Enter') { break }
    Start-Sleep -Milliseconds 300
  }
} finally {
  Start-Service Ollama
  Write-Host "Ollama started again: $((Get-Service Ollama).Status)" -ForegroundColor Green
}
# A cloud fallback would have logged a non-local line while Ollama was down.
$new = if (Test-Path $usage) { @(Get-Content $usage | Select-Object -Skip $before) } else { @() }
$cloud = @($new | Where-Object { $_ -match '"local": false' })
Write-Host ("[{0}] no-cloud-call-while-stopped  {1} new line(s), {2} non-local" -f $(if ($cloud.Count -eq 0) {'PASS'} else {'FAIL'}), $new.Count, $cloud.Count) -ForegroundColor $(if ($cloud.Count -eq 0) {'Green'} else {'Red'})
Write-Host "Did the bot reply with an error (not an answer)? Tell Claude."
if ($LogPath) { Stop-Transcript | Out-Null }
Read-Host "Press Enter to close" | Out-Null
