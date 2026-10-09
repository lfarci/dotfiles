# Dotfiles

Personal dotfiles for bash, git, terminal prompt (Oh My Posh), and VS Code.

VS Code settings and keybindings live under `config/vscode/`. Both bootstrap
entrypoints install the extensions declared in `config/vscode/extensions.txt`
when the VS Code CLI is available.

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

Re-running the bootstrap is safe and idempotent: correct symlinks are left
alone, and anything else is backed up to `~/.dotfiles_backup_<timestamp>/`
before being re-linked. Only re-run it after changes to *what* gets installed
or linked — new symlink mappings, packages, VS Code extensions, or skills.
Changes to the *contents* of already-linked files take effect as soon as you
edit or pull them, with no bootstrap needed.

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
change means the skill will not be restored on a fresh machine.

Skills are vendored on purpose, and skill refreshes are reviewed separately from
bootstrap changes. See [`config/agents/README.md`](config/agents/README.md) for
the provenance and maintenance policy.
