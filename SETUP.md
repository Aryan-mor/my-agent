# my-agent: setup guide for an AI agent (Grok Bot or Cursor)

> **For you (the human):** fill in `SIGNUP_EMAIL` / `SIGNUP_PASSWORD` in `.env` if you want the agent to create the free provider accounts for you (optional), then ask **Grok Bot**, or open this folder in **Cursor** (Agent mode), and say:
>
> **"Set up my-agent for me following SETUP.md."**
>
> The agent does everything itself and only stops to ask you for captchas, 2FA / email verification codes, or a choice. About 20-40 minutes on a Windows PC.

---

## Instructions to the AI agent

You are setting up **my-agent** (this repository) for the user: Claude Code (or Cursor's Agent) plans and reviews, a cheap **OpenCode** agent implements, and a local **LiteLLM** proxy on `127.0.0.1:4000` routes OpenCode's requests through a chain of **free** providers:
`Kilo -> OpenRouter -> Gemini -> NVIDIA NIM -> (optional GLM bridge) -> (optional local Ollama model)`. Read `README.md` once for background.

### Which agent are you?

- **Grok Bot** (desktop assistant with its own browser and a shell on the user's PC): run every command on the user's Windows PC in PowerShell, and do the provider sign-ups in your browser (Step 4).
- **Cursor (Agent mode)**: run every command in Cursor's terminal tool. For the sign-ups (Step 4) use Cursor's **built-in browser tool** if it is available in this session; otherwise give the user the signup URL and key page for each provider, and ask them to paste the key into `.env` themselves (or paste it to you so you write it with `Set-EnvValue`).
- Do **not** install extra browser tooling (Playwright, browser extensions, MCP servers) on the user's PC. Other agents (e.g. Claude Code): see the optional appendix at the end.

### Rules for you

1. **In order, one step at a time.** Before each step say in one plain sentence what you do and why; after it, show the check result.
2. **Check before installing.** Run the check command first; install only what is missing.
3. **Install location is configurable.** Ask the user once which drive/folder to use (`INSTALL_ROOT`, e.g. `D:\` when C: is small). Put the repo, Python venv, Ollama models and npm caches there (see Step 2). Never install onto a drive the user excluded.
4. **Secrets.** Never print, echo, log or repeat an API key or `SIGNUP_PASSWORD`, not even partially. Verify a key only by checking its `.env` line is non-empty. Never commit `.env` (it is in `.gitignore`). Write values with the helper in Step 3.
5. **Stop and ask the user only for:** captchas, 2FA / SMS codes, email verification links or codes (unless you can read that mailbox), terms that need a personal decision (payment details: never enter any; all providers here have free tiers), or when a site blocks automated sign-up.
6. **Back up before overwriting** anything in the user's home folder (`scripts\install.ps1` does this automatically).
7. Use **PowerShell**. If scripts are blocked, run them as `powershell -NoProfile -ExecutionPolicy Bypass -File <script>`.
8. Never commit, push or delete the user's things unless they explicitly ask.

---

### Step 1 - Get the repository

Ask where to keep my-agent (default `$INSTALL_ROOT\Projects\my-agent`). It must stay there: the Claude skill points to that path.

```powershell
git clone https://github.com/Aryan-mor/my-agent.git "$INSTALL_ROOT\Projects\my-agent"   # or: gh repo clone Aryan-mor/my-agent <path>
cd "$INSTALL_ROOT\Projects\my-agent"
```

From now on **MY_AGENT_HOME** = `(Resolve-Path .).Path`.

### Step 2 - Prerequisites

| Tool | Check | Install if missing |
|---|---|---|
| PowerShell 5.1+ | `$PSVersionTable.PSVersion` | built into Windows |
| git | `git --version` | `winget install --id Git.Git -e --location "$INSTALL_ROOT\Programs\Git"` |
| Node.js LTS | `node --version; npm --version` | `winget install --id OpenJS.NodeJS.LTS -e` |
| Python 3.11+ | `py -3.11 --version` (or `python --version`) | `winget install --id Python.Python.3.12 -e --location "$INSTALL_ROOT\Python312"` |
| OpenCode >= 1.19 | `opencode --version` | `npm install -g opencode-ai` |
| Cursor and/or Claude Code (planner; at least one) | `cursor --version` / `claude --version` | https://cursor.com/downloads / https://docs.claude.com/en/docs/claude-code |
| Ollama (only if the user wants a local model, Step 5) | `ollama --version` | Step 5 |

To keep npm's global packages and caches off C:: `npm config set prefix "$INSTALL_ROOT\npm-global"` and `npm config set cache "$INSTALL_ROOT\npm-cache"`, then add `$INSTALL_ROOT\npm-global` to the user PATH. Open a new terminal after installs so PATH updates apply.

### Step 3 - Create `.env`

```powershell
if (-not (Test-Path .env)) { Copy-Item .env.example .env }
# helper: set one value without printing it
function Set-EnvValue($name, $value) {
  $l = Get-Content .env
  if ($l -match "^$name=") { $l = $l -replace "^$name=.*", "$name=$value" } else { $l += "$name=$value" }
  [IO.File]::WriteAllLines("$PWD\.env", $l, (New-Object Text.UTF8Encoding $false))
}
# LITELLM_MASTER_KEY is just a local password: generate it
Set-EnvValue LITELLM_MASTER_KEY ("sk-" + -join ((48..57) + (97..122) | Get-Random -Count 32 | ForEach-Object { [char]$_ }))
```

Ask the user: **use a local Ollama model?** (needs a decent GPU or lots of RAM; `qwen3-coder:30b` needs ~20 GB, `qwen2.5-coder:7b` ~5 GB). Set:

```powershell
Set-EnvValue MYAGENT_LOCAL on                      # or off (default)
Set-EnvValue MYAGENT_LOCAL_MODEL qwen3-coder:30b   # any Ollama tag
Set-EnvValue MYAGENT_LOCAL_URL http://127.0.0.1:11434/v1
```

### Step 4 - Free API keys (sign up with SIGNUP_EMAIL / SIGNUP_PASSWORD)

Read the credentials from `.env` without printing them:

```powershell
$su = @{}; Get-Content .env | Where-Object { $_ -match '^(SIGNUP_EMAIL|SIGNUP_PASSWORD)=(.*)$' } | ForEach-Object { $su[$Matches[1]] = $Matches[2] }
```

If both are set, use them to create accounts on each site below in your browser (Grok Bot: your own browser; Cursor: its built-in browser tool if available, otherwise hand each site to the user and ask for the key). If the user prefers, use **"Continue with Google"** instead (the user may need to log in once). If they are empty, ask the user whether to sign up for them (they type credentials themselves) or to paste keys.
For each provider: sign up / log in -> confirm the email if asked (ask the user for the code/link) -> open the key page -> create a key -> copy it straight into `.env` with `Set-EnvValue` (never into the chat). If a site refuses or needs a phone number, tell the user and move on; every provider is optional except that **at least one of Kilo / OpenRouter** is needed.

| # | Provider (role in chain) | Sign up | Key page / what to click | `.env` variable |
|---|---|---|---|---|
| 1 | **Kilo** (primary `sonnet`) | https://app.kilo.ai (Sign up / Continue with Google) | profile / **API keys** -> create / copy key | `KILO_API_KEY` |
| 2 | **OpenRouter** (primary `opus` + `openrouter/free`) | https://openrouter.ai/sign-up | https://openrouter.ai/settings/keys -> **Create Key** (starts with `sk-or-`) | `OPENROUTER_API_KEY` |
| 3 | **Google AI Studio / Gemini** (`gemini-flash` fallback) | https://aistudio.google.com (Google account) | https://aistudio.google.com/app/apikey -> **Create API key** | `OPENAI_API_KEY` (yes, the Gemini key goes here) |
| 4 | **NVIDIA NIM** (`nvidia-nemotron` / `nvidia-glm`) | https://build.nvidia.com (Login -> create NVIDIA account) | https://build.nvidia.com/settings/api-keys -> **Generate API Key** (starts with `nvapi-`) | `NVIDIA_API_KEY` |
| 5 | GLM bridge (advanced, optional) | only if the user already runs one on :3001 | - | `GLM_BRIDGE_DIR`, `GLM_API_KEY` |

Verify without values:

```powershell
foreach ($n in "LITELLM_MASTER_KEY","KILO_API_KEY","OPENROUTER_API_KEY","OPENAI_API_KEY","NVIDIA_API_KEY","MYAGENT_LOCAL","MYAGENT_LOCAL_MODEL") {
  "{0,-20} {1}" -f $n, $(if (Select-String -Path .env -Pattern "^$n=.+" -Quiet) { "set" } else { "empty" }) }
```

Offer to clear `SIGNUP_PASSWORD` from `.env` afterwards.

### Step 5 - Local model with Ollama (only if `MYAGENT_LOCAL=on`)

```powershell
ollama --version
# missing -> install (the installer accepts a target dir):
#   winget install --id Ollama.Ollama -e --location "$INSTALL_ROOT\AI\Ollama"
# keep the (large) models on the chosen drive, then restart Ollama:
[Environment]::SetEnvironmentVariable("OLLAMA_MODELS", "$INSTALL_ROOT\AI\ollama-models", "User")
ollama pull qwen3-coder:30b                  # = MYAGENT_LOCAL_MODEL
ollama list
Invoke-RestMethod http://127.0.0.1:11434/v1/models | Select-Object -Expand data | Select-Object id
```

The local model is the **last** fallback (only used when every free provider fails) and is also selectable directly as `auto/ollama-local` in OpenCode. Toggle any time: `scripts\my-agent-local.ps1 on|off|status` (writes `.env` and restarts LiteLLM). Change the model: `scripts\my-agent-local.ps1 on -Model qwen2.5-coder:7b`.

### Step 6 - LiteLLM proxy

`start-litellm.ps1` renders `litellm\config.yaml` into `litellm\config.generated.yaml` from `.env`: with `MYAGENT_LOCAL=on` it fills in `MYAGENT_LOCAL_MODEL` / `MYAGENT_LOCAL_URL`; with `off` it removes the `ollama-local` model and its fallback entries.

```powershell
cd litellm
py -3.11 -m venv .venv                      # or: python -m venv .venv   (lives inside the repo, i.e. on the chosen drive)
.venv\Scripts\python -m pip install --upgrade pip
.venv\Scripts\pip install -r requirements.txt
.\start-litellm.ps1                         # hidden, port 4000 (LITELLM_PORT to change; -Foreground to debug)
Start-Sleep 20
.venv\Scripts\python test_proxy.py basic    # expect a tool call and a model name
cd ..
```

If LiteLLM is already installed elsewhere, set `LITELLM_EXE=<path>\litellm.exe` in `.env` instead of creating a venv.

### Step 7 - Verify routing and the local toggle

```powershell
$k = ((Select-String .env -Pattern '^LITELLM_MASTER_KEY=').Line -split '=',2)[1]; $h = @{ Authorization = "Bearer $k" }
(Invoke-RestMethod http://127.0.0.1:4000/v1/models -Headers $h).data.id      # ollama-local listed only when MYAGENT_LOCAL=on
$b = @{ model = "sonnet"; max_tokens = 400; messages = @(@{ role = "user"; content = "Reply with just: OK" }) } | ConvertTo-Json -Depth 4
(Invoke-RestMethod http://127.0.0.1:4000/v1/chat/completions -Method Post -Headers $h -ContentType application/json -Body $b).choices[0].message.content
# local model directly (if on; first call loads the model, can take a minute):
$b = $b.Replace('"sonnet"', '"ollama-local"'); (Invoke-RestMethod http://127.0.0.1:4000/v1/chat/completions -Method Post -Headers $h -ContentType application/json -Body $b -TimeoutSec 300).choices[0].message.content
Remove-Variable k
```

Toggle check: `scripts\my-agent-local.ps1 off` -> the models list no longer has `ollama-local`; `scripts\my-agent-local.ps1 on` -> it is back.
### Step 8 - Install the OpenCode global agents, DCP config and plugins

Explain: this copies the two agent prompts (`orchestrator`, `implementer`) and the context-pruning config into the user's OpenCode config folder. Existing files are backed up as `*.bak-<timestamp>`; an existing `opencode.jsonc` / `package.json` is never overwritten.

First tell the user what exists already:

```powershell
Get-ChildItem "$env:USERPROFILE\.config\opencode" -Recurse -ErrorAction SilentlyContinue | Select-Object FullName
```

Then run (`-NoClaude -NoCursor` limits it to OpenCode; the planner integrations follow in Step 9):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\install.ps1 -NoClaude -NoCursor
```

If the user wants rtk (Step 10), re-run later with `-WithRtk -NoClaude -NoCursor`.

The DCP plugin (`@tarquinen/opencode-dcp`) is listed in the repo's `opencode.json` and is downloaded by OpenCode automatically on first start.

### Step 9 - Install `/my-agent` for Claude Code, Cursor, or both

**Ask the user first:** "Do you want to use my-agent from **Claude Code** (CLI or the Claude Code extension), from **Cursor's own Agent chat**, or **both**?" Explain: either one acts as the planner and reviewer; my-agent does the coding in both cases. In Cursor the user can pick any model for planning/reviewing.

Explain: this adds a `/my-agent` command. The files are written as UTF-8 **without BOM** (a BOM breaks the Claude skill header), and their `<MY_AGENT_HOME>` placeholder is replaced with the real absolute path of the repo. Existing files are backed up. Run the matching command:

```powershell
# Claude Code only  -> ~/.claude/skills/my-agent/SKILL.md
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\install.ps1 -SkipOpenCode -NoCursor
# Cursor only       -> ~/.cursor/commands/my-agent.md
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\install.ps1 -SkipOpenCode -NoClaude
# both
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\install.ps1 -SkipOpenCode
```

Verify each installed file (no BOM, real path filled in):

```powershell
foreach ($s in "$env:USERPROFILE\.claude\skills\my-agent\SKILL.md", "$env:USERPROFILE\.cursor\commands\my-agent.md") {
  if (-not (Test-Path $s)) { "$s : not installed"; continue }
  $b = [System.IO.File]::ReadAllBytes($s)[0..2]
  "$s : " + $(if ($b[0] -eq 0xEF) { "BOM PRESENT - fix it" } else { "no BOM - ok" })
  if (Select-String -Path $s -Pattern "<MY_AGENT_HOME>" -SimpleMatch -Quiet) { "  placeholder NOT replaced - re-run install.ps1" }
  Select-String -Path $s -Pattern "delegate.ps1" | Select-Object -First 1     # must show the real repo path
}
Test-Path (Join-Path (Get-Location) "scripts\delegate.ps1")
```

Check that the command appears:
- **Claude Code:** restart Claude Code (or the extension), type `/my` at the start of a message; `my-agent` should be listed.
- **Cursor:** in Cursor's Agent chat, type `/`; `my-agent` should be in the list. If not, reload the window (Ctrl+Shift+P -> `Developer: Reload Window`) or restart Cursor. If both are installed, Cursor may show `my-agent` twice (Cursor also loads `~/.claude/skills`); both work.

If the user moves the repo later, re-run this step.

### Step 10 - Optional: graphify and rtk

**graphify** ([Graphify-Labs/graphify](https://github.com/Graphify-Labs/graphify)) builds a code knowledge graph (`graphify-out/graph.json`) so the agent finds code without grepping. Strongly recommended for real projects.

```powershell
winget install --id astral-sh.uv -e          # if uv is missing (or: pip install pipx, then pipx install graphifyy)
uv tool install graphifyy                    # note the double "y"; the command is still "graphify"
uv tool update-shell                         # then open a new terminal
graphify --help
```

Then, **per project** (in the project's root folder): build the graph once, e.g. type `/graphify .` in Claude Code after `graphify install`, or use the CLI build command from the graphify docs. Afterwards the orchestrator keeps it fresh with `graphify update .`. Tell the user to add `graphify-out/` to the project's `.gitignore` if they don't want to commit it.

**rtk** ([rtk-ai/rtk](https://github.com/rtk-ai/rtk)) compresses command output to save tokens. Install it following its README (it is a single binary; make sure `rtk` is on PATH: `rtk --version`), then:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\install.ps1 -WithRtk -NoClaude -NoCursor
```

Both are optional; everything works without them.

### Step 11 - Smoke test

Explain: we run my-agent once on a tiny sample task in a throw-away folder to prove the whole chain works.

```powershell
$repo = (Resolve-Path .).Path
$t = Join-Path $env:TEMP "my-agent-smoke"
New-Item -ItemType Directory -Force "$t\hello" | Out-Null
Set-Content "$t\hello\greet.py" "# placeholder: greet() goes here" -Encoding ascii
Set-Content "$t\hello\__init__.py" "" -Encoding ascii
git -C $t init -q; git -C $t add -A; git -C $t -c user.email=smoke@example.com -c user.name=smoke commit -qm init
Copy-Item "$repo\examples\sample-plan.md" "$t\sample-plan.md"

$d = "$repo\scripts\delegate.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File $d start -Plan "$t\sample-plan.md" -Dir $t
powershell -NoProfile -ExecutionPolicy Bypass -File $d wait -Dir $t      # repeat while it prints STATE: RUNNING
powershell -NoProfile -ExecutionPolicy Bypass -File $d status -Dir $t
cd $t; python -m unittest discover -s hello -t . -v; cd $repo
```

Expected: `STATE: FINISHED`, the progress checklist mostly `[x]`, `hello/greet.py` changed and `hello/test_greet.py` created, tests pass.

Also prove the wrong-project guard: run `start -Plan "$t\sample-plan.md" -Dir $repo`; it must print `WRONG PROJECT` (exit code 2) and start nothing.

If it fails: `status` shows the errors; also check `$t\.opencode\delegate\run.err.log` and `litellm\litellm.err.log`. Clean up afterwards with the user's OK: `Remove-Item -Recurse -Force $t`.

### Step 12 - Tell the user how to use it

Explain in plain words:
- **Claude Code:** open any project and type, **at the very start of a message**: `/my-agent <what you want built>` (or `/my-agent <path to a plan .md>`).
- **Cursor:** in the Agent chat, type `/`, pick `my-agent`, and add the task. Any model works as the planner/reviewer; that's the user's choice.
- The planner writes a plan, my-agent implements it, the planner checks it with the project's tests and loops up to 3 times, then reports back. In Cursor, the agent waits in short `wait -Minutes 4` steps; that is normal.
- Nothing is committed or pushed; review with `git diff` and commit yourself.
- Tiny fixes (about 3 lines) the planner does directly.
- For big projects, build the graphify graph once in the project root for much faster runs.
- If something goes wrong: see "Tips and troubleshooting" in `README.md`.

---

## Verification checklist

- [ ] `git`, `node`, `npm`, Python 3.11+, `opencode` (>= 1.19) available, plus Claude Code and/or Cursor (as the user chose)
- [ ] `.env` exists, `LITELLM_MASTER_KEY` and at least one of `KILO_API_KEY` / `OPENROUTER_API_KEY` are set (checked without printing values); `.env` is not tracked by git (`git status` does not list it)
- [ ] `litellm\.venv` exists and `test_proxy.py basic` returned a tool call
- [ ] `~/.config/opencode/agents/orchestrator.md`, `implementer.md` and `~/.config/opencode/dcp.jsonc` installed (old versions backed up as `*.bak-*`)
- [ ] Claude Code chosen: `~/.claude/skills/my-agent/SKILL.md` installed, **no BOM**, contains the real path to `scripts\delegate.ps1` (no `<MY_AGENT_HOME>` left); after a restart `/my-agent` is listed
- [ ] Cursor chosen: `~/.cursor/commands/my-agent.md` installed, **no BOM**, real path filled in; typing `/` in Cursor's Agent chat lists `my-agent` (after `Developer: Reload Window` if needed)
- [ ] (optional) `graphify --help` works; graph built in the user's main project
- [ ] (optional) `rtk --version` works and `~/.config/opencode/plugins/rtk.ts` installed
- [ ] Smoke test: `STATE: FINISHED`, tests in the scratch folder pass
- [ ] Wrong-project guard: printed `WRONG PROJECT` for the wrong `-Dir`
- [ ] No API key was printed in the chat or terminal output

---

## Appendix (optional) - Claude Code as the setup agent

Only if the user explicitly wants Claude Code to run this guide **and** agrees to install browser tooling. Otherwise Claude Code simply asks the user for each key. Do this before Step 1:

Install the official [Playwright MCP](https://github.com/microsoft/playwright-mcp) server (user scope, so it works in every project). Point the npm cache at the chosen drive first so nothing large lands on C: (skip if C: is fine):

```powershell
npm config set cache "$INSTALL_ROOT\npm-cache"          # e.g. D:\npm-cache ; npx uses the same cache
claude mcp add --scope user playwright -- npx @playwright/mcp@latest
# if Windows cannot start npx directly, use:  claude mcp add --scope user playwright -- cmd /c npx -y @playwright/mcp@latest
claude mcp list                                          # expect: playwright ... connected
```

Then **restart Claude Code** so the `browser_*` tools appear. The browser profile is stored under `%LOCALAPPDATA%\ms-playwright`; to keep it on another drive add `--user-data-dir "$INSTALL_ROOT\playwright-profile"` after `@playwright/mcp@latest`.
Alternative: the **Claude in Chrome** extension (lets Claude Code drive the user's own Chrome). Either is fine; without any browser, fall back to asking the user for each key.
