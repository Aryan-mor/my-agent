# Start LiteLLM proxy (127.0.0.1:4000, or LITELLM_PORT) hidden, with keys from the repo-root .env (+ optional GLM bridge token).
# Usage: .\start-litellm.ps1            (background, hidden; logs in litellm.log / litellm.err.log)
#        .\start-litellm.ps1 -Foreground (run in this console for debugging)
# Expects a virtualenv in .venv next to this script:  py -3.11 -m venv .venv; .venv\Scripts\pip install -r requirements.txt
param([switch]$Foreground)
$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
# Repo root: MY_AGENT_HOME if set, otherwise the folder above this script.
$root = if ($env:MY_AGENT_HOME) { $env:MY_AGENT_HOME } else { Split-Path -Parent $here }
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
# Optional: take the GLM bridge token from GLM_BRIDGE_DIR\.env (AUTH_TOKEN=...). Skipped if GLM_BRIDGE_DIR is not set.
if ($env:GLM_BRIDGE_DIR) {
    $glmEnv = Join-Path $env:GLM_BRIDGE_DIR ".env"
    if (Test-Path $glmEnv) {
        $tokLine = Get-Content $glmEnv | Where-Object { $_ -match '^AUTH_TOKEN=' } | Select-Object -First 1
        if ($tokLine) { $env:GLM_API_KEY = $tokLine.Substring(11).Trim() }
    }
}
if (-not $env:GLM_API_KEY) { $env:GLM_API_KEY = "none" }
$env:PYTHONIOENCODING = "utf-8"
$env:PYTHONUTF8 = "1"
$env:LITELLM_LOG = "ERROR"
$env:LITELLM_TELEMETRY = "False"
$env:NO_DOCS = "True"
$exe = if ($env:LITELLM_EXE) { $env:LITELLM_EXE } else { Join-Path $here ".venv\Scripts\litellm.exe" }  # LITELLM_EXE: reuse an existing LiteLLM install
if (-not (Test-Path $exe)) { throw "LiteLLM not installed: $exe not found. Create the venv first (see SETUP.md), or set LITELLM_EXE in .env." }
# Render config.yaml -> config.generated.yaml with the local Ollama model from .env:
#   MYAGENT_LOCAL=on|off (default off), MYAGENT_LOCAL_MODEL (default qwen3-coder:30b), MYAGENT_LOCAL_URL (default http://127.0.0.1:11434/v1)
$local = if ($env:MYAGENT_LOCAL) { $env:MYAGENT_LOCAL.ToLower() } else { "off" }
$localModel = if ($env:MYAGENT_LOCAL_MODEL) { $env:MYAGENT_LOCAL_MODEL } else { "qwen3-coder:30b" }
$localUrl = if ($env:MYAGENT_LOCAL_URL) { $env:MYAGENT_LOCAL_URL } else { "http://127.0.0.1:11434/v1" }
$cfgText = Get-Content (Join-Path $here "config.yaml") -Raw
if ($local -eq "on") {
    $cfgText = $cfgText.Replace("__MYAGENT_LOCAL_MODEL__", $localModel).Replace("__MYAGENT_LOCAL_URL__", $localUrl)
} else {
    $cfgText = [regex]::Replace($cfgText, '(?s)[ \t]*# >>> ollama-local.*?# <<< ollama-local[^\n]*\n', '')
    $cfgText = $cfgText.Replace(', "ollama-local"', '')
}
$cfgPath = Join-Path $here "config.generated.yaml"
[IO.File]::WriteAllText($cfgPath, $cfgText, (New-Object Text.UTF8Encoding $false))
# LITELLM_PORT (default 4000). opencode.json expects 4000; change it there too if you move the port.
$port = if ($env:LITELLM_PORT) { $env:LITELLM_PORT } else { "4000" }
$litArgs = @("--config", "`"$cfgPath`"", "--host", "127.0.0.1", "--port", $port, "--num_workers", "1")
if ($Foreground) { & $exe @litArgs; return }
$log = Join-Path $here "litellm.log"
$err = Join-Path $here "litellm.err.log"
Start-Process -FilePath $exe -ArgumentList $litArgs -WorkingDirectory $here -WindowStyle Hidden -RedirectStandardOutput $log -RedirectStandardError $err | Out-Null
