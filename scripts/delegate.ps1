# delegate.ps1 - run my-agent (OpenCode orchestrator via LiteLLM) headless on a plan file and report compactly.
# Used by the Claude Code /my-agent skill so Claude only plans + reviews, my-agent does the work.
#   delegate.ps1 start -Plan <plan.md> [-Dir <project>] [-Resume] [-TimeoutMin 90]
#   delegate.ps1 wait  [-Dir <project>] [-Minutes 9]     (blocks up to N minutes, then prints a short report)
#   delegate.ps1 status [-Dir <project>]
#   delegate.ps1 stop  [-Dir <project>]
# Exit code 2 + "WRONG PROJECT" if none of the plan's backticked file paths exist under -Dir (use -Force for all-new files).
param(
    [Parameter(Position = 0)][ValidateSet("start", "wait", "status", "stop")][string]$Action = "status",
    [string]$Plan,
    [string]$Dir = (Get-Location).Path,
    [switch]$Resume,
    [switch]$Force,
    [int]$Minutes = 9,
    [int]$TimeoutMin = 90
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
        if ((Test-Path $graphJson) -and (Test-Path $gfy) -and $refs) {
            $ctxFile = Join-Path $state "graph-context.md"
            $out = @("# graphify context for the plan's files (precomputed by delegate.ps1)", "")
            $prevEap = $ErrorActionPreference; $ErrorActionPreference = "Continue"
            Push-Location $Dir
            foreach ($r in ($refs | Where-Object { Test-Path (Join-Path $Dir $_) } | Select-Object -First 12)) {
                $ex = @(& $gfy explain $r 2>$null)
                if ($LASTEXITCODE -eq 0 -and ($ex -match [regex]::Escape($r))) { $out += "## $r"; $out += ($ex | Select-Object -First 22); $out += "" }
            }
            Pop-Location
            $ErrorActionPreference = $prevEap
            $out | Set-Content $ctxFile -Encoding utf8
            $ctxNote = " FIRST read `"$ctxFile`": it already lists, for each file in the plan, what it imports and who uses it (from graphify). Use it instead of grep/ls/reading files to find code; for anything else run graphify query/explain before grep."
        }
        $msg = "Implement the plan in `"$planPath`" end to end. Track steps in .opencode/progress.md (create it fresh from this plan unless it already tracks this exact plan). Follow your orchestrator rules (do small steps yourself, delegate bigger ones to implementer), verify each step yourself.$ctxNote Run typecheck/analyze/tests once at the end of each step, not after every edit. If the files the plan names do not exist in this folder, stop at once and report it; never adapt the plan to a different codebase. Then: do not commit or push. Do not ask me questions; make reasonable decisions and note them in progress.md. When finished, reply with a short final summary: steps done, verify command results, open issues."
        $empty = Join-Path $state "empty.txt"; if (-not (Test-Path $empty)) { "" | Set-Content $empty }  # may be held open by the LiteLLM bridge from an earlier run
        Remove-Item $log, $errLog -ErrorAction SilentlyContinue
        $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$agentPs1`"", "run", "--agent", "orchestrator", "--dir", "`"$Dir`"", "--title", "`"delegate: $(Split-Path $planPath -Leaf)`"", "`"$($msg -replace '"', '\"')`"")
        $p = Start-Process powershell -ArgumentList $argList -WorkingDirectory $Dir -WindowStyle Hidden -RedirectStandardInput $empty -RedirectStandardOutput $log -RedirectStandardError $errLog -PassThru
        $p.Id | Set-Content $pidFile
        @{ plan = $planPath; started = (Get-Date).ToString("o"); timeoutMin = $TimeoutMin; killed = $false } | ConvertTo-Json | Set-Content $metaFile
        Write-Output "Started my-agent (pid $($p.Id)) on $planPath in $Dir. Next: delegate.ps1 wait"
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
        Report
    }
    "status" { Report }
    "stop" {
        $p = Get-RunProc
        if ($p) { taskkill /T /F /PID $p.Id | Out-Null; Write-Output "Stopped pid $($p.Id)" } else { Write-Output "Not running" }
    }
}


