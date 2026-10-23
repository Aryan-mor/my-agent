# delegate.ps1 - run my-agent (OpenCode orchestrator via the LiteLLM free chain) headless on a plan file and report compactly.
# Used by Claude Code's /delegate command so Claude only plans + reviews, my-agent does the work.
#   delegate.ps1 start -Plan <plan.md> [-Dir <project>] [-Resume] [-TimeoutMin 90]
#   delegate.ps1 wait  [-Dir <project>] [-Minutes 9]     (blocks up to N minutes, then prints a short report)
#   delegate.ps1 status [-Dir <project>]
#   delegate.ps1 stop  [-Dir <project>]
#   add -Engine agy [-Model claude-sonnet-5-5-medium] to run Antigravity CLI (Google AI Pro quota) instead of OpenCode. Models: agy models
#   -Engine auto (default, or MYAGENT_ENGINE in env): picks a tier (plan "Tier: hard|medium|easy" line or heuristics) and uses Antigravity if installed and its quota allows, otherwise the free chain. Without agy it is always opencode.
param(
    [Parameter(Position = 0)][ValidateSet("start", "wait", "status", "stop")][string]$Action = "status",
    [string]$Plan,
    [string]$Dir = (Get-Location).Path,
    [switch]$Resume,
    [switch]$Force,
    [int]$Minutes = 9,
    [int]$TimeoutMin = 90,
    [ValidateSet("auto", "opencode", "agy")][string]$Engine = $(if ($env:MYAGENT_ENGINE) { $env:MYAGENT_ENGINE } else { "auto" }),
    [string]$Model = "claude-sonnet-5-5-medium",
    [ValidateSet("auto", "hard", "medium", "easy")][string]$Tier = "auto",
    [switch]$FellBack
)
$ErrorActionPreference = "Stop"
$Dir = (Resolve-Path $Dir).Path
$state = Join-Path $Dir ".opencode\delegate"
New-Item -ItemType Directory -Force $state | Out-Null
$pidFile = Join-Path $state "pid.txt"
$metaFile = Join-Path $state "meta.json"
$log = Join-Path $state "run.log"
$errLog = Join-Path $state "run.err.log"
$agentPs1 = Join-Path $PSScriptRoot "agent.ps1"

function Get-RunProc {
    if (-not (Test-Path $pidFile)) { return $null }
    $id = [int](Get-Content $pidFile -Raw)
    return Get-Process -Id $id -ErrorAction SilentlyContinue
}
function Clean([string]$t) { return ($t -replace ([string][char]27 + "\[[0-9;?]*[A-Za-z]"), "") }
function Report {
    $p = Get-RunProc
    $meta = if (Test-Path $metaFile) { Get-Content $metaFile -Raw | ConvertFrom-Json } else { $null }
    $elapsed = if ($meta) { [int]((Get-Date) - [datetime]$meta.started).TotalMinutes } else { 0 }
    $st = if ($p) { "RUNNING" } elseif ($meta -and $meta.killed) { "TIMED_OUT" } else { "FINISHED" }
    Write-Output "STATE: $st  (elapsed ${elapsed} min, plan: $($meta.plan))"
    $prog = Join-Path $Dir ".opencode\progress.md"
    if (Test-Path $prog) {
        $lines = Get-Content $prog -Encoding utf8
        $done = ($lines | Where-Object { $_ -match '^\s*- \[x\]' }).Count
        $open = $lines | Where-Object { $_ -match '^\s*- \[ \]' }
        Write-Output "PROGRESS: $done done, $($open.Count) open"
        $open | Select-Object -First 10 | ForEach-Object { Write-Output "  $($_.Trim())" }
        $lines | Where-Object { $_ -match '(?i)blocker|blocked|failed' } | Select-Object -First 6 | ForEach-Object { Write-Output "  ! $($_.Trim())" }
    }
    if ($st -ne "RUNNING") {
        Write-Output "--- my-agent final output (tail) ---"
        if (Test-Path $log) { Clean ((Get-Content $log -Tail 40 -Encoding utf8) -join "`n") | Write-Output }
        if ((Test-Path $errLog) -and (Get-Item $errLog).Length -gt 0) {
            $e = Get-Content $errLog -Tail 8 -Encoding utf8 | Where-Object { $_ -match '(?i)error|fail|429|limit' }
            if ($e) { Write-Output "--- errors ---"; Clean ($e -join "`n") | Write-Output }
        }
        $ErrorActionPreference = "Continue"; $env:GIT_CONFIG_PARAMETERS = "'core.safecrlf=false'"
        Write-Output "--- git diff --stat ---"
        cmd /c "git -C `"$Dir`" diff --stat 2>nul" | Select-Object -Last 25
        cmd /c "git -C `"$Dir`" status --short 2>nul" | Where-Object { $_ -match '^\?\?' -and $_ -notmatch '\.opencode' } | Select-Object -First 15
    }
}

