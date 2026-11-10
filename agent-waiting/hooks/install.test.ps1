# powershell -NoProfile -ExecutionPolicy Bypass -File agent-waiting\hooks\install.test.ps1
# (or pwsh -NoProfile -File ...). Runs install.ps1 against a throwaway Cursor folder
# (CURSOR_CONFIG_DIR) with fake hc's, each a child PowerShell as a person would run it.
$ErrorActionPreference = "Stop"
$inst = Join-Path $PSScriptRoot "install.ps1"
$shell = (Get-Process -Id $PID).Path
$tmp = Join-Path ([IO.Path]::GetTempPath()) "herdr-hooks-install-test-$PID"
New-Item -ItemType Directory -Force $tmp | Out-Null
$script:fails = 0
function Ok($name) { Write-Output "ok   $name" }
function Fail($name, $why) { Write-Output "FAIL ${name}: $why"; $script:fails++ }
function Norm($path) { (Get-Content -Raw -LiteralPath $path | ConvertFrom-Json) | ConvertTo-Json -Depth 20 -Compress }

# A fake hc with `report` (records what it reports) and one without.
$log = Join-Path $tmp "log"
$hc = Join-Path $tmp "hc.ps1"
$old = Join-Path $tmp "hc-old.ps1"
Set-Content -LiteralPath $hc -Value 'if ($args[0] -eq "report" -and $args[1] -eq "--help") { exit 0 }; Add-Content -LiteralPath $env:FAKE_LOG -Value ($args -join " ")'
Set-Content -LiteralPath $old -Value '[Console]::Error.WriteLine("error: unrecognized subcommand"); exit 2'
$env:FAKE_LOG = $log
Remove-Item Env:HC_TERMINAL_ID -ErrorAction SilentlyContinue

$dir = Join-Path $tmp "cursor"
$env:CURSOR_CONFIG_DIR = $dir
$cfg = Join-Path $dir "hooks.json"
$hook = Join-Path $dir "herdr-status-hook.ps1"
function Install($hcPath, $arg) {
    # Windows PowerShell 5.1 turns a child's stderr into an error under "Stop".
    $ErrorActionPreference = "Continue"
    $env:HERDR_HC = $hcPath
    $a = @(); if ($arg) { $a += $arg }
    $out = & $shell -NoProfile -ExecutionPolicy Bypass -File $inst @a 2>&1
    $script:code = $LASTEXITCODE
    return (@($out) -join "`n")
}
function Ours($event) { @((Get-Content -Raw -LiteralPath $cfg | ConvertFrom-Json).hooks.$event | Where-Object { "$($_.command)".Contains($hook) }) }

