# Windows Setup

Two phases: first bootstrap the native Windows environment with `bootstrap.ps1`, then set up WSL separately using `bootstrap.sh`.

## Phase 1 — Windows (PowerShell)

### Prerequisites

- Windows 10 (build 1903+) or Windows 11
- **winget** — ships with [App Installer](https://apps.microsoft.com/detail/9nblggh4nns1) (pre-installed on Windows 11)
- **Symbolic link capability** — either:
  - Enable Developer Mode: **Settings → System → For developers → Developer Mode**
  - Or run PowerShell as Administrator

### Install

Open **PowerShell 7 (`pwsh`)** (recommended) or Windows PowerShell 5.1 and run:

```powershell
git clone https://github.com/lfarci/dotfiles.git $HOME\dotfiles
cd $HOME\dotfiles
pwsh -ExecutionPolicy Bypass -File .\bootstrap.ps1
```

Restart your terminal when done.

The bootstrap refreshes its process `PATH` after winget finishes and then
installs the extensions declared in `config\vscode\extensions.txt`. If VS Code
was installed but `code` is still unavailable, reopen PowerShell and rerun the
bootstrap.

### What gets installed (via winget)

| Package | winget ID |
|---------|-----------|
| Git | `Git.Git` |
| Visual Studio Code | `Microsoft.VisualStudioCode` |
| Windows Terminal | `Microsoft.WindowsTerminal` |
| Node.js LTS | `OpenJS.NodeJS.LTS` |
| Oh My Posh | `JanDeDobbeleer.OhMyPosh` |
| ripgrep | `BurntSushi.ripgrep.MSVC` |
| fzf | `junegunn.fzf` |
| eza | `eza-community.eza` |

### What gets configured

- **JetBrainsMono Nerd Font** installed (user-level, no admin needed)
- **Oh My Posh** added to both PowerShell 5.1 and PowerShell 7 profiles
- **VS Code extensions** installed from `config\vscode\extensions.txt`
- Config files symlinked:

| Source | Destination |
|--------|-------------|
| `config/git/.gitconfig` | `~\.gitconfig` |
| `config/git/.gitignore_global` | `~\.gitignore_global` |
| `config/ohmyposh/theme.omp.json` | `~\.config\ohmyposh\theme.omp.json` |
| `config/vscode/settings.json` | `%APPDATA%\Code\User\settings.json` |
| `config/vscode/keybindings.json` | `%APPDATA%\Code\User\keybindings.json` |
| `config/windows-terminal/settings.json` | Windows Terminal `settings.json` |
| `config/agents` | `~\.agents` |
| `config/claude/settings.json` | `~\.claude\settings.json` |

### Windows Terminal settings

`bootstrap.ps1` now links the repo-managed Windows Terminal settings file into the active Windows Terminal settings location. It checks the stable Store path first, then Preview, then the unpackaged path under `%LOCALAPPDATA%`.

The tracked file already keeps `JetBrainsMono Nerd Font` configured for the current profiles.

---

## Phase 2 — WSL

Once the Windows environment is set up, install WSL and run `bootstrap.sh` inside it:

```bash
# In a WSL terminal
git clone https://github.com/lfarci/dotfiles.git ~/dotfiles
cd ~/dotfiles
./bootstrap.sh
```

See the [WSL docs](https://learn.microsoft.com/en-us/windows/wsl/install) for installing WSL.

The WSL phase uses the Windows `code` CLI exposed inside WSL. Extensions that
affect the VS Code interface, including color and icon themes, are installed on
the Windows side. The PowerShell phase links the tracked settings into
`%APPDATA%\Code\User`, so run the Windows phase before the WSL phase. If `code`
is unavailable inside WSL, reopen the terminal after installing VS Code and
rerun `bootstrap.sh`.

## Notes

- Git identity overrides (work vs personal) go in `~/.gitconfig.local`, which is included automatically.
- The `bootstrap.ps1` backs up any pre-existing config files to `~/.dotfiles_backup_<timestamp>/`.
- Windows Terminal changes should be made in `config/windows-terminal/settings.json` so they stay in the repo.
