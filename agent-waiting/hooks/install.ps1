# Installs this mod's hooks on Windows: the Cursor Agent CLI status hook. (The
# Claude Code hook is sh only; there is no Windows version yet.)
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File agent-waiting\hooks\install.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File agent-waiting\hooks\install.ps1 -Uninstall
#
# Copies cursor\status-hook.ps1 to %USERPROFILE%\.cursor\herdr-status-hook.ps1 and
# adds its sessionStart, beforeSubmitPrompt, stop and sessionEnd entries to
# %USERPROFILE%\.cursor\hooks.json, after your own hooks (the old file is saved as
# hooks.json.bak-pre-herdr-status-hook), with hc's full path in each command.
# Running it again updates the hook. Needs hc on PATH (or HERDR_HC). Honors
# CURSOR_CONFIG_DIR. The hook needs `hc report` (herdr-core#81); without it the
# hook is installed but reports nothing, and this says so.
param([switch]$Uninstall)
$ErrorActionPreference = "Stop"
# The fork publishes each build as a prerelease, so not /releases/latest.
$release = "https://github.com/zztalker/herdr-core/releases"
$src = Join-Path (Join-Path $PSScriptRoot "cursor") "status-hook.ps1"
$dir = if ($env:CURSOR_CONFIG_DIR) { $env:CURSOR_CONFIG_DIR } else { Join-Path $HOME ".cursor" }
$hook = Join-Path $dir "herdr-status-hook.ps1"
$cfg = Join-Path $dir "hooks.json"
$events = @(@("sessionStart", "start"), @("beforeSubmitPrompt", "prompt"), @("stop", "stop"), @("sessionEnd", "end"))

function Read-Config {
    if (Test-Path -LiteralPath $cfg) { return [IO.File]::ReadAllText($cfg) | ConvertFrom-Json }
    return [pscustomobject]@{ version = 1; hooks = [pscustomobject]@{} }
}
# UTF-8 without a BOM, as Cursor wrote it.
function Write-Config($j) {
    [IO.File]::WriteAllText($cfg, ($j | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding $false))
}
function Test-Ours($entry) { "$($entry.command)".Contains($hook) }
function Remove-Ours($j) {
    foreach ($p in @($j.hooks.PSObject.Properties)) {
        $p.Value = @(@($p.Value) | Where-Object { -not (Test-Ours $_) })
    }
}

if ($Uninstall) {
    if (Test-Path -LiteralPath $cfg) {
        $j = Read-Config
        if ($j.hooks -and @($j.hooks.PSObject.Properties | ForEach-Object { @($_.Value) } | Where-Object { Test-Ours $_ }).Count -gt 0) {
            Copy-Item -LiteralPath $cfg "$cfg.bak-pre-herdr-status-hook-uninstall" -Force
            Remove-Ours $j
            foreach ($p in @($j.hooks.PSObject.Properties)) { if (@($p.Value).Count -eq 0) { $j.hooks.PSObject.Properties.Remove($p.Name) } }
            Write-Config $j
        }
    }
    Remove-Item -LiteralPath $hook -Force -ErrorAction SilentlyContinue
    Write-Output "removed the Cursor hook from $cfg"
    exit 0
}

$hc = $env:HERDR_HC
if (-not $hc) {
    $found = Get-Command hc -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { $hc = $found.Path }
}
if (-not $hc -or -not (Test-Path -LiteralPath $hc)) {
    [Console]::Error.WriteLine("install.ps1: hc not found (set HERDR_HC to the full path of hc.exe)")
    exit 1
}
if (-not (Test-Path -LiteralPath $dir) -and -not (Get-Command cursor-agent -ErrorAction SilentlyContinue)) {
    Write-Output "No Cursor on this machine ($dir, cursor-agent): nothing installed."
    exit 0
}

$hasReport = $false
$ErrorActionPreference = "Continue"
try { & $hc report --help *> $null; $hasReport = ($LASTEXITCODE -eq 0) } catch {}
$ErrorActionPreference = "Stop"

New-Item -ItemType Directory -Force $dir | Out-Null
Copy-Item -LiteralPath $src "$hook.new" -Force
Move-Item -LiteralPath "$hook.new" $hook -Force
if ((Test-Path -LiteralPath $cfg) -and -not (Test-Path -LiteralPath "$cfg.bak-pre-herdr-status-hook")) {
    Copy-Item -LiteralPath $cfg "$cfg.bak-pre-herdr-status-hook"
}
$j = Read-Config
if ($j.PSObject.Properties.Name -notcontains "version") { $j | Add-Member -NotePropertyName version -NotePropertyValue 1 }
if ($null -eq $j.hooks) { $j | Add-Member -Force -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{}) }
# Ours are taken out and put back last: running it again gives the same file.
Remove-Ours $j
foreach ($pair in $events) {
    $e, $a = $pair
    $entry = [pscustomobject]@{ command = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$hook`" $a `"$hc`""; timeout = 5 }
    if ($j.hooks.PSObject.Properties.Name -contains $e) { $j.hooks.$e = @(@($j.hooks.$e) + $entry) }
    else { $j.hooks | Add-Member -NotePropertyName $e -NotePropertyValue @($entry) }
}
Write-Config $j
Write-Output "installed the Cursor hook: $hook (hc: $hc)"
Write-Output "New Cursor sessions use it; restart running ones."

if (-not $hasReport) {
    Write-Output ""
    Write-Output "WARNING: $hc has no 'hc report', so the hook reports nothing yet."
    Write-Output "'hc report' is in herdr-core#81 (https://github.com/herdrdev/herdr-core/pull/81),"
    Write-Output "not in a herdr-core release. Until it is, install the newest *-report.1 build from:"
    Write-Output "  $release"
    Write-Output "Then check with: hc report --help"
}
exit 0
