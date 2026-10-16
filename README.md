# Dotfiles

Personal dotfiles for bash, git, terminal prompt (Oh My Posh), VS Code, and
OpenCode.

VS Code settings and keybindings live under `config/vscode/`. Both bootstrap
entrypoints install the extensions declared in `config/vscode/extensions.txt`
when the VS Code CLI is available.

OpenCode configuration lives under `config/opencode/`, and `bootstrap.sh`
installs the OpenCode CLI when `curl` is available.

## Setup

- [Windows](os/windows/README.md)
- [Ubuntu](os/ubuntu/README.md)
- [Fedora](os/fedora/README.md)

## Updating

`config/` is the source of truth and both bootstraps **symlink** it into `$HOME`,
so the live files are the tracked files — editing `~/.bashrc` edits
`config/bash/.bashrc` and shows up in `git status` immediately.

To pull changes on an existing machine:

```bash
cd ~/dotfiles        # or $HOME\dotfiles on Windows
git pull --ff-only
./bootstrap.sh       # bootstrap.ps1 on Windows
```

The same flow is available as `scripts/update.sh` (Bash) and
`scripts/update.ps1` (PowerShell). Each refuses to run unless the checkout is on
the expected branch with a clean working tree, then runs `git pull --ff-only`
and the platform bootstrap. See `scripts/update.sh --help` or
`.\scripts\update.ps1 -Help`.

To reclaim disk space, `scripts/cleanup.sh` (Bash, `--apply`) and
`scripts/cleanup.ps1` (PowerShell, `-Apply`) list stale `~/.dotfiles_backup_*`
directories older than a configurable age and only delete them when explicitly
asked; both are a dry run by default. See `scripts/cleanup.sh --help` or
`.\scripts\cleanup.ps1 -Help`.

Re-running the bootstrap is safe and idempotent: correct symlinks are left
alone, and anything else is backed up to `~/.dotfiles_backup_<timestamp>/`
before being re-linked. Only re-run it after changes to *what* gets installed
or linked — new symlink mappings, packages, VS Code extensions, or skills.
Changes to the *contents* of already-linked files take effect as soon as you
edit or pull them, with no bootstrap needed.

### Linting

CI runs separate ShellCheck and PSScriptAnalyzer workflows for maintained
scripts. See [`docs/linting.md`](docs/linting.md) for the scope, configuration,
and local commands.

### Testing

`tests/` holds offline assertion suites for the bootstrap entrypoints and the
update/cleanup scripts. A Python end-to-end harness drives the **real** scripts
against throwaway `$HOME` directories and local git remotes:

```bash
python3 tests/e2e/run_update_cleanup.py                       # .sh scripts
python3 tests/e2e/run_update_cleanup.py --platform windows    # .ps1 scripts (needs pwsh)
```

See [`tests/AGENTS.md`](tests/AGENTS.md) for the suites and
[`docs/ci.md`](docs/ci.md) for how they run in CI.

### Line endings

`.gitattributes` normalizes text to LF in the repository and forces `*.sh`,
`*.bash`, `*.ps1`, `config/bash/.bashrc` and `config/bash/.bash_aliases` to
check out with LF even when `core.autocrlf=true`. CRLF in these files breaks
ShellCheck (`SC1017`) and can make a script fail to run under WSL. If a script was checked out before these rules existed, its worktree copy is
still CRLF and ShellCheck reports `SC1017` for it. Refresh the affected files
(deleting forces git to re-checkout using the new attributes):

```powershell
Remove-Item bootstrap.sh, .shellcheckrc; git checkout -- bootstrap.sh .shellcheckrc
```
`config/agents/` is intentionally left to `* text=auto` rather than being
marked `-text`: those files are owned upstream and marking the tree binary would
report every vendored file as modified on a CRLF worktree.

### Skills

Skills are installed straight into the repo: `~/.agents` and `~/.copilot/skills`
are symlinks into `config/agents`. Install and update them with the skills CLI
so `.skill-lock.json` stays in sync, then commit both together:

```bash
npx skills add <source> --skill <name> --yes --global
npx skills update
git add config/agents
git commit -m "Add <skill> skill"
```

Committing `config/agents/skills/` without the matching `.skill-lock.json`
change means the skill will not be restored on a fresh machine. The two
inventories are checked by name (not just by count) so an orphaned lock entry
cannot hide behind an unlocked skill directory:

```bash
node tests/skills-inventory-consistency.mjs
```

Skills are vendored on purpose, and skill refreshes are reviewed separately from
bootstrap changes. See [`config/agents/README.md`](config/agents/README.md) for
the provenance and maintenance policy.
