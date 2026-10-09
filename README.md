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

### Linting

CI runs ShellCheck over the maintained Bash scripts and PSScriptAnalyzer over
the maintained PowerShell scripts (`.github/workflows/lint.yml`). Both analyzers
read a shared config from the repo root, so a local run matches CI exactly.

ShellCheck (`.shellcheckrc`) covers `bootstrap.sh`, `os/*/install.sh` and the
Bash tests. `--severity=warning` is passed on the command line because ShellCheck
does not accept `severity` as a config-file key; the rc file supplies
`external-sources` and `source-path=SCRIPTDIR:.`, which let the `source`
directives resolve so no inline suppressions are needed. Run it from the repo
root:

```bash
shellcheck --severity=warning \
  bootstrap.sh os/ubuntu/install.sh os/fedora/install.sh \
  os/windows/install.sh tests/bootstrap-vscode-extensions.bash \
  tests/fixtures/code-stub.bash
```

PSScriptAnalyzer (`PSScriptAnalyzerSettings.psd1`) covers `bootstrap.ps1` and
the Pester tests. On Windows:

```powershell
Install-Module PSScriptAnalyzer -RequiredVersion 1.25.0 -Force -Scope CurrentUser

foreach ($file in 'bootstrap.ps1', 'tests/bootstrap-vscode-extensions.Tests.ps1') {
  Invoke-ScriptAnalyzer -Path $file -Settings ./PSScriptAnalyzerSettings.psd1
}
```

`Invoke-ScriptAnalyzer` also auto-discovers `PSScriptAnalyzerSettings.psd1` from
the current directory, so run it from the repo root or pass `-Settings`
explicitly to be sure which baseline applies.

The scope is the bootstrap and test scripts only. Upstream-vendored skill content
under `config/agents/` is deliberately excluded from both analyzers — it is not
locally authored and should not be reformatted here. The five excluded
PSScriptAnalyzer rules and the two benign ShellCheck note classes are each
justified inline in the config files.

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
change means the skill will not be restored on a fresh machine.
