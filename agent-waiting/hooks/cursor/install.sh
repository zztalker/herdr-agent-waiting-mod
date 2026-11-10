#!/bin/sh
# Installs the Cursor Agent CLI status hook: copies status-hook.sh to
# ~/.cursor/herdr-status-hook.sh and adds its sessionStart, beforeSubmitPrompt,
# stop and sessionEnd entries to ~/.cursor/hooks.json, after your own hooks
# (the old file is saved as hooks.json.bak-pre-herdr-status-hook). Running it
# again updates the hook. `install.sh --uninstall` removes both.
# Needs jq, and hc on PATH (or HERDR_HC=/path/to/hc). Honors CURSOR_CONFIG_DIR.
set -eu
src=$(cd "$(dirname "$0")" && pwd)/status-hook.sh
home=${CURSOR_CONFIG_DIR:-$HOME/.cursor}
hook="$home/herdr-status-hook.sh"
cfg="$home/hooks.json"
command -v jq >/dev/null || { echo "install.sh: needs jq" >&2; exit 1; }
# Our entries, found by the hook's path wherever it sits in the command.
drop='.hooks |= with_entries(.value |= map(select((.command // "") | contains($h) | not)))'

if [ "${1:-}" = --uninstall ]; then
  if [ -f "$cfg" ] && jq -e --arg h "$hook" '[.hooks[]?[]?.command // empty | select(contains($h))] | length > 0' "$cfg" >/dev/null; then
    cp -p "$cfg" "$cfg.bak-pre-herdr-status-hook-uninstall"
    jq --arg h "$hook" "$drop | .hooks |= with_entries(select(.value | length > 0))" "$cfg" > "$cfg.tmp"
    cat "$cfg.tmp" > "$cfg" && rm -f "$cfg.tmp"
  fi
  rm -f "$hook"
  echo "removed the Cursor hook from $cfg"
  exit 0
fi

hc=${HERDR_HC:-$(command -v hc || true)}
[ -n "$hc" ] && [ -x "$hc" ] || { echo "install.sh: hc not found (set HERDR_HC=/path/to/hc)" >&2; exit 1; }
"$hc" report --help >/dev/null 2>&1 || echo "note: $hc has no 'hc report' (herdr-core#81); the Cursor hook stays inert until it does" >&2
mkdir -p "$home"
cp "$src" "$hook.new" && chmod 755 "$hook.new" && mv -f "$hook.new" "$hook"
[ -f "$cfg" ] || echo '{"version": 1, "hooks": {}}' > "$cfg"
[ -f "$cfg.bak-pre-herdr-status-hook" ] || cp -p "$cfg" "$cfg.bak-pre-herdr-status-hook"
# Ours are taken out and put back last: running it again gives the same file.
jq --arg h "$hook" --arg hc "$hc" "
  .version //= 1 | .hooks //= {} | $drop
  | reduce ([\"sessionStart\", \"start\"], [\"beforeSubmitPrompt\", \"prompt\"], [\"stop\", \"stop\"], [\"sessionEnd\", \"end\"]) as [\$e, \$a] (.;
      .hooks[\$e] = ((.hooks[\$e] // []) + [{command: (\"HERDR_HC=\" + (\$hc | @sh) + \" sh \" + (\$h | @sh) + \" \" + \$a), timeout: 5}]))" \
  "$cfg" > "$cfg.tmp"
cat "$cfg.tmp" > "$cfg" && rm -f "$cfg.tmp" # keeps the file's owner and mode
echo "installed the Cursor hook: $hook (hc: $hc)"
echo "New Cursor sessions use it; restart running ones."
