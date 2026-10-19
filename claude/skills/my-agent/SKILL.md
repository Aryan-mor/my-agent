---
name: my-agent
disable-model-invocation: true
description: Plan with Claude, let my-agent (a cheap OpenCode agent) implement, review, repeat until done
argument-hint: <what to build, or path to an existing plan file>
model: sonnet
---

You are the **planner and reviewer**. The cheap coding agent **my-agent** (OpenCode `orchestrator` agent behind a LiteLLM proxy) does all implementation. Your job is to spend as few tokens as possible: plan precisely, delegate, review with checks, and loop. Do NOT write the feature code yourself.

Task: $ARGUMENTS

Runner (PowerShell, works from any project folder):
`powershell -NoProfile -ExecutionPolicy Bypass -File "<MY_AGENT_HOME>\scripts\delegate.ps1" <start|wait|status|stop> [-Plan <file>] [-Dir <project root>]`

(`<MY_AGENT_HOME>` is replaced with the absolute path of the my-agent repository by the installer.)

## 1. Plan (cheap)
- If $ARGUMENTS is a path to an existing plan file, use it as-is and skip to step 2.
- Otherwise explore minimally: use Grep/Glob and read only the relevant line ranges. Never read whole large files, generated files, lockfiles, or build output. Stop exploring once you know which files and functions change.
- If a requirement is truly ambiguous, ask the user once, up front. After that, never ask again during the loop.
- Write the plan to `.opencode/plans/<short-slug>-r1.md`:
  - Goal: 2-3 lines.
  - Numbered steps, each 1-3 files. For each step give exact file paths (with line hints or function names), the precise behaviour change, and a `done-check:` command (a test, analyze, or typecheck command, or a grep).
  - Constraints and out-of-scope items.
  - A final verification step listing the project's full check commands. Use the commands the project actually has, e.g. `pnpm typecheck`, `pnpm test`, `npm test`, `flutter analyze`, `flutter test`, `pytest`.
  - Paste no code except short interface or signature snippets. my-agent reads files itself.

## 2. Delegate
- Run the runner with `start -Plan <plan file> -Dir <project root the plan targets>` (the folder its file paths are relative to; it may differ from your current folder). If it prints `WRONG PROJECT`, find the right project root and re-run with that `-Dir`; never let my-agent work in a project the plan was not written for. Pass the same `-Dir` to `wait`, `status` and `stop`.
- Then run the runner with `wait`, using a 600000 ms Bash timeout. Repeat `wait` while the output says `STATE: RUNNING`.
- Do nothing else while it runs. Do not read the log, progress.md, or files in between. The `wait` output already has everything you need.

## 3. Review (cheap)
- Run the plan's verification commands yourself. Show only the failing parts, e.g. pipe through `Select-String` or `tail`.
- Use `git diff --stat` for an overview. Read `git diff -- <file>` only for files whose checks failed, files the report flags, or high-risk files such as migrations, auth, or payments. Do not read the whole diff when the checks are green.
- Check every plan step against the result: is each one done, and are behaviours implemented as specified?

## 4. Loop
- If everything passes and all steps are done, go to step 5.
- Otherwise write `.opencode/plans/<short-slug>-r<N+1>.md`. It should contain only the remaining fixes: exact file and line, what is wrong, what is expected, and a done-check for each. Then go back to step 2. The runner archives the old progress.md automatically.
- Maximum **3 rounds** in total. If it is still failing after round 3, stop and report.
- If my-agent clearly failed because of the model or provider (rate limit, timeout, empty output) and not because of the code, re-run the same plan once with `start -Plan <same file> -Resume`.
- Exception: you may make a trivial fix yourself (3 lines or fewer, such as a typo or an import) instead of starting a whole new round.

## 5. Report
Reply to the user in English, briefly:
- What was done and how many rounds it took.
- Check results.
- Anything left for them, such as manual testing.

Write all plans, briefs and reports in English, whatever language the user writes in.

Never commit, push, reset, or delete anything unless the user explicitly asks.

