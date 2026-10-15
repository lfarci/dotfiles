# opencode

OpenCode user configuration tracked as the source of truth for
`~/.config/opencode/`. Both bootstraps symlink the tracked files into place, so
editing the live files — or letting OpenCode write them (`opencode mcp add
--global`) — lands in this directory and shows up in `git status` immediately.

## Files

- `opencode.json` — global OpenCode configuration: default model, permissions,
  MCP servers, agents, formatters, and so on. It applies to every project for
  this user. Tracked content is the published `$schema` reference plus whatever
  settings accumulate.
- `themes/` — custom theme definitions, symlinked as a directory. `midnight`
  is the builtin OpenCode theme with the dark neutral ramp shifted toward the
  desktop app background (`#0f0f1d`), so the terminal UI matches the app. The
  builtin theme omits a `yellow` hue from both modes (resolved at runtime);
  the extraction preserves that.
- `cli.json` — TUI preferences, tracked as a **seed snapshot only** (see
  below). It currently preselects `midnight` in dark mode.

## CLI installation

`bootstrap.sh` installs the OpenCode CLI with the official installer when
`curl` is available, guarded by `command -v opencode` so an existing install is
left alone. It runs the installer with `--no-modify-path`: `~/.bashrc` is a
symlink to the tracked `config/bash/.bashrc`, so the installer must not edit
shell config — that file adds `~/.opencode/bin` to `PATH` instead. Installation
is Linux-only for now; Windows machines install OpenCode themselves.

## Machine-local state (never tracked)

- `service.json` in `~/.config/opencode/` — the background-service auth token
  OpenCode generates per machine. The bootstraps link individual files rather
  than the directory precisely so this file, and any future generated state,
  stays outside the repository and is never moved by a re-run.
- `~/.local/state/opencode/` and `~/.local/share/opencode/` — runtime state,
  sessions, logs, and the database. Never linked or tracked.
- `~/.config/ai.opencode.desktop/` — the desktop app's Electron home: its
  `opencode.settings` holds machine-specific window IDs on top of the Chromium
  cache, so nothing in it is portable.

## cli.json is seeded once, then owned by the TUI

The TUI persists preference changes with an atomic write that replaces the
file, so a symlink at that path is destroyed on the first settings change, and
a re-link would restore a stale copy over the live preferences. Upstream:
`anomalyco/opencode#45067`. Instead of symlinking, the bootstraps **copy the
tracked `cli.json` into place only when the destination does not exist** —
a fresh machine starts with the `midnight` theme preselected, and every later
settings change belongs to the TUI on that machine. Expect live edits to
diverge from the tracked snapshot; refresh the snapshot by hand (copy the live
file back into the repo) when a preference change is worth keeping.

## Provider connections are per machine

`opencode auth login` stores provider credentials (GitHub Copilot, OpenAI,
OpenRouter, …) outside the configuration in a machine-local store. Nothing
about them belongs in this repository: on a fresh machine, run
`opencode auth login` once per provider you use. Never put API keys in
`opencode.json`; where a header key is unavoidable, use an environment
substitution such as `{env:VAR}` instead.

## Skills

OpenCode discovers global skills from `~/.agents/skills` as a compatibility
source, and `~/.agents` is already symlinked to the vendored store in
`config/agents/`. Do not copy or link skills into this directory; it would
shadow the store for no benefit.

## Future surfaces

Custom agents, commands, and plugins live in dedicated directories under
`~/.config/opencode/`: `agents/`, `commands/`, and `plugins/` (plural — the
singular forms are legacy compatibility aliases, so new files belong in the
plural directories). When one starts being used, add a symlink mapping to both
`bootstrap.sh` and `bootstrap.ps1`, and list it in the symlink tables in
`os/*/README.md`.

On Windows, OpenCode reads the same `%USERPROFILE%\.config\opencode` location,
matching the `~/.config` convention `bootstrap.ps1` already uses for
oh-my-posh.
