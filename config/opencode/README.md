# opencode

OpenCode user configuration tracked as the source of truth for
`~/.config/opencode/`. Both bootstraps symlink the tracked files into place, so
editing the live files — or letting OpenCode write them (`opencode mcp add
--global`, the TUI settings dialog) — lands in this directory and shows up in
`git status` immediately.

## Files

- `opencode.json` — global OpenCode configuration: default model, permissions,
  MCP servers, agents, formatters, and so on. It applies to every project for
  this user. Tracked content is the published `$schema` reference plus whatever
  settings accumulate.
- `cli.json` — terminal (TUI) preferences such as theme and keybinds. This is a
  separate surface from `opencode.json` and is written by the TUI itself.

## Machine-local state (never tracked)

- `service.json` in `~/.config/opencode/` — the background-service auth token
  OpenCode generates per machine. The bootstraps link individual files rather
  than the directory precisely so this file, and any future generated state,
  stays outside the repository and is never moved by a re-run.
- `~/.local/state/opencode/` and `~/.local/share/opencode/` — runtime state,
  sessions, logs, and the database. Never linked or tracked.

## Skills

OpenCode discovers global skills from `~/.agents/skills` as a compatibility
source, and `~/.agents` is already symlinked to the vendored store in
`config/agents/`. Do not copy or link skills into this directory; it would
shadow the store for no benefit.

## Future surfaces

Custom agents, commands, and plugins live in dedicated directories under
`~/.config/opencode/` (for example `agent/`, `command/`, `plugin/`). When one
starts being used, add a symlink mapping to both `bootstrap.sh` and
`bootstrap.ps1`, and list it in the symlink tables in `os/*/README.md`.

On Windows, OpenCode reads the same `%USERPROFILE%\.config\opencode` location,
matching the `~/.config` convention `bootstrap.ps1` already uses for
oh-my-posh.
