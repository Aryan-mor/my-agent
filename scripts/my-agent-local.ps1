# my-agent-local.ps1 on|off|status : switch the local Ollama model (last fallback of the LiteLLM chain) on or off.
# Writes MYAGENT_LOCAL=on|off into the repo-root .env and restarts LiteLLM so the change takes effect.
#   my-agent-local.ps1 status          -> shows on/off, model and URL, and whether Ollama answers
#   my-agent-local.ps1 on [-Model qwen3-coder:30b]   (optionally also sets MYAGENT_LOCAL_MODEL)
#   my-agent-local.ps1 off
param([ValidateSet("on","off","status")][string]$Mode = "status", [string]$Model, [switch]$NoRestart)
$root = if ($env:MY_AGENT_HOME) { $env:MY_AGENT_HOME } else { Split-Path -Parent $PSScriptRoot }
$envFile = Join-Path $root ".env"
if (-not (Test-Path $envFile)) { throw ".env not found at $envFile. Copy .env.example to .env first." }
$lines = @(Get-Content $envFile)
function Get-Val($name, $def) { $l = $lines | Where-Object { $_ -match "^$name=" } | Select-Object -First 1; $v = if ($l) { ($l -replace "^$name=", '').Trim().Trim('"').Trim("'") } else { "" }; if ($v) { $v } else { $def } }
function Set-Val($name, $val) {
    if ($script:lines -match "^$name=") { $script:lines = @($script:lines | ForEach-Object { if ($_ -match "^$name=") { "$name=$val" } else { $_ } }) }
    else { $script:lines += "$name=$val" }
}
$cur = Get-Val "MYAGENT_LOCAL" "off"
$m = Get-Val "MYAGENT_LOCAL_MODEL" "qwen3-coder:30b"
$u = Get-Val "MYAGENT_LOCAL_URL" "http://127.0.0.1:11434/v1"
if ($Mode -eq "status") {
    $tags = ($u.TrimEnd('/') -replace '/v1$', '') + "/api/tags"
    $alive = try { Invoke-WebRequest -UseBasicParsing $tags -TimeoutSec 3 | Out-Null; "reachable" } catch { "NOT reachable" }
    Write-Output "Local model: $cur  (model $m at $u, Ollama $alive)"; return
}
Set-Val "MYAGENT_LOCAL" $Mode
if ($Model) { Set-Val "MYAGENT_LOCAL_MODEL" $Model }
[IO.File]::WriteAllLines($envFile, $lines, (New-Object Text.UTF8Encoding $false))
if ($NoRestart) { Write-Output "Local model: $Mode (saved; LiteLLM not restarted)"; return }
$port = if ($env:LITELLM_PORT) { $env:LITELLM_PORT } else { "4000" }
Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'litellm' -and $_.CommandLine -match "--port\s+$port\b" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 2
$litellmDir = if ($env:LITELLM_DIR) { $env:LITELLM_DIR } else { Join-Path $root "litellm" }
$env:MYAGENT_LOCAL = $Mode
& (Join-Path $litellmDir "start-litellm.ps1")
Write-Output "Local model: $Mode (LiteLLM on port $port restarted)"
