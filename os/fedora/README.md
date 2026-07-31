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

## Notes

- Run `source ~/.bashrc` or restart the terminal after the first install.
- Git identity overrides (work vs personal) go in `~/.gitconfig.local`, which is included automatically.
- VS Code is not installed by `packages/dnf.txt`; bootstrap warns and skips extensions when `code` is unavailable.
