# install.ps1 - install my-agent's global pieces from this repo.
#   - OpenCode global agents (orchestrator, implementer) + dcp.jsonc  -> ~/.config/opencode/
#   - optional rtk plugin (-WithRtk)                                   -> ~/.config/opencode/plugins/rtk.ts
#   - Claude Code skill (UTF-8 without BOM, <MY_AGENT_HOME> filled in) -> ~/.claude/skills/my-agent/SKILL.md
# Existing files are backed up next to the original as <name>.bak-<timestamp> before being replaced.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File scripts\install.ps1 [-WithRtk] [-SkipSkill] [-SkipOpenCode]
param([switch]$WithRtk, [switch]$SkipSkill, [switch]$SkipOpenCode)
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

if (-not $SkipSkill) {
    $skillDst = Join-Path $env:USERPROFILE ".claude\skills\my-agent\SKILL.md"
    Write-Host "Claude Code skill: $skillDst"
    $text = [System.IO.File]::ReadAllText((Join-Path $root "claude\skills\my-agent\SKILL.md"), $utf8NoBom)
    $text = $text.TrimStart([char]0xFEFF).Replace("<MY_AGENT_HOME>", $root)
    New-Item -ItemType Directory -Force (Split-Path -Parent $skillDst) | Out-Null
    Backup-IfExists $skillDst
    [System.IO.File]::WriteAllText($skillDst, $text, $utf8NoBom)   # no BOM: a BOM breaks the YAML frontmatter
    Write-Host "  installed $skillDst (MY_AGENT_HOME = $root)"
}
Write-Host "Done. Restart Claude Code / Cursor so the /my-agent skill is picked up."
