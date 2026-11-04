#!/bin/sh
# Installs the Claude Code Stop hook that reports background shells to Herdr as a `bg`
# record: copies it to ~/.claude/hooks/ and adds one Stop entry to ~/.claude/settings.json
# (kept beside your own hooks; the old file is saved as settings.json.bak-pre-bg-hook).
# Running it again updates the hook. `install.sh --uninstall` removes both.
# Needs jq, and hc on PATH (or HERDR_HC=/path/to/hc). Honors CLAUDE_CONFIG_DIR.
set -eu
src=$(cd "$(dirname "$0")" && pwd)/herdr-background-waiting-hook.sh
home=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
hook="$home/hooks/herdr-background-waiting-hook.sh"
cfg="$home/settings.json"
command -v jq >/dev/null || { echo "install.sh: needs jq" >&2; exit 1; }
# Our entry, found by the hook's path wherever it sits in the command.
ours='[.hooks.Stop[]?.hooks[]?.command // empty | select(contains($h))] | length > 0'

if [ "${1:-}" = --uninstall ]; then
  if [ -f "$cfg" ] && jq -e --arg h "$hook" "$ours" "$cfg" >/dev/null; then
    cp -p "$cfg" "$cfg.bak-pre-bg-hook-uninstall"
    jq --arg h "$hook" '.hooks.Stop |= (map(.hooks |= map(select((.command // "") | contains($h) | not))) | map(select(.hooks | length > 0)))
      | if (.hooks.Stop | length) == 0 then del(.hooks.Stop) else . end' "$cfg" > "$cfg.tmp"
    cat "$cfg.tmp" > "$cfg" && rm -f "$cfg.tmp"
  fi
  rm -f "$hook"
  echo "removed the hook from $cfg"
  exit 0
fi

hc=${HERDR_HC:-$(command -v hc || true)}
[ -n "$hc" ] && [ -x "$hc" ] || { echo "install.sh: hc not found (set HERDR_HC=/path/to/hc)" >&2; exit 1; }
"$hc" report --help >/dev/null 2>&1 || echo "note: $hc has no 'hc report' (herdr-core#81); the hook stays inert until it does" >&2
mkdir -p "$home/hooks"
cp "$src" "$hook.new" && chmod 755 "$hook.new" && mv -f "$hook.new" "$hook"
[ -f "$cfg" ] || echo '{}' > "$cfg"
if jq -e --arg h "$hook" "$ours" "$cfg" >/dev/null; then
  echo "updated $hook (already in $cfg)"
else
  cp -p "$cfg" "$cfg.bak-pre-bg-hook"
  jq --arg c "HERDR_HC=$hc $hook" '.hooks.Stop = ((.hooks.Stop // []) + [{"hooks": [{"type": "command", "command": $c}]}])' "$cfg" > "$cfg.tmp"
  cat "$cfg.tmp" > "$cfg" && rm -f "$cfg.tmp" # keeps the file's owner and mode
  echo "installed: HERDR_HC=$hc $hook"
fi
echo "New Claude Code sessions use it; restart running ones (or check /hooks)."
