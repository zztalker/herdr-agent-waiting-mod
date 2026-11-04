# herdr-agent-waiting-mod

A [Herdr](https://herdr.dev) mod, [`agents-waiting`](agent-waiting/RECIPE.md), and the Claude Code hook that feeds it.

Claude Code ends its turn as `done` even while its `run_in_background` shells are still running. With this mod Herdr's agents list has a **Waiting** section: an agent you've already seen, at rest, with background work still running. A new finish still shows as Done first.

![Agent Waiting](agent-waiting/preview.png)

## Install

Ask an agent in Herdr to add `github.com/zztalker/herdr-agent-waiting-mod/tree/main/agent-waiting`, or follow [Use it](agent-waiting/RECIPE.md#use-it). In short:

1. An hc with `hc report`: [herdrdev/herdr-core#81](https://github.com/herdrdev/herdr-core/pull/81), not released yet. Until then: [herdr-core 0.1.18 + hc report](https://github.com/zztalker/herdr-core/releases/tag/0.1.18-report.1).
2. The hook, wherever Claude Code runs: `sh agent-waiting/hooks/claude-code/install.sh` (`--uninstall` removes it).
3. The mod: copy `agent-waiting/mods/agents-waiting/` to `~/.config/herdr-app/mods/` and point your layout's agents block at `agents-waiting`.

What it runs: the mod, nothing (it reads `agents()` and `terminals()`). The hook runs `jq` and `hc report` and edits `~/.claude/settings.json` only through `install.sh`. No network.

## License

Apache-2.0 (see `LICENSE`). `agents-waiting` is modified from Herdr's shipped `agents` mod (Apache-2.0); the changes are marked `waiting:` in the source.
