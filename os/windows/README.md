# Windows Setup

Two phases: first bootstrap the native Windows environment with `bootstrap.ps1`, then set up WSL separately using `bootstrap.sh`.

## Phase 1 — Windows (PowerShell)

### Prerequisites

- Windows 10 (build 1903+) or Windows 11
- **Git** — required to clone this repository. `bootstrap.ps1` installs Git via
  winget, but that happens *after* the clone, so install Git first:

  ```powershell
  winget install --id Git.Git --exact --accept-source-agreements --accept-package-agreements
  ```

  (Alternatively, download the repository as a ZIP and extract it.)
- **winget** — ships with [App Installer](https://apps.microsoft.com/detail/9nblggh4nns1) (pre-installed on Windows 11)
- **PowerShell** — either **Windows PowerShell 5.1** (built into Windows) or
  **PowerShell 7+**. `bootstrap.ps1` requires PowerShell 5.1 or later.
  PowerShell 7 is *not* installed by the bootstrap; install it yourself if you
  want to use it:

  ```powershell
  winget install --id Microsoft.PowerShell --exact --accept-source-agreements --accept-package-agreements
  ```
- **Symbolic link capability** — either:
  - Enable Developer Mode: **Settings → System → For developers → Developer Mode**
  - Or run PowerShell as Administrator

### Install

Clone the repository, then run the bootstrap with the invocation that matches
your PowerShell edition. The `-ExecutionPolicy Bypass` flag runs the script even
when your execution policy would otherwise block it.

**Windows PowerShell 5.1** (built into Windows — no extra install needed):

```powershell
git clone https://github.com/lfarci/dotfiles.git $HOME\dotfiles
cd $HOME\dotfiles
powershell -ExecutionPolicy Bypass -File .\bootstrap.ps1
```

**PowerShell 7+ (`pwsh`)** — only if you installed PowerShell 7 as described above:

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

The authoritative list is `packages/winget.txt`; the table mirrors it.

| Package | winget ID |
|---------|-----------|
| Git | `Git.Git` |
| GitHub CLI | `GitHub.cli` |
| Visual Studio Code | `Microsoft.VisualStudioCode` |
| Windows Terminal | `Microsoft.WindowsTerminal` |
| Azure CLI | `Microsoft.AzureCLI` |
| Node.js LTS | `OpenJS.NodeJS.LTS` |
| Oh My Posh | `JanDeDobbeleer.OhMyPosh` |
| ripgrep | `BurntSushi.ripgrep.MSVC` |
| Terraform | `Hashicorp.Terraform` |
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
| `config/agents/skills` | `~\.copilot\skills` |
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

## Updating

Use the same invocation as installation, matching your PowerShell edition.

**Windows PowerShell 5.1:**

```powershell
cd $HOME\dotfiles
git pull --ff-only
powershell -ExecutionPolicy Bypass -File .\bootstrap.ps1
```

**PowerShell 7+ (`pwsh`):**

```powershell
cd $HOME\dotfiles
git pull --ff-only
pwsh -ExecutionPolicy Bypass -File .\bootstrap.ps1
```

Then repeat `git pull` + `./bootstrap.sh` inside WSL for the Linux side.
Both bootstraps are idempotent — re-running is safe. Config files are
symlinked, so edits to `config/` (including a `git pull` that changes them)
apply immediately; re-run a bootstrap only when symlink mappings, packages,
extensions, or skills change.

## Notes

- Git identity overrides (work vs personal) go in `~/.gitconfig.local`, which is included automatically.
- The `bootstrap.ps1` backs up any pre-existing config files to `~/.dotfiles_backup_<timestamp>/`.
- Windows Terminal changes should be made in `config/windows-terminal/settings.json` so they stay in the repo.
