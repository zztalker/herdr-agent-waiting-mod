#!/bin/sh
# sh agent-waiting/hooks/cursor/install.test.sh
# Runs install.sh against a throwaway Cursor folder (CURSOR_CONFIG_DIR) with fake hc's.
set -u
here=$(cd "$(dirname "$0")" && pwd)
inst="$here/install.sh"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fails=0
ok() { echo "ok   $1"; }
fail() { echo "FAIL $1: $2"; fails=$((fails + 1)); }

# A fake hc with `report` (records its args) and one without it.
mkdir -p "$tmp/bin"
cat > "$tmp/bin/hc" <<'FAKE'
#!/bin/sh
[ "$1" = report ] && [ "${2:-}" = --help ] && exit 0
printf '%s\n' "$*" >> "$FAKE_LOG"
FAKE
printf '#!/bin/sh\necho "error: unrecognized subcommand" >&2; exit 2\n' > "$tmp/bin/hc-old"
chmod +x "$tmp/bin/hc" "$tmp/bin/hc-old"
export FAKE_LOG="$tmp/log"

export CURSOR_CONFIG_DIR="$tmp/cursor"
cfg="$CURSOR_CONFIG_DIR/hooks.json"
hook="$CURSOR_CONFIG_DIR/herdr-status-hook.sh"
mkdir -p "$CURSOR_CONFIG_DIR"
# Someone's own hooks (the TUI's sessionStart, an unrelated stop) and a key of theirs.
cat > "$cfg" <<'JSON'
{"version": 1, "mine": true, "hooks": {
  "sessionStart": [{"command": "bash '/x/herdr-agent-state.sh' session"}],
  "stop": [{"command": "say done", "timeout": 3}]}}
JSON
before=$(jq -S . "$cfg")

# 1. Install: the four entries, after theirs, with hc pinned; their hooks and keys kept.
out=$(HERDR_HC="$tmp/bin/hc" sh "$inst" 2>&1); code=$?
[ $code -eq 0 ] || fail "install exits 0" "exit $code: $out"
[ -x "$hook" ] && cmp -s "$hook" "$here/status-hook.sh" && ok "the hook is copied" || fail "the hook is copied" "$(ls -l "$hook" 2>&1)"
for e in sessionStart:start beforeSubmitPrompt:prompt stop:stop sessionEnd:end; do
  ev=${e%:*} act=${e#*:}
  n=$(jq --arg h "$hook" --arg e "$ev" '[.hooks[$e][] | select(.command | contains($h))] | length' "$cfg")
  last=$(jq -r --arg e "$ev" '.hooks[$e][-1].command' "$cfg")
  want="HERDR_HC='$tmp/bin/hc' sh '$hook' $act"
  [ "$n" = 1 ] && [ "$last" = "$want" ] && ok "$ev: one entry, last, $act" || fail "$ev entry" "n=$n last=$last want=$want"
done
[ "$(jq -r '.hooks.sessionStart[0].command' "$cfg")" = "bash '/x/herdr-agent-state.sh' session" ] && [ "$(jq -r '.hooks.stop[0].command' "$cfg")" = "say done" ] &&
  [ "$(jq '.mine' "$cfg")" = true ] && [ "$(jq '.version' "$cfg")" = 1 ] && ok "their hooks and keys stay" || fail "their hooks and keys stay" "$(cat "$cfg")"
[ -f "$cfg.bak-pre-herdr-status-hook" ] && [ "$(jq -S . "$cfg.bak-pre-herdr-status-hook")" = "$before" ] && ok "the old file is kept" || fail "the old file is kept" "no backup"
case $out in *"hc report"*missing*|*missing*"hc report"*) fail "no warning with hc report" "$out" ;; *) ok "no warning with hc report" ;; esac

# 2. The installed command, run the way Cursor runs it, reports.
: > "$FAKE_LOG"
cmd=$(jq -r '.hooks.beforeSubmitPrompt[-1].command' "$cfg")
res=$(echo '{}' | HC_TERMINAL_ID=t7 sh -c "$cmd")
[ "$res" = '{"continue":true}' ] && [ "$(cat "$FAKE_LOG")" = "report state=working:app=cursor" ] && ok "the installed command reports" || fail "the installed command reports" "out=$res log=$(cat "$FAKE_LOG")"

# 3. Again: the same file, nothing doubled.
first=$(cat "$cfg")
HERDR_HC="$tmp/bin/hc" sh "$inst" > /dev/null 2>&1
[ "$(cat "$cfg")" = "$first" ] && ok "installing again changes nothing" || fail "installing again changes nothing" "$(cat "$cfg")"

# 4. Uninstall: back to what they had (empty event lists dropped), the hook gone.
sh "$inst" --uninstall > /dev/null 2>&1
[ "$(jq -S . "$cfg")" = "$before" ] && [ ! -e "$hook" ] && ok "uninstall restores their file" || fail "uninstall restores their file" "$(cat "$cfg")"

# 5. An hc without `report`: installed anyway, and it says so.
out=$(HERDR_HC="$tmp/bin/hc-old" sh "$inst" 2>&1); code=$?
[ $code -eq 0 ] && [ -x "$hook" ] && ok "old hc: still installs" || fail "old hc: still installs" "exit $code"
case $out in *"hc report"*) ok "old hc: warns about hc report" ;; *) fail "old hc: warns about hc report" "$out" ;; esac
sh "$inst" --uninstall > /dev/null 2>&1

# 6. No hc at all: refuses, changes nothing.
out=$(PATH=/usr/bin:/bin HERDR_HC= sh "$inst" 2>&1); code=$?
[ $code -ne 0 ] && [ "$(jq -S . "$cfg")" = "$before" ] && [ ! -e "$hook" ] && ok "no hc: refuses" || fail "no hc: refuses" "exit $code: $out"

# 7. No hooks.json yet: one is made.
rm -f "$cfg"
HERDR_HC="$tmp/bin/hc" sh "$inst" > /dev/null 2>&1
[ "$(jq '.version' "$cfg")" = 1 ] && [ "$(jq '.hooks | keys | length' "$cfg")" = 4 ] && ok "no hooks.json: one is made" || fail "no hooks.json: one is made" "$(cat "$cfg" 2>&1)"

[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
