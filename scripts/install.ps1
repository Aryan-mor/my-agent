# install.ps1 - install my-agent's global pieces from this repo.
#   - OpenCode global agents (orchestrator, implementer) + dcp.jsonc  -> ~/.config/opencode/
#   - optional rtk plugin (-WithRtk)                                   -> ~/.config/opencode/plugins/rtk.ts
#   - Claude Code skill (UTF-8 without BOM, <MY_AGENT_HOME> filled in) -> ~/.claude/skills/my-agent/SKILL.md
#   - Cursor command    (UTF-8 without BOM, <MY_AGENT_HOME> filled in) -> ~/.cursor/commands/my-agent.md
# Existing files are backed up next to the original as <name>.bak-<timestamp> before being replaced.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File scripts\install.ps1 [-WithRtk] [-NoClaude] [-NoCursor] [-SkipOpenCode]
#   -NoClaude      do not install the Claude Code skill (-SkipSkill is an alias)
#   -NoCursor      do not install the Cursor command
#   -SkipOpenCode  do not touch ~/.config/opencode
param(
    [switch]$WithRtk,
    [Alias("SkipSkill")][switch]$NoClaude,
    [switch]$NoCursor,
    [switch]$SkipOpenCode
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Backup-IfExists([string]$path) {
    if (Test-Path $path) {
        $bak = "$path.bak-$stamp"
        Copy-Item $path $bak -Force
        Write-Host "  backed up $path -> $bak"
    }
}
function Install-File([string]$src, [string]$dst) {
    New-Item -ItemType Directory -Force (Split-Path -Parent $dst) | Out-Null
    Backup-IfExists $dst
    Copy-Item $src $dst -Force
    Write-Host "  installed $dst"
}
# Copy a markdown template, replacing <MY_AGENT_HOME> with the repo path; always written as UTF-8 WITHOUT BOM
# (a BOM in front of YAML frontmatter breaks Claude Code skills).
function Install-Template([string]$src, [string]$dst) {
    $text = [System.IO.File]::ReadAllText($src, $utf8NoBom)
    $text = $text.TrimStart([char]0xFEFF).Replace("<MY_AGENT_HOME>", $root)
    New-Item -ItemType Directory -Force (Split-Path -Parent $dst) | Out-Null
    Backup-IfExists $dst
    [System.IO.File]::WriteAllText($dst, $text, $utf8NoBom)
    Write-Host "  installed $dst (MY_AGENT_HOME = $root)"
}

if (-not $SkipOpenCode) {
    $oc = Join-Path $env:USERPROFILE ".config\opencode"
    Write-Host "OpenCode global config: $oc"
    Install-File (Join-Path $root "opencode\agents\orchestrator.md") (Join-Path $oc "agents\orchestrator.md")
    Install-File (Join-Path $root "opencode\agents\implementer.md") (Join-Path $oc "agents\implementer.md")
    Install-File (Join-Path $root "opencode\dcp.jsonc") (Join-Path $oc "dcp.jsonc")
    # Never overwrite an existing global opencode.jsonc / package.json; only create them if missing.
    foreach ($f in @("opencode.jsonc", "package.json")) {
        $dst = Join-Path $oc $f
        if (-not (Test-Path $dst)) { Copy-Item (Join-Path $root "opencode\$f") $dst; Write-Host "  created $dst" }
        else { Write-Host "  kept existing $dst (compare with opencode\$f in the repo if something is missing)" }
    }
    if ($WithRtk) {
        if (-not (Get-Command rtk -ErrorAction SilentlyContinue)) { Write-Warning "rtk is not on PATH; the plugin will stay disabled until it is." }
        Install-File (Join-Path $root "opencode\plugins\rtk.ts") (Join-Path $oc "plugins\rtk.ts")
    }
}

if (-not $NoClaude) {
    Write-Host "Claude Code skill:"
    Install-Template (Join-Path $root "claude\skills\my-agent\SKILL.md") (Join-Path $env:USERPROFILE ".claude\skills\my-agent\SKILL.md")
}

if (-not $NoCursor) {
    Write-Host "Cursor command:"
    Install-Template (Join-Path $root "cursor\commands\my-agent.md") (Join-Path $env:USERPROFILE ".cursor\commands\my-agent.md")
    if (-not $NoClaude) {
        Write-Host "  note: Cursor also loads skills from ~/.claude/skills, so Cursor may list /my-agent twice; both work."
    }
}
Write-Host "Done. Restart Claude Code / reload the Cursor window (Ctrl+Shift+P -> 'Developer: Reload Window') so /my-agent is picked up."