try {
    New-Item -ItemType Directory -Force $dir | Out-Null
    # Someone's own hooks (the TUI's sessionStart, an unrelated stop) and a key of theirs.
    $theirs = '{"version":1,"mine":true,"hooks":{"sessionStart":[{"command":"powershell -NoProfile -File C:\\x\\herdr-agent-state.ps1 session"}],"stop":[{"command":"say done","timeout":3}]}}'
    [IO.File]::WriteAllText($cfg, $theirs)
    $before = Norm $cfg

    # 1. Install: four entries, after theirs, with hc's path as the hook's argument.
    $out = Install $hc
    if ($script:code -ne 0) { Fail "install exits 0" "exit $($script:code): $out" }
    if ((Test-Path $hook) -and ((Get-FileHash $hook).Hash -eq (Get-FileHash (Join-Path $PSScriptRoot "cursor/status-hook.ps1")).Hash)) { Ok "the hook is copied" } else { Fail "the hook is copied" "missing or different" }
    $j = Get-Content -Raw -LiteralPath $cfg | ConvertFrom-Json
    foreach ($pair in @(@("sessionStart", "start"), @("beforeSubmitPrompt", "prompt"), @("stop", "stop"), @("sessionEnd", "end"))) {
        $e, $a = $pair
        $mine = Ours $e
        $last = @($j.hooks.$e)[-1].command
        $want = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$hook`" $a `"$hc`""
        if ($mine.Count -eq 1 -and $last -eq $want) { Ok "${e}: one entry, last, $a" } else { Fail "$e entry" "n=$($mine.Count) last=$last want=$want" }
    }
    if (@($j.hooks.sessionStart)[0].command -like "*herdr-agent-state.ps1 session" -and @($j.hooks.stop)[0].command -eq "say done" -and $j.mine -eq $true -and $j.version -eq 1) { Ok "their hooks and keys stay" } else { Fail "their hooks and keys stay" (Get-Content -Raw $cfg) }
    if ((Test-Path "$cfg.bak-pre-herdr-status-hook") -and ((Norm "$cfg.bak-pre-herdr-status-hook") -eq $before)) { Ok "the old file is kept" } else { Fail "the old file is kept" "no backup" }
    if ([IO.File]::ReadAllBytes($cfg)[0] -eq 0xEF) { Fail "hooks.json has no BOM" "it starts with a BOM" } else { Ok "hooks.json has no BOM" }
    if ($out -match "WARNING") { Fail "hc with report: no warning" $out } else { Ok "hc with report: no warning" }

    # 2. The installed command, run as Cursor runs it (powershell there, this shell here), reports.
    $cmd = @($j.hooks.beforeSubmitPrompt)[-1].command
    if ($cmd -match '-File "([^"]+)" (\w+) "([^"]+)"$') {
        [IO.File]::WriteAllText($log, "")
        $env:HC_TERMINAL_ID = "t7"; $env:HERDR_HC = ""
        $res = '{}' | & $shell -NoProfile -ExecutionPolicy Bypass -File $Matches[1] $Matches[2] $Matches[3]
        Remove-Item Env:HC_TERMINAL_ID
        if ("$res".Trim() -eq '{"continue":true}' -and ([IO.File]::ReadAllText($log)).Trim() -eq "report state=working:app=cursor") { Ok "the installed command reports" } else { Fail "the installed command reports" "out=$res log=$([IO.File]::ReadAllText($log))" }
    } else { Fail "the installed command reports" "unexpected command: $cmd" }

    # 3. Again: the same file, nothing doubled.
    $first = Get-Content -Raw -LiteralPath $cfg
    Install $hc | Out-Null
    if ((Get-Content -Raw -LiteralPath $cfg) -eq $first) { Ok "installing again changes nothing" } else { Fail "installing again changes nothing" (Get-Content -Raw $cfg) }

    # 4. Uninstall: back to what they had, the hook gone.
    Install $hc "-Uninstall" | Out-Null
    if ((Norm $cfg) -eq $before -and -not (Test-Path $hook)) { Ok "uninstall restores their file" } else { Fail "uninstall restores their file" (Get-Content -Raw $cfg) }

    # 5. An hc without `report`: installed anyway, with a warning that says where to get one.
    $out = Install $old
    if ($script:code -eq 0 -and (Test-Path $hook)) { Ok "old hc: still installs" } else { Fail "old hc: still installs" "exit $($script:code): $out" }
    if ($out -match "(?s)WARNING.*hc report.*herdr-core/releases") { Ok "old hc: warns, with where to get it" } else { Fail "old hc: warns, with where to get it" $out }
    Install $hc "-Uninstall" | Out-Null

    # 6. No hc: refuses, changes nothing.
    $out = Install (Join-Path $tmp "no-such-hc.exe")
    if ($script:code -ne 0 -and (Norm $cfg) -eq $before -and -not (Test-Path $hook)) { Ok "no hc: refuses" } else { Fail "no hc: refuses" "exit $($script:code): $out" }

    # 7. No hooks.json yet: one is made.
    Remove-Item -LiteralPath $cfg
    Install $hc | Out-Null
    $j = Get-Content -Raw -LiteralPath $cfg | ConvertFrom-Json
    if ($j.version -eq 1 -and @($j.hooks.PSObject.Properties).Count -eq 4 -and (Ours "stop").Count -eq 1) { Ok "no hooks.json: one is made" } else { Fail "no hooks.json: one is made" (Get-Content -Raw $cfg) }

    # 8. No Cursor on this machine: nothing installed, said plainly.
    $env:CURSOR_CONFIG_DIR = Join-Path $tmp "no-cursor"
    $out = Install $hc
    if ($script:code -eq 0 -and -not (Test-Path $env:CURSOR_CONFIG_DIR) -and $out -match "nothing installed") { Ok "no Cursor: nothing installed" } else { Fail "no Cursor: nothing installed" "exit $($script:code): $out" }
} finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

if ($script:fails -eq 0) { Write-Output "all passed"; exit 0 }
Write-Output "$($script:fails) failed"
exit 1
