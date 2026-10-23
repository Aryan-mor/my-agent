# my-agent: launch OpenCode in the current folder with this repo's config (opencode.json + .env).
# Starts the LiteLLM proxy (and, if GLM_BRIDGE_DIR is set, an optional local GLM bridge) when not running.
# Usage: agent.ps1 [any opencode arguments], e.g.  agent.ps1 run --agent orchestrator "do X"
$ErrorActionPreference = "Stop"
# Repo root: MY_AGENT_HOME if set, otherwise the folder above this script.
$root = if ($env:MY_AGENT_HOME) { $env:MY_AGENT_HOME } else { Split-Path -Parent $PSScriptRoot }
$envFile = Join-Path $root ".env"
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith("#") -and $line.Contains("=")) {
            $idx = $line.IndexOf("=")
            $name = $line.Substring(0, $idx).Trim()
            $value = $line.Substring($idx + 1).Trim().Trim("'").Trim('"')
            if ($value) { Set-Item -Path "Env:$name" -Value $value }  # empty values in .env are ignored
        }
    }
}
# Optional local GLM bridge (OpenAI-compatible server on localhost:3001, started via start.bat in GLM_BRIDGE_DIR).
# Skipped entirely when GLM_BRIDGE_DIR is not set.
$glmDir = $env:GLM_BRIDGE_DIR
if ($glmDir -and (Test-Path $glmDir)) {
    $glmEnv = Join-Path $glmDir ".env"
    if (Test-Path $glmEnv) {
        $tokLine = Get-Content $glmEnv | Where-Object { $_ -match '^AUTH_TOKEN=' } | Select-Object -First 1
        if ($tokLine) { $env:GLM_API_KEY = $tokLine.Substring(11).Trim() }
    }
    function Test-Glm { try { Invoke-WebRequest -UseBasicParsing "http://localhost:3001/health" -TimeoutSec 2 | Out-Null; $true } catch { $false } }
    if (-not (Test-Glm)) {
        Write-Host "Starting GLM bridge (start.bat in $glmDir)..."
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c", "start.bat" -WorkingDirectory $glmDir -WindowStyle Minimized
        for ($i = 0; $i -lt 20 -and -not (Test-Glm); $i++) { Start-Sleep -Seconds 1 }
        if (-not (Test-Glm)) { Write-Warning "GLM bridge did not start on port 3001. Check the start.bat window." }
    }
}
# LiteLLM failover proxy (127.0.0.1:4000): free chain Kilo -> OpenRouter -> Gemini -> NVIDIA -> GLM -> local Ollama (if MYAGENT_LOCAL=on)
$litellmDir = if ($env:LITELLM_DIR) { $env:LITELLM_DIR } else { Join-Path $root "litellm" }
$litellmStart = Join-Path $litellmDir "start-litellm.ps1"
function Test-Litellm { try { Invoke-WebRequest -UseBasicParsing "http://127.0.0.1:4000/health/liveliness" -TimeoutSec 2 | Out-Null; $true } catch { $false } }
if ((Test-Path $litellmStart) -and -not (Test-Litellm)) {
    Write-Host "Starting LiteLLM proxy (start-litellm.ps1)..."
    & $litellmStart
    for ($i = 0; $i -lt 60 -and -not (Test-Litellm); $i++) { Start-Sleep -Seconds 1 }
    if (-not (Test-Litellm)) { Write-Warning "LiteLLM proxy did not start on port 4000. See $(Join-Path $litellmDir 'litellm.err.log') (auto/* models will fail; direct kilo/* and openrouter/* providers still work)." }
}
$opencode = Join-Path $env:APPDATA "npm\opencode.cmd"
if (-not (Test-Path $opencode)) {
    $cmd = Get-Command opencode -ErrorAction SilentlyContinue
    if ($cmd) { $opencode = $cmd.Source }
    else { Write-Error "OpenCode missing. Run: npm install -g --allow-scripts=opencode-ai opencode-ai" }
}
$env:OPENCODE_CONFIG = Join-Path $root "opencode.json"
& $opencode @args
