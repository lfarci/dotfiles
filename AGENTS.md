# AGENTS.md

Personal dotfiles. `config/` is the **source of truth**: the bootstraps symlink
it into `$HOME`, so the tracked files *are* the live files. Editing `~/.bashrc`
edits `config/bash/.bashrc` and shows up in `git status` immediately. Change the
repo file, never the link target.

## Layout

| Path | Purpose |
| --- | --- |
| `bootstrap.sh` | Linux/WSL entrypoint (Bash) |
| `bootstrap.ps1` | Windows entrypoint (PowerShell 5.1+) |
| `os/<os>/install.sh` | per-OS package/tool installers sourced by `bootstrap.sh` |
| `packages/` | package manifests: `apt.txt`, `dnf.txt`, `winget.txt` |
| `config/` | tracked dotfiles, symlinked into `$HOME` |
| `scripts/` | repo-maintained helper scripts (`update.sh`, `cleanup.sh`) |
| `config/powershell/` | PowerShell profile helpers (`helpers.ps1`), dot-sourced from the profile |
| `config/agents/` | vendored skills store — see `config/agents/AGENTS.md` |
| `tests/` | assertion suites — see `tests/AGENTS.md` |
| `os/` | OS installers + Dockerfiles — see `os/AGENTS.md` |
| `docs/` | CI/linting references; design specs in `docs/superpowers/specs/` |
| `plan/` | implementation plans |
| `.github/workflows/` | CI |

## Bootstrap invariants

These are load-bearing; preserve them in any change.

- **Idempotent and safe to re-run.** A correct symlink is left alone; only new
  mappings/packages/extensions/skills require a re-run. Content edits take
  effect without one.
- **Back up, never delete.** A destination that is not already the correct
  symlink is moved to `~/.dotfiles_backup_<timestamp>/` before linking. If the
  backup cannot be created or the move fails, leave the destination untouched
  and skip the link — never delete it as a fallback.
- **`bootstrap.sh` refuses to run as root** unless `DOTFILES_ALLOW_ROOT=1`.
- **Bash and PowerShell stay in parity.** `bootstrap.sh` and `bootstrap.ps1`
  implement the same behavior (manifest parsing, extension install, backup/link,
  skills restore). A change to one usually needs the matching change in the
  other.
- **Optional steps warn and continue; contract steps fail.** Use the existing
  `log`/`warn` (Bash) and `Log`/`Warn` (PowerShell) helpers. Missing tools such
  as `npx` and `code` on native Linux warn and skip; a missing `code` on
  Windows/WSL is actionable and fails.
- **Link mappings are explicit.** Bash: `link_all`'s `link_mappings` list.
  PowerShell: `Link-All`'s `$mappings` array. Keep the **shared** mappings in
  sync across both (git, oh-my-posh, VS Code, `config/agents`, Claude) — but
  the platform-specific ones are deliberate: Bash links `.bashrc`,
  `.bash_aliases`, `.inputrc`, and Ghostty; PowerShell links Windows Terminal
  settings. Destinations also legitimately differ per OS (e.g. VS Code lives
  under `~/.config/Code/User` on Linux, `$env:APPDATA\Code\User` on Windows).

## Line endings

`.gitattributes` normalizes text to LF. `*.sh`, `*.bash`, `*.ps1`,
`config/bash/.bashrc`, `config/bash/.bash_aliases`, and `.shellcheckrc` are
pinned to `eol=lf` because CRLF breaks ShellCheck (`SC1017`) or Linux execution.
`config/agents/**` is deliberately left to `text=auto` — do **not** add
`-text` or `eol=lf` there (see `config/agents/AGENTS.md`).

## Verify before committing

```bash
# Bash syntax + maintained ShellCheck scope (keep in sync with CI)
bash -n bootstrap.sh os/windows/install.sh os/ubuntu/install.sh os/fedora/install.sh \
  scripts/update.sh scripts/cleanup.sh
shellcheck --severity=warning \
  bootstrap.sh os/ubuntu/install.sh os/fedora/install.sh os/windows/install.sh \
  scripts/update.sh scripts/cleanup.sh \
  tests/bootstrap-vscode-extensions.bash tests/fixtures/code-stub.bash

# Assertion suites (see tests/AGENTS.md for the full set)
bash tests/bootstrap-backup.bash
bash tests/bootstrap-vscode-extensions.bash
bash tests/skills-inventory-consistency.bash
```

```powershell
# Maintained PowerShell lint scope (PSScriptAnalyzer 1.25.0)
Invoke-ScriptAnalyzer -Path bootstrap.ps1 -Settings ./PSScriptAnalyzerSettings.psd1
Invoke-ScriptAnalyzer -Path config/powershell/helpers.ps1 -Settings ./PSScriptAnalyzerSettings.psd1
Invoke-ScriptAnalyzer -Path scripts/update.ps1 -Settings ./PSScriptAnalyzerSettings.psd1
Invoke-ScriptAnalyzer -Path scripts/cleanup.ps1 -Settings ./PSScriptAnalyzerSettings.psd1
Invoke-ScriptAnalyzer -Path tests/bootstrap-vscode-extensions.Tests.ps1 -Settings ./PSScriptAnalyzerSettings.psd1
```

`docs/linting.md` and `docs/ci.md` document the scope and workflow mapping; keep
them updated when the lint file list or CI wiring changes. New suites need a
workflow (see `tests/AGENTS.md`).

## Conventions

- Package lists are one item per line in `packages/*.txt`; `#` starts a comment
  and blank lines are ignored. VS Code extensions follow the same manifest shape
  in `config/vscode/extensions.txt`, parsed by both entrypoints.
- Keep unrelated working-tree changes out of your commit. When a change is
  intentionally broader than the task, say so.
- **Skill refreshes are reviewed separately from bootstrap changes.** One
  refresh per PR with the lock diff and content diff together; never let a
  bootstrap/symlink change ride along with a refresh. See
  `config/agents/AGENTS.md`.