switch ($Action) {
    "start" {
        if (Get-RunProc) { Write-Output "Already running. Use: delegate.ps1 wait"; Report; exit 0 }
        if (-not $Plan) { throw "-Plan <file> is required" }
        $planPath = (Resolve-Path $Plan).Path
        # Guard: the plan's file paths must exist in -Dir, otherwise we're in the wrong project.
        $refs = [regex]::Matches((Get-Content $planPath -Raw), '`([A-Za-z0-9_.\-]+(?:/[A-Za-z0-9_.\-]+)+\.[A-Za-z0-9]+)') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
        if ($refs.Count -ge 2 -and -not $Force) {
            $found = @($refs | Where-Object { Test-Path (Join-Path $Dir $_) })
            if ($found.Count -eq 0) {
                Write-Output "WRONG PROJECT: none of the files named in the plan exist under $Dir (checked: $(($refs | Select-Object -First 5) -join ', ')). Re-run start with -Dir <the project root>, or add -Force if they are all new files."
                exit 2
            }
        }
        $prog = Join-Path $Dir ".opencode\progress.md"
        if ((Test-Path $prog) -and -not $Resume) {
            Move-Item $prog (Join-Path $state ("progress." + (Get-Date -Format "yyyyMMdd-HHmmss") + ".md")) -Force
        }
        # Pre-compute graphify context for the plan's files so the model doesn't have to explore.
        $ctxNote = ""
        $graphJson = Join-Path $Dir "graphify-out\graph.json"
        $gfy = (Get-Command graphify -ErrorAction SilentlyContinue).Source
        if (-not $gfy) { $gfy = Join-Path $env:USERPROFILE ".local\bin\graphify.exe" }
        if ((Test-Path $graphJson) -and (Test-Path $gfy)) {
            # Refresh the code graph if code changed since it was built (incremental AST update, no LLM, ~30 s).
            $prevEap = $ErrorActionPreference; $ErrorActionPreference = "Continue"
            $gTime = (Get-Item $graphJson).LastWriteTime
            $stale = $false
            $ct = cmd /c "git -C `"$Dir`" log -1 --format=%ct 2>nul"
            if ($ct -match '^\d+$' -and ([DateTimeOffset]::FromUnixTimeSeconds([int64]$ct).LocalDateTime -gt $gTime)) { $stale = $true }
            if (-not $stale) {
                foreach ($l in @(cmd /c "git -C `"$Dir`" status --porcelain 2>nul")) {
                    if ($l.Length -lt 4) { continue }
                    $p = $l.Substring(3).Trim('"'); if ($p -match ' -> ') { $p = ($p -split ' -> ')[-1] }
                    if ($p -match '^(\.opencode|graphify-out)/') { continue }
                    $fp = Join-Path $Dir $p
                    if ((Test-Path -LiteralPath $fp -PathType Leaf) -and (Get-Item -LiteralPath $fp).LastWriteTime -gt $gTime) { $stale = $true; break }
                }
            }
            if ($stale) { Push-Location $Dir; & $gfy update . *> $null; Pop-Location }
            $ErrorActionPreference = $prevEap
        }
        if ((Test-Path $graphJson) -and (Test-Path $gfy) -and $refs) {
            $ctxFile = Join-Path $state "graph-context.md"
            $out = @("# graphify outline of the plan's files (precomputed by delegate.ps1)", "Symbols are listed with their start line: Read with offset=<line> and a small limit instead of the whole file.", "")
            $prevEap = $ErrorActionPreference; $ErrorActionPreference = "Continue"
            $gpy = Join-Path $env:APPDATA "uv\tools\graphifyy\Scripts\python.exe"
            $outline = Join-Path $PSScriptRoot "graph-outline.py"
            $ol = @()
            if ((Test-Path $gpy) -and (Test-Path $outline)) {
                $ol = @(& $gpy $outline $Dir @($refs | Select-Object -First 20) 2>$null)
                if ($LASTEXITCODE -ne 0) { $ol = @() }
            }
            if ($ol.Count -gt 0) { $out += $ol }
            else {
                Push-Location $Dir
                foreach ($r in ($refs | Where-Object { Test-Path (Join-Path $Dir $_) } | Select-Object -First 12)) {
                    $ex = @(& $gfy explain $r 2>$null)
                    if ($LASTEXITCODE -eq 0 -and ($ex -match [regex]::Escape($r))) { $out += "## $r"; $out += ($ex | Select-Object -First 22); $out += "" }
                }
                Pop-Location
            }
            $ErrorActionPreference = $prevEap
            $out | Set-Content $ctxFile -Encoding utf8
            $ctxNote = " FIRST read `"$ctxFile`": for each file in the plan it lists symbols with line numbers, imports and importers (from graphify). Use it instead of grep/ls/whole-file reads; read only the line ranges you need. For other code run graphify explain `"PATH::SYMBOL`" or graphify query before grep."
        }
        $msg = "Implement the plan in `"$planPath`" end to end. Track steps in .opencode/progress.md (create it fresh from this plan unless it already tracks this exact plan). Follow your orchestrator rules (do small steps yourself, delegate bigger ones to implementer), verify each step yourself.$ctxNote Run typecheck/analyze/tests once at the end of each step, not after every edit. If the files the plan names do not exist in this folder, stop at once and report it; never adapt the plan to a different codebase. Then: do not commit or push. Do not ask me questions; make reasonable decisions and note them in progress.md. When finished, reply with a short final summary: steps done, verify command results, open issues."
        $empty = Join-Path $state "empty.txt"; if (-not (Test-Path $empty)) { "" | Set-Content $empty }  # may be held open by the LiteLLM bridge from an earlier run
        Remove-Item $log, $errLog -ErrorAction SilentlyContinue
        # ---- smart engine routing (Engine auto): plan difficulty + Antigravity quota ----
        $routeNote = ""
        if ($Engine -eq "auto") {
            $planText = Get-Content $planPath -Raw
            $t = $Tier
            if ($t -eq "auto") {
                if ($planText -match '(?im)^\s*(?:\*\*)?(?:tier|difficulty)(?:\*\*)?\s*[:=]\s*(?:\*\*)?\s*(hard|medium|easy)') { $t = $Matches[1].ToLower() }
                else {
                    $steps = ([regex]::Matches($planText, '(?m)^\s*(#{2,4}\s|\d+[\.\)]\s|- \[ \])')).Count
                    $hardKw = ([regex]::Matches($planText, '(?i)architect|refactor|migrat|concurren|race condition|security|auth|debug|root cause|performance|algorithm')).Count
                    if ($hardKw -ge 3 -or $steps -ge 12) { $t = "hard" } elseif ($steps -le 3 -and $planText.Length -lt 2500) { $t = "easy" } else { $t = "medium" }
                }
            }
            # remaining Antigravity quota (percent left); unknown -> assume ok
            $q = @{ gemini = 100; claude = 100; argon = 100 }
            try {
                $agyExe = (Get-Command agy -ErrorAction SilentlyContinue).Source; if (-not $agyExe) { $agyExe = Join-Path $env:LOCALAPPDATA "agy\bin\agy.exe" }
                if (-not (Test-Path $agyExe)) { throw "agy not installed" }
                $u = (& $agyExe -p "/usage" --print-timeout 60s 2>&1 | Out-String)
                function MinPct($pat) { $v = [regex]::Matches($u, "(?im)$pat[^\r\n%]*?(\d{1,3})\s*%") | ForEach-Object { [int]$_.Groups[1].Value }; if ($v) { ($v | Measure-Object -Minimum).Minimum } else { 100 } }
                $q.gemini = MinPct 'gemini(?!\s*4)'; $q.claude = MinPct '(claude|gpt)'; $q.argon = MinPct '(argon|gemini\s*4)'
            } catch { $q = @{ gemini = 0; claude = 0; argon = 0 } }  # no agy / no quota info -> free chain
            $min = 15
            $Engine = "opencode"; $pick = "free chain (Kilo/OpenRouter/NVIDIA/Gemini API/local)"
            if ($t -eq "hard") {
                if ($q.claude -ge $min) { $Engine = "agy"; $Model = "claude-sonnet-5-5-high" }
                elseif ($q.argon -ge $min -and $q.gemini -ge $min) { $Engine = "agy"; $Model = "gemini-4-argon-high" }
            } elseif ($t -eq "medium") {
                if ($q.argon -ge $min -and $q.gemini -ge $min) { $Engine = "agy"; $Model = "gemini-4-argon-medium" }
                elseif ($q.gemini -ge $min) { $Engine = "agy"; $Model = "gemini-3.8-flash-medium" }
            }
            if ($Engine -eq "agy") { $pick = "Antigravity $Model" }
            $routeNote = " tier=$t quota(gemini $($q.gemini)%, claude $($q.claude)%, argon $($q.argon)%) -> $pick"
        }
        if ($Engine -eq "agy") {
            $agy = (Get-Command agy -ErrorAction SilentlyContinue).Source
            if (-not $agy) { $agy = Join-Path $env:LOCALAPPDATA "agy\bin\agy.exe" }
            $msg = $msg.Replace("Follow your orchestrator rules (do small steps yourself, delegate bigger ones to implementer), verify each step yourself.", "Work through the steps one at a time and verify each step yourself.")
            $argList = @("-p", "`"$($msg -replace '"', '\"')`"", "--model", $Model, "--dangerously-skip-permissions", "--print-timeout", "0s")
            $p = Start-Process $agy -ArgumentList $argList -WorkingDirectory $Dir -WindowStyle Hidden -RedirectStandardInput $empty -RedirectStandardOutput $log -RedirectStandardError $errLog -PassThru
        } else {
            $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$agentPs1`"", "run", "--agent", "orchestrator", "--dir", "`"$Dir`"", "--title", "`"delegate: $(Split-Path $planPath -Leaf)`"", "`"$($msg -replace '"', '\"')`"")
            $p = Start-Process powershell -ArgumentList $argList -WorkingDirectory $Dir -WindowStyle Hidden -RedirectStandardInput $empty -RedirectStandardOutput $log -RedirectStandardError $errLog -PassThru
        }
        $p.Id | Set-Content $pidFile
        @{ plan = $planPath; started = (Get-Date).ToString("o"); timeoutMin = $TimeoutMin; killed = $false; engine = $Engine; model = $Model; fellBack = [bool]$FellBack } | ConvertTo-Json | Set-Content $metaFile
        Write-Output "Started my-agent [$Engine$(if($Engine -eq 'agy'){" $Model"})] (pid $($p.Id)) on $planPath in $Dir.$routeNote Next: delegate.ps1 wait"
    }
    "wait" {
        $deadline = (Get-Date).AddMinutes($Minutes)
        while ((Get-RunProc) -and (Get-Date) -lt $deadline) {
            $meta = Get-Content $metaFile -Raw | ConvertFrom-Json
            if (((Get-Date) - [datetime]$meta.started).TotalMinutes -gt $meta.timeoutMin) {
                $p = Get-RunProc; if ($p) { taskkill /T /F /PID $p.Id | Out-Null }
                $meta.killed = $true; $meta | ConvertTo-Json | Set-Content $metaFile
                break
            }
            Start-Sleep -Seconds 15
        }
        if (-not (Get-RunProc)) {
            $meta = Get-Content $metaFile -Raw | ConvertFrom-Json
            $out = ((Get-Content $log -Raw -ErrorAction SilentlyContinue) + (Get-Content $errLog -Raw -ErrorAction SilentlyContinue))
            if ($meta.engine -eq "agy" -and -not $meta.fellBack -and $out -match '(?i)RESOURCE_EXHAUSTED|quota|rate.?limit|\b429\b|usage limit') {
                Write-Output "Antigravity quota hit -> continuing on the free chain (opencode, -Resume)."
                & $PSCommandPath start -Plan $meta.plan -Dir $Dir -Resume -Force -Engine opencode -FellBack
                $deadline = (Get-Date).AddMinutes($Minutes)
                while ((Get-RunProc) -and (Get-Date) -lt $deadline) { Start-Sleep -Seconds 15 }
            }
        }
        Report
    }
    "status" { Report }
    "stop" {
        $p = Get-RunProc
        if ($p) { taskkill /T /F /PID $p.Id | Out-Null; Write-Output "Stopped pid $($p.Id)" } else { Write-Output "Not running" }
    }
}


