# bench/speed-probe.ps1 -- a quick viability check for a local model, before the full benchmark.
# Not the P1.1 benchmark (bench/README.md): that runs agent tasks through Hermes. This only asks
# Ollama directly: native context, CPU/GPU split at the context we use, generation speed, and
# whether one simple tool call comes back well-formed. Run in `operator`, unelevated.
# Loading a model evicts whatever Ollama had loaded, so the Telegram bot is slow for a moment after.
param([Parameter(Mandatory)][string[]]$Models, [int]$Ctx = 65536, [int]$Runs = 3)

$ErrorActionPreference = 'Stop'
$ollama = 'D:\ollama\bin\ollama.exe'
$api = 'http://127.0.0.1:11434/api'
function Post($path, $body) {
  Invoke-RestMethod -Method Post -Uri "$api/$path" -ContentType 'application/json' -TimeoutSec 1800 `
    -Body ([Text.Encoding]::UTF8.GetBytes(($body | ConvertTo-Json -Depth 10)))
}
$tools = @(@{ type = 'function'; function = @{
  name = 'get_weather'; description = 'Current weather for a city'
  parameters = @{ type = 'object'; properties = @{ city = @{ type = 'string' } }; required = @('city') } } })

$rows = foreach ($m in $Models) {
  Write-Host "`n== $m" -ForegroundColor Cyan
  $show = (& $ollama show $m 2>&1) -join "`n"
  $native = if ($show -match '(?m)context length\s+(\d+)') { [int]$Matches[1] } else { $null }

  $load = Post 'generate' @{ model = $m; prompt = 'Reply with OK.'; stream = $false; keep_alive = '10m'; options = @{ num_ctx = $Ctx; num_predict = 8 } }
  $ps = (& $ollama ps 2>&1) | Where-Object { $_ -match [regex]::Escape($m) }
  $split = if ($ps -match '(\d+%/\d+% CPU/GPU|\d+% GPU|\d+% CPU)') { $Matches[1] } else { "$ps" }
  Write-Host "  native ctx=$native  load=$([int]($load.load_duration / 1e9)) s  processor=$split"

  $tps = @(); $pps = @()
  for ($i = 1; $i -le $Runs; $i++) {
    $g = Post 'generate' @{ model = $m; stream = $false; keep_alive = '10m'
      prompt = 'In about 300 words, explain how a heat pump moves heat. Plain prose, no lists.'
      options = @{ num_ctx = $Ctx; num_predict = 400; temperature = 0; seed = $i } }
    $tps += $g.eval_count / ($g.eval_duration / 1e9)
    if ($g.prompt_eval_duration) { $pps += $g.prompt_eval_count / ($g.prompt_eval_duration / 1e9) }
    Write-Host ("  run {0}: {1:N1} tok/s ({2} tokens)" -f $i, $tps[-1], $g.eval_count)
  }

  $ok = 0
  for ($i = 1; $i -le $Runs; $i++) {
    $c = Post 'chat' @{ model = $m; stream = $false; keep_alive = '10m'; tools = $tools
      messages = @(@{ role = 'user'; content = 'What is the weather in Lisbon right now? Use the tool.' })
      options = @{ num_ctx = $Ctx; temperature = 0; seed = $i } }
    $call = $c.message.tool_calls | Select-Object -First 1
    if ($call.function.name -eq 'get_weather' -and "$($call.function.arguments.city)" -match 'Lisbon') { $ok++ }
  }
  Write-Host "  tool calls well-formed: $ok/$Runs"

  Post 'generate' @{ model = $m; prompt = ''; keep_alive = 0 } | Out-Null   # unload
  $med = ($tps | Sort-Object)[[int][Math]::Floor(($tps.Count - 1) / 2)]
  [pscustomobject]@{ model = $m; native_ctx = $native; processor = $split
    gen_tok_s = [Math]::Round($med, 1); prompt_tok_s = [Math]::Round((($pps | Measure-Object -Average).Average), 0)
    tool_calls = "$ok/$Runs" }
}
"`n"; $rows | Format-Table -AutoSize
