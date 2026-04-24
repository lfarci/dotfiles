# Ubuntu Setup

## Prerequisites

- Ubuntu 22.04 or later
- A [Nerd Font](https://ohmyposh.dev/docs/installation/fonts) set in your terminal emulator

## Install

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
- Git identity, credential helper, and other client-specific overrides go in `~/.gitconfig.local`, which is included automatically. See `config/git/.gitconfig.local.example` for a starting point.
