# Windows (WSL) Setup

These dotfiles run inside WSL (Windows Subsystem for Linux). The bootstrap script installs packages and symlinks configs into the WSL home directory.

## Prerequisites

- WSL 2 installed with Ubuntu (recommended) or another supported distro
- A [Nerd Font](https://ohmyposh.dev/docs/installation/fonts) installed on Windows and set in Windows Terminal

## Install

Open a WSL terminal and run:

```bash
git clone https://github.com/lfarci/dotfiles.git ~/dotfiles
cd ~/dotfiles
./bootstrap.sh
```

Restart your terminal for all changes to take effect.

## What gets installed

- Packages from `packages/apt.txt` via `apt`
- [Oh My Posh](https://ohmyposh.dev) prompt to `~/.local/bin`

## What gets symlinked

| Source | Destination |
|--------|-------------|
| `config/bash/.bashrc` | `~/.bashrc` |
| `config/bash/.bash_aliases` | `~/.bash_aliases` |
| `config/git/.gitconfig` | `~/.gitconfig` |
| `config/ohmyposh/theme.omp.json` | `~/.config/ohmyposh/theme.omp.json` |

## Notes

- Run `source ~/.bashrc` or restart the terminal after the first install.
- The `cdc` and `cdr` aliases navigate to common Windows paths under `/mnt/c`.
- Git identity overrides (work vs personal) go in `~/.gitconfig.local`, which is included automatically.
