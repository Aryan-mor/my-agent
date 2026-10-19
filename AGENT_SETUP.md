# my-agent: guided setup for your AI coding agent

> **For you (the human):** open your AI coding agent (Claude Code, Cursor, Windsurf, ...), paste or attach this file, and say:
>
> **"Set up my-agent for me following AGENT_SETUP.md."**
>
> The agent will walk you through everything one step at a time. You will need about 20-30 minutes, a Windows PC, and a browser to create one or more API keys.

---

## Instructions to the AI agent

You are setting up **my-agent** (repository: this file's repo) for the user. my-agent lets Claude Code plan and review while a cheap OpenCode agent does the implementation through a local LiteLLM proxy. Read `README.md` once for background.

### Rules for you

1. **One step at a time.** Do the steps below in order. Before each step, tell the user in one or two plain sentences what you are about to do and why. After each step, confirm it worked (show the check result) before moving on.
2. **Plain words.** Assume the user is not an expert. Avoid jargon or explain it in a few words.
3. **Check before installing.** For each prerequisite, run the check command first. Only install what is missing, using the exact commands given, and tell the user before you install anything.
4. **Secrets.** For every API key:
   - Tell the user exactly which website to open and what to click to create the key (instructions below).
   - Then offer **two options** and let the user choose:
     - **Option A:** the user pastes the key into the chat and you write it into `.env` yourself.
     - **Option B:** the user opens `.env` (e.g. `notepad .env`) and pastes it after the `=` themselves, then tells you "done".
   - **Never print, echo, log or repeat a key back**, not even partially. To verify, only check that the line is non-empty (e.g. `(Select-String '^RADOX_API_KEY=.+' .env) -ne $null`).
   - Never commit `.env`. It is already in `.gitignore`.
5. **Back up before overwriting** any file in the user's home folder (`~/.config/opencode`, `~/.claude`). `scripts\install.ps1` does this automatically.
6. Use **PowerShell** for all commands. If a command fails, show the relevant error lines, explain them simply, and fix the cause before continuing.
7. Never commit, push or delete anything of the user's unless they explicitly ask.

---

### Step 1 - Get the repository

Ask the user where they want to keep my-agent (default: `$env:USERPROFILE\my-agent`). It must stay there, because the Claude skill will point to that path.

```powershell
git --version                 # if missing, see Step 2 first
git clone https://github.com/Aryan-mor/my-agent.git "$env:USERPROFILE\my-agent"
cd "$env:USERPROFILE\my-agent"
```

If the user already has the folder (e.g. unzipped), just `cd` into it. From now on, **MY_AGENT_HOME** means the absolute path of this folder: `(Resolve-Path .).Path`.

### Step 2 - Check and install prerequisites

Run the checks; install only what is missing (winget ships with Windows 10/11):

| Tool | Check | Install if missing |
|---|---|---|
| PowerShell 5.1+ | `$PSVersionTable.PSVersion` | built into Windows |
| git | `git --version` | `winget install --id Git.Git -e` |
| Node.js LTS (includes npm) | `node --version; npm --version` | `winget install --id OpenJS.NodeJS.LTS -e` |
| Python 3.11+ | `py -3.11 --version` (or `python --version`) | `winget install --id Python.Python.3.11 -e` (or 3.12 / 3.13) |
| OpenCode >= 1.19 | `opencode --version` | `npm install -g --allow-scripts=opencode-ai opencode-ai` (if your npm rejects `--allow-scripts`, use `npm install -g opencode-ai`) |
| Claude Code | `claude --version`, or the Claude Code extension in Cursor / VS Code | see https://docs.claude.com/en/docs/claude-code (the user needs a Claude subscription or API access) |

After installing, the user may need to **open a new terminal** so PATH updates take effect. If `opencode --version` is lower than 1.19, run `npm install -g opencode-ai@latest`.

If scripts are blocked ("running scripts is disabled on this system"), always invoke them as `powershell -NoProfile -ExecutionPolicy Bypass -File <script>`, or, with the user's consent: `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`.

### Step 3 - Create `.env`

```powershell
Copy-Item .env.example .env
```

Explain: `.env` holds the user's private keys. It stays on their PC and is ignored by git. Each line in `.env.example` has a comment saying what it is and whether it is required.

### Step 4 - Get the keys

Go through them one by one. After each key, use the two-option rule from "Rules for you".

**4a. `LITELLM_MASTER_KEY` (required, no website).** This is just a password for the local proxy. Offer to generate one, and write it into `.env` directly (it is safe for you to generate it; still do not print it):

```powershell
$k = "sk-" + -join ((48..57) + (97..122) | Get-Random -Count 32 | ForEach-Object { [char]$_ })
(Get-Content .env) -replace '^LITELLM_MASTER_KEY=.*', "LITELLM_MASTER_KEY=$k" | Set-Content .env -Encoding ascii
Remove-Variable k
```

**4b. `RADOX_API_KEY` (required: the main models).**
1. Open https://radoxai.com and sign up / log in.
2. Go to **Dashboard -> API Keys** and click **Create Key** (keep the default scopes, including `models:read`).
3. Copy the key immediately: it starts with `cc_` and is shown only once.
4. Option A or B -> `RADOX_API_KEY=` in `.env`.
5. RadoxAI is a paid service with cheap plans; the user needs credit or a plan for requests to work.

**4c. `NVIDIA_API_KEY` (optional, free: fallback models).** Ask whether the user wants free fallbacks for when RadoxAI is rate-limited.
1. Open https://build.nvidia.com/settings/api-keys and sign in (or create a free NVIDIA account).
2. Click **Generate API Key**, then **Generate Key**, and copy it (starts with `nvapi-`).
3. Option A or B -> `NVIDIA_API_KEY=`.

**4d. `OPENAI_API_KEY` = Google Gemini key (optional, free tier: fallback model).** In this setup the Gemini fallback reads its key from `OPENAI_API_KEY`.
1. Open https://aistudio.google.com/app/apikey and sign in with a Google account.
2. Click **Create API key** (pick or create a Google Cloud project if asked) and copy it.
3. Option A or B -> `OPENAI_API_KEY=`.
4. Optional, for `scripts\chat.py` / `scripts\list_models.py` only: set `OPENAI_BASE_URL=https://generativelanguage.googleapis.com/v1beta/openai` and `OPENAI_MODEL=` to a Gemini model id from `python scripts\list_models.py`.

**4e. `GLM_API_KEY` / `GLM_BRIDGE_DIR` (optional, advanced).** Only if the user already runs a local OpenAI-compatible GLM bridge on port 3001. Otherwise leave both empty and move on; the `glm` fallback is then skipped.

**Verify (without showing values):**

```powershell
foreach ($n in "LITELLM_MASTER_KEY","RADOX_API_KEY","NVIDIA_API_KEY","OPENAI_API_KEY") {
  "{0,-20} {1}" -f $n, $(if (Select-String -Path .env -Pattern "^$n=.+" -Quiet) { "set" } else { "empty" })
}
```

### Step 5 - LiteLLM proxy

Explain: LiteLLM is a small local server (on `127.0.0.1:4000`) that sends my-agent's requests to the cheapest working model and switches to a fallback instantly on errors or rate limits.

```powershell
cd litellm
py -3.11 -m venv .venv                      # or: python -m venv .venv
.venv\Scripts\python -m pip install --upgrade pip
.venv\Scripts\pip install -r requirements.txt
.\start-litellm.ps1 -Foreground             # first run in the foreground to see errors; stop with Ctrl+C once it says it is running
.\start-litellm.ps1                         # then start it hidden in the background
Start-Sleep 15
.venv\Scripts\python test_proxy.py basic    # expect: tool='get_weather' and a model name
.venv\Scripts\python test_proxy.py fb       # mocked 429: expect a fallback model to answer
cd ..
```

If the test fails: read `litellm\litellm.err.log`, check that port 4000 is free (`Get-NetTCPConnection -LocalPort 4000`), and that `RADOX_API_KEY` / `LITELLM_MASTER_KEY` are set. (`scripts\agent.ps1` starts the proxy automatically later, so this manual start is only needed once.)

### Step 6 - Install the OpenCode global agents, DCP config and plugins

Explain: this copies the two agent prompts (`orchestrator`, `implementer`) and the context-pruning config into the user's OpenCode config folder. Existing files are backed up as `*.bak-<timestamp>`; an existing `opencode.jsonc` / `package.json` is never overwritten.

First tell the user what exists already:

```powershell
Get-ChildItem "$env:USERPROFILE\.config\opencode" -Recurse -ErrorAction SilentlyContinue | Select-Object FullName
```

Then run (this also installs the Claude skill, see Step 7; to do only this step add `-SkipSkill`):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\install.ps1 -SkipSkill
```

If the user wants rtk (Step 8), re-run later with `-WithRtk -SkipSkill`.

The DCP plugin (`@tarquinen/opencode-dcp`) is listed in the repo's `opencode.json` and is downloaded by OpenCode automatically on first start.

### Step 7 - Install the Claude Code skill

Explain: this adds the `/my-agent` command to Claude Code. The file must be UTF-8 **without BOM** (a BOM breaks the skill header), and its `<MY_AGENT_HOME>` placeholder must be replaced with the real absolute path of the repo. `install.ps1` does both:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\install.ps1 -SkipOpenCode
```

Verify:

```powershell
$s = "$env:USERPROFILE\.claude\skills\my-agent\SKILL.md"
$b = [System.IO.File]::ReadAllBytes($s)[0..2]; if ($b[0] -eq 0xEF) { "BOM PRESENT - fix it" } else { "no BOM - ok" }
Select-String -Path $s -Pattern "delegate.ps1" | Select-Object -First 1   # must show the real path, no <MY_AGENT_HOME>
Test-Path (Join-Path (Get-Location) "scripts\delegate.ps1")
```

If the user moves the repo later, re-run this step. Then ask the user to **restart Claude Code / Cursor**.

### Step 8 - Optional: graphify and rtk

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
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\install.ps1 -WithRtk -SkipSkill
```

Both are optional; everything works without them.

### Step 9 - Smoke test

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

### Step 10 - Tell the user how to use it

Explain in plain words:
- Open any project in Claude Code / Cursor and type, **at the very start of a message**: `/my-agent <what you want built>` (or `/my-agent <path to a plan .md>`).
- Claude writes a plan, my-agent implements it, Claude checks it with the project's tests and loops up to 3 times, then reports back.
- Nothing is committed or pushed; review with `git diff` and commit yourself.
- Tiny fixes (about 3 lines) Claude does directly.
- For big projects, build the graphify graph once in the project root for much faster runs.
- If something goes wrong: see "Tips and troubleshooting" in `README.md`.

---

## Verification checklist

- [ ] `git`, `node`, `npm`, Python 3.11+, `opencode` (>= 1.19) and Claude Code all available
- [ ] `.env` exists, `LITELLM_MASTER_KEY` and `RADOX_API_KEY` are set (checked without printing values); `.env` is not tracked by git (`git status` does not list it)
- [ ] `litellm\.venv` exists and `test_proxy.py basic` returned a tool call
- [ ] `~/.config/opencode/agents/orchestrator.md`, `implementer.md` and `~/.config/opencode/dcp.jsonc` installed (old versions backed up as `*.bak-*`)
- [ ] `~/.claude/skills/my-agent/SKILL.md` installed, **no BOM**, contains the real path to `scripts\delegate.ps1` (no `<MY_AGENT_HOME>` left)
- [ ] Claude Code / Cursor restarted and `/my-agent` appears in the slash-command list
- [ ] (optional) `graphify --help` works; graph built in the user's main project
- [ ] (optional) `rtk --version` works and `~/.config/opencode/plugins/rtk.ts` installed
- [ ] Smoke test: `STATE: FINISHED`, tests in the scratch folder pass
- [ ] Wrong-project guard: printed `WRONG PROJECT` for the wrong `-Dir`
- [ ] No API key was printed in the chat or terminal output
