#!/bin/sh
# Installs every hook this mod ships, for each agent found on this machine:
#   Claude Code (~/.claude, or claude on PATH)        claude-code/install.sh
#   Cursor Agent CLI (~/.cursor, or cursor-agent on PATH)   cursor/install.sh
# Run it on every machine where those agents run. `install.sh --uninstall`
# removes them all. Needs jq, and hc on PATH (or HERDR_HC=/path/to/hc).
# The hooks need `hc report` (herdr-core#81); without it they are installed but
# report nothing, and this says so at the end.
set -u
here=$(cd "$(dirname "$0")" && pwd)
release=https://github.com/zztalker/herdr-core/releases/tag/0.1.19-report.1

if [ "${1:-}" != --uninstall ]; then
  HERDR_HC=${HERDR_HC:-$(command -v hc || true)}
  [ -n "$HERDR_HC" ] && [ -x "$HERDR_HC" ] || { echo "install.sh: hc not found (set HERDR_HC=/path/to/hc)" >&2; exit 1; }
  export HERDR_HC
fi

found=0 failed=0
# agent <name> <config dir> <program> <installer>
agent() {
  if [ -d "$2" ] || command -v "$3" >/dev/null 2>&1; then
    found=1
    echo "== $1"
    sh "$here/$4" $ARG || failed=1
  else
    echo "== $1: not found ($2, $3), skipped"
  fi
}
ARG=${1:-}
agent "Claude Code" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" claude claude-code/install.sh
agent "Cursor" "${CURSOR_CONFIG_DIR:-$HOME/.cursor}" cursor-agent cursor/install.sh
[ "$found" = 1 ] || echo "No Claude Code or Cursor on this machine: nothing installed."

if [ -z "$ARG" ] && [ "$found" = 1 ] && ! "$HERDR_HC" report --help >/dev/null 2>&1; then
  cat >&2 <<EOF

WARNING: $HERDR_HC has no 'hc report', so these hooks report nothing yet.
'hc report' is in herdr-core#81 (https://github.com/herdrdev/herdr-core/pull/81),
not in a herdr-core release. Until it is, install a build with it:
  $release
Then check with: hc report --help
EOF
fi
exit $failed
