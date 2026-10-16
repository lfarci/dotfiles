# Fedora Setup

## Prerequisites

- Fedora 39 or later
- A [Nerd Font](https://ohmyposh.dev/docs/installation/fonts) set in your terminal emulator

## Install

```bash
git clone https://github.com/lfarci/dotfiles.git ~/dotfiles
cd ~/dotfiles
./bootstrap.sh
```

Restart your terminal for all changes to take effect.

## What gets installed

- Packages from `packages/dnf.txt` via `dnf`
- [Oh My Posh](https://ohmyposh.dev) prompt to `~/.local/bin`
- [OpenCode](https://opencode.ai) CLI to `~/.opencode/bin` via the official installer (`--no-modify-path`; `PATH` is set by `config/bash/.bashrc`)
- VS Code extensions from `config/vscode/extensions.txt` when `code` is already available

## What gets symlinked

| Source | Destination |
|--------|-------------|
| `config/bash/.bashrc` | `~/.bashrc` |
| `config/bash/.bash_aliases` | `~/.bash_aliases` |
| `config/git/.gitconfig` | `~/.gitconfig` |
| `config/ohmyposh/theme.omp.json` | `~/.config/ohmyposh/theme.omp.json` |
| `config/vscode/settings.json` | `~/.config/Code/User/settings.json` |
| `config/vscode/keybindings.json` | `~/.config/Code/User/keybindings.json` |
| `config/opencode/opencode.json` | `~/.config/opencode/opencode.json` |
| `config/opencode/themes` | `~/.config/opencode/themes` |

`config/opencode/cli.json` (theme selection) is not symlinked: it is copied to
`~/.config/opencode/cli.json` on the first bootstrap only, and the TUI owns
that file afterwards — later settings changes are not versioned. See
`config/opencode/README.md`.

## Updating

```bash
cd ~/dotfiles
git pull --ff-only
./bootstrap.sh
```

`bootstrap.sh` is idempotent — re-running it is safe. Config files are symlinked,
so edits to `config/` (including a `git pull` that changes them) apply
immediately; re-run the bootstrap only when symlink mappings, packages,
extensions, or skills change.

`scripts/update.sh` wraps this flow (`--help`): it refuses unless the checkout
is on the expected branch with a clean working tree, then runs
`git pull --ff-only` and `./bootstrap.sh`. `scripts/cleanup.sh` reclaims stale
`~/.dotfiles_backup_*` directories and deletes them only with `--apply` (dry run
by default).

## Notes

- Run `source ~/.bashrc` or restart the terminal after the first install.
- Git identity overrides (work vs personal) go in `~/.gitconfig.local`, which is included automatically.
- Git authentication overrides go there too. The tracked config uses `gh` (resolved from `PATH`) as the
  credential helper for GitHub; a machine that needs a different helper overrides it locally:
  ```gitconfig
  [credential "https://github.com"]
    helper =
    helper = store
  ```
- VS Code is not installed by `packages/dnf.txt`; bootstrap warns and skips extensions when `code` is unavailable.
- Docker is installed from Docker's official repository and the `docker` service is
  enabled and started only when systemd is running. On hosts without a running
  systemd (Docker build stages, WSL without systemd, containers) bootstrap reports
  that activation is deferred and finishes normally; start the service later with
  `sudo systemctl enable --now docker`, or enable systemd in WSL by adding
  `[boot]` / `systemd=true` to `/etc/wsl.conf` and running `wsl --shutdown`.
