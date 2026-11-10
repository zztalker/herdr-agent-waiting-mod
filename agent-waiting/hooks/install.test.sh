#!/bin/sh
# sh agent-waiting/hooks/install.test.sh
# Runs install.sh in a throwaway HOME with fake hc's: it installs the hook of each
# agent it finds, skips the others, and says loudly when hc has no `report`.
set -u
here=$(cd "$(dirname "$0")" && pwd)
inst="$here/install.sh"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fails=0
ok() { echo "ok   $1"; }
fail() { echo "FAIL $1: $2"; fails=$((fails + 1)); }
mkdir -p "$tmp/bin" "$tmp/old"
printf '#!/bin/sh\nexit 0\n' > "$tmp/bin/hc"
printf '#!/bin/sh\necho "error: unrecognized subcommand" >&2; exit 2\n' > "$tmp/old/hc"
chmod +x "$tmp/bin/hc" "$tmp/old/hc"
unset CLAUDE_CONFIG_DIR CURSOR_CONFIG_DIR HERDR_HC
# Only jq beside the system tools: a real hc, claude or cursor-agent on PATH must not leak in.
mkdir -p "$tmp/jq" && ln -s "$(command -v jq)" "$tmp/jq/jq"
base=/usr/bin:/bin:$tmp/jq
fresh() { rm -rf "$tmp/home"; mkdir -p "$tmp/home"; for d in "$@"; do mkdir -p "$tmp/home/$d"; done; }
run() { HOME="$tmp/home" PATH="$1:$base" sh "$inst" ${2:-} 2>&1; }
claude_in() { jq -e '[.hooks.Stop[]?.hooks[]?.command | select(contains("herdr-background-waiting-hook.sh"))] | length == 1' "$tmp/home/.claude/settings.json" >/dev/null 2>&1; }
cursor_in() { jq -e '[.hooks[][]?.command | select(contains("herdr-status-hook.sh"))] | length == 4' "$tmp/home/.cursor/hooks.json" >/dev/null 2>&1; }

# Only Cursor here: its hook goes in, Claude Code's is skipped and ~/.claude isn't made.
fresh .cursor; out=$(run "$tmp/bin"); code=$?
[ $code -eq 0 ] && cursor_in && [ ! -e "$tmp/home/.claude" ] && ok "only Cursor: Cursor's hook, nothing for Claude" || fail "only Cursor" "exit $code: $out"
case $out in *"Claude Code: not found"*) ok "only Cursor: says Claude was skipped" ;; *) fail "only Cursor: says Claude was skipped" "$out" ;; esac
case $out in *"hc report"*) fail "hc with report: no warning" "$out" ;; *) ok "hc with report: no warning" ;; esac

# Both: both hooks.
fresh .cursor .claude; out=$(run "$tmp/bin"); code=$?
[ $code -eq 0 ] && cursor_in && claude_in && ok "both: both hooks" || fail "both: both hooks" "exit $code: $out"

# Uninstall: both gone.
out=$(run "$tmp/bin" --uninstall); code=$?
! cursor_in && ! claude_in && [ ! -e "$tmp/home/.cursor/herdr-status-hook.sh" ] && [ ! -e "$tmp/home/.claude/hooks/herdr-background-waiting-hook.sh" ] &&
  ok "uninstall: both removed" || fail "uninstall: both removed" "exit $code: $out"

# An hc without `report`: hooks installed anyway, and a warning that says what to do.
fresh .cursor .claude; out=$(run "$tmp/old"); code=$?
[ $code -eq 0 ] && cursor_in && claude_in && ok "old hc: hooks installed" || fail "old hc: hooks installed" "exit $code: $out"
case $out in *"WARNING"*"hc report"*"herdr-core/releases"*) ok "old hc: warns, with where to get it" ;; *) fail "old hc: warns, with where to get it" "$out" ;; esac

# No agent at all: nothing to do, said plainly.
fresh; out=$(run "$tmp/bin"); code=$?
[ $code -eq 0 ] && [ ! -e "$tmp/home/.cursor" ] && [ ! -e "$tmp/home/.claude" ] && ok "no agents: nothing installed" || fail "no agents" "exit $code: $out"
case $out in *"nothing installed"*) ok "no agents: says so" ;; *) fail "no agents: says so" "$out" ;; esac

# No hc: refuses before touching anything.
fresh .cursor; out=$(run "$tmp/none"); code=$?
[ $code -ne 0 ] && [ ! -e "$tmp/home/.cursor/hooks.json" ] && ok "no hc: refuses" || fail "no hc: refuses" "exit $code: $out"

[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
