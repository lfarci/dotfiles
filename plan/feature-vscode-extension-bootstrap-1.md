---
goal: Safely integrate VS Code extension installation into the current main branch
version: 1.0
date_created: 2026-07-31
last_updated: 2026-07-31
owner: lfarci
status: 'In progress'
tags: [feature, bootstrap, vscode, windows, wsl]
---

# Introduction

![Status: In progress](https://img.shields.io/badge/status-In%20progress-yellow)

This plan ports the VS Code extension-install behavior from the stale remote implementation branches onto a new branch created from current `main`, validates it on Bash and PowerShell, and merges it only after the current dirty working tree has been made safe. The source branches are references only; neither branch is merged or cherry-picked wholesale.

## 1. Requirements & Constraints

- **REQ-001**: Add `config/vscode/extensions.txt` as the single line-delimited extension manifest consumed by both bootstrap entrypoints.
- **REQ-002**: Include these extension IDs exactly once: `catppuccin.catppuccin-vsc`, `catppuccin.catppuccin-vsc-icons`, `PKief.material-icon-theme`, `ms-dotnettools.csharp`, `stackbreak.comment-divider`, `github.vscode-github-actions`, `github.vscode-pull-request-github`, `codezombiech.gitignore`, and `mermaidchart.vscode-mermaid-chart`.
- **REQ-003**: Ignore blank lines, leading and trailing whitespace, and text beginning with `#` while parsing the manifest.
- **REQ-004**: Invoke `code --install-extension <extension-id> --force` once for every parsed extension.
- **REQ-005**: Continue processing the manifest after an individual extension fails, then return a nonzero result containing every failed extension ID.
- **REQ-006**: Run extension installation in `bootstrap.ps1` after `Install-WingetPackages`, because that function installs VS Code and refreshes the process `PATH`.
- **REQ-007**: Run extension installation in `bootstrap.sh` after the OS-specific installer has been sourced and before skills restoration.
- **REQ-008**: If `code` is absent on Windows PowerShell or WSL (`OS=windows`), fail with an actionable message stating that VS Code must be installed and the terminal may need to be reopened.
- **REQ-009**: If `code` is absent on native Ubuntu or Fedora, warn and skip extension installation because `packages/apt.txt` and `packages/dnf.txt` do not install VS Code.
- **REQ-010**: Preserve the committed `workbench.colorTheme` and `workbench.iconTheme` values in `config/vscode/settings.json`; do not modify that file as part of this feature.
- **REQ-011**: Update documentation to state that VS Code UI extensions such as themes are installed locally when using WSL and that the Windows PowerShell phase configures the Windows VS Code user settings.
- **CON-001**: Do not merge `origin/copilot/implement-extension-install-plan` directly. It conflicts with the current `install_nvm_node` implementation in `bootstrap.sh` and duplicates the current design specification.
- **CON-002**: Do not merge `origin/copilot/vscode-mo8q6fef-nqxu` directly. It contains unrelated commits and obsolete documentation changes.
- **CON-003**: Use commits `59a14ed` and `6161fec` only as implementation references. Reimplement their relevant behavior against current `main`.
- **CON-004**: Do not overwrite, stash, discard, stage, or commit the existing user modifications in `config/git/.gitconfig`, `config/vscode/settings.json`, or `config/windows-terminal/settings.json`.
- **CON-005**: Do not merge the completed feature branch into `main` while `git status --porcelain` is nonempty. Stop and report the exact paths requiring user disposition.
- **CON-006**: Preserve the current `install_nvm_node` function and its invocation in `bootstrap.sh`.
- **SEC-001**: Install only extension IDs explicitly committed to `config/vscode/extensions.txt`; do not discover or install additional extensions dynamically.
- **GUD-001**: Keep bootstrap reruns idempotent by using the supported VS Code `--force` option to install or update the declared extensions without interactive prompts.
- **PAT-001**: Use the existing `Log`/`Warn` PowerShell functions and `log`/`warn` Bash functions for all output.

## 2. Implementation Steps

### Implementation Phase 1

- GOAL-001: Establish an isolated, reproducible integration branch without touching the dirty `main` worktree.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-001 | Run `git status --short --branch` in `/home/lfarci/workspace/repos/dotfiles` and record the modified paths. Assert that no implementation command stages or changes those paths. | | |
| TASK-002 | Run `git fetch origin`, then verify the reference inputs with `git show --stat 59a14ed`, `git show --stat 6161fec`, and `git show HEAD:docs/superpowers/specs/2026-04-21-vscode-extension-install-design.md`. This task depends on TASK-001. | | |
| TASK-003 | Create an isolated worktree from current `main` at `/tmp/dotfiles-vscode-extension-bootstrap` on branch `feature/vscode-extension-bootstrap`. If that branch or path already exists, stop and report it instead of deleting or reusing it. This task depends on TASK-002. | | |
| TASK-004 | In the isolated worktree, run `git status --porcelain` and require empty output before editing. This task depends on TASK-003. | | |

Completion criteria: `/tmp/dotfiles-vscode-extension-bootstrap` exists on `feature/vscode-extension-bootstrap`, points at the same commit as `main`, and has a clean working tree.

### Implementation Phase 2

- GOAL-002: Add the shared manifest and deterministic installation logic without importing stale branch conflicts.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-005 | Create `config/vscode/extensions.txt` with a comment header followed by the nine IDs from REQ-002, one ID per line, grouped only with blank lines, and terminated by a newline. This task depends on TASK-004. | | |
| TASK-006 | Add `install_vscode_extensions` to `bootstrap.sh`. Resolve `config/vscode/extensions.txt` from `$DOTFILES_DIR`; strip comments and surrounding whitespace using Bash parameter expansion; install every parsed ID with `code --install-extension "$extension" --force`; collect failures in an array; and return nonzero after the loop if the array is nonempty. Implement the missing-CLI behavior from REQ-008 and REQ-009. Do not alter `install_nvm_node`. This task depends on TASK-004 and may run in parallel with TASK-005 and TASK-007. | | |
| TASK-007 | Add `Install-VSCodeExtensions` to `bootstrap.ps1`. Resolve the manifest with `Join-Path $DotfilesDir`; parse it with `Get-Content`, comment removal, `Trim()`, and empty-line filtering; resolve the executable with `Get-Command code`; invoke its `Path` with `--install-extension`, the extension ID, and `--force`; collect nonzero exits; and throw once after the loop with all failed IDs. This task depends on TASK-004 and may run in parallel with TASK-005 and TASK-006. | | |
| TASK-008 | Add `install_vscode_extensions` to the bottom-level execution order in `bootstrap.sh` after OS installation has completed and before `install_skills`. Add `Install-VSCodeExtensions` to the `bootstrap.ps1` main block immediately after `Install-WingetPackages` and before `Install-NerdFont`. This task depends on TASK-006 and TASK-007. | | |
| TASK-009 | Run `git diff -- config/vscode/settings.json` in the isolated worktree and require empty output. Verify the clean-main copy still contains `"workbench.colorTheme": "Catppuccin Macchiato"` and `"workbench.iconTheme": "material-icon-theme"`. This task depends on TASK-005 through TASK-008. | | |

Completion criteria: both bootstrap scripts consume the same nine-entry manifest, report aggregate failures, preserve Node installation, and leave `config/vscode/settings.json` unchanged.

### Implementation Phase 3

- GOAL-003: Reconcile repository documentation with the actual Windows, WSL, and native Linux behavior.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-010 | Update `docs/superpowers/specs/2026-04-21-vscode-extension-install-design.md` to add `PKief.material-icon-theme`, specify `--force`, document the WSL-versus-native-Linux missing-CLI behavior, and state that extension failures are aggregated. This task depends on TASK-005 through TASK-008. | | |
| TASK-011 | Update `README.md` to mention tracked VS Code configuration and the shared extension manifest. This task may run in parallel with TASK-010. | | |
| TASK-012 | Update `os/windows/README.md` to document extension installation after the winget `PATH` refresh and to state that PowerShell configures Windows VS Code user settings. This task may run in parallel with TASK-010. | | |
| TASK-013 | Update `os/ubuntu/README.md` and `os/fedora/README.md` to document that extensions install when `code` is already available and otherwise emit a warning without failing native-Linux bootstrap. This task may run in parallel with TASK-010. | | |
| TASK-014 | In `os/windows/README.md`, document that WSL uses the Windows `code` CLI for UI extensions and that themes remain local to the Windows VS Code UI. This task depends on TASK-012. | | |

Completion criteria: the specification and all platform setup documents describe the implemented manifest, ordering, failure behavior, and WSL extension location without contradictions.

### Implementation Phase 4

- GOAL-004: Add focused automated coverage and validate both script implementations.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-015 | Update `os/windows/Dockerfile` to place a non-networking executable `code` stub on `PATH` before `RUN ./bootstrap.sh`. The stub must append every argument vector to `/tmp/vscode-extension-installs.log`. After bootstrap, assert that each REQ-002 ID appears exactly once with `--install-extension` and `--force`. This task depends on Phase 2. | | |
| TASK-016 | Add a second Bash failure-path test using a temporary `code` stub that returns nonzero for two fixed IDs. Assert that later IDs are still attempted and that the final diagnostic contains both failed IDs. The test must not invoke package installation or write outside `/tmp`; extract and exercise the function through a dedicated test harness rather than sourcing the full bootstrap entrypoint. This task depends on Phase 2. | | |
| TASK-017 | Run `bash -n bootstrap.sh os/windows/install.sh os/ubuntu/install.sh os/fedora/install.sh` and require exit code 0. Run `shellcheck` on the same files when `shellcheck` is available; treat findings in changed lines as failures. This task depends on Phase 2. | | |
| TASK-018 | On PowerShell 5.1 or 7+, parse `bootstrap.ps1` with `[System.Management.Automation.Language.Parser]::ParseFile` and require zero parse errors. Exercise `Install-VSCodeExtensions` with a temporary `code.cmd` stub: verify all nine IDs and `--force`, then make two IDs fail and verify both appear in the thrown aggregate error. This task depends on Phase 2. | | |
| TASK-019 | Build `os/windows/Dockerfile`, `os/ubuntu/Dockerfile`, and `os/fedora/Dockerfile` from the isolated worktree and require all existing bootstrap assertions plus the new WSL extension assertions to pass. This task depends on TASK-015 through TASK-017. | | |
| TASK-020 | On an actual Windows-plus-WSL environment, run `bootstrap.ps1`, then `bootstrap.sh` inside WSL. Verify `code --list-extensions` contains `catppuccin.catppuccin-vsc` and `PKief.material-icon-theme`, open a WSL VS Code window, and verify the selected UI theme is `Catppuccin Macchiato`. This task depends on TASK-018 and TASK-019. | | |
| TASK-021 | Run `git diff --check`, require no whitespace errors, and run `git status --short` to confirm only the files declared in Section 5 changed. This task depends on TASK-010 through TASK-020. | | |

Completion criteria: Bash syntax, PowerShell syntax, success paths, aggregate-failure paths, all three Docker bootstrap builds, and one real Windows/WSL smoke test pass.

### Implementation Phase 5

- GOAL-005: Commit and integrate the validated change into `main` without absorbing or overwriting unrelated work.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-022 | In the isolated worktree, stage only the files declared in Section 5, inspect `git diff --cached`, and create one commit named `feat: install tracked vscode extensions`. This task depends on Phase 4. | | |
| TASK-023 | In the original `main` worktree, run `git status --porcelain`. If output is nonempty, stop and report the exact paths; do not stash, commit, reset, or discard them automatically. This task depends on TASK-022. | | |
| TASK-024 | After the original `main` worktree is clean, run `git merge --no-ff feature/vscode-extension-bootstrap` from `main`. Abort the merge and report conflicts if any file conflicts; do not select a side automatically. This task depends on TASK-023. | | |
| TASK-025 | Re-run `bash -n`, the PowerShell parser, focused extension tests, and `git diff --check` on merged `main`. Require `git log -1 --merges --oneline` to identify the feature merge and `git status --porcelain` to be empty. This task depends on TASK-024. | | |

Completion criteria: current `main` contains a dedicated reviewed feature commit through a non-fast-forward merge, all validation remains green after the merge, and no unrelated user changes are included.

## 3. Alternatives

- **ALT-001**: Merge `origin/copilot/implement-extension-install-plan` directly. Rejected because it conflicts in `bootstrap.sh`, duplicates the newer specification, and contains behavior that does not match the current failure requirements.
- **ALT-002**: Cherry-pick `59a14ed`. Rejected because the cherry-pick still conflicts with current `bootstrap.sh` and the specification, and its two-entry manifest omits extensions required by the current specification.
- **ALT-003**: Merge `origin/copilot/vscode-mo8q6fef-nqxu`. Rejected because the branch contains unrelated commits and changes outside the VS Code bootstrap scope.
- **ALT-004**: Install extensions only from PowerShell. Rejected because the repository specification requires both bootstrap entrypoints and native Linux users may already have a usable `code` CLI.
- **ALT-005**: Modify or discard the current uncommitted `config/vscode/settings.json` change to restore automatic theme selection. Rejected because that edit belongs to the user and is outside the authorized integration scope.

## 4. Dependencies

- **DEP-001**: Git with worktree support.
- **DEP-002**: Bash for `bootstrap.sh` syntax and focused tests.
- **DEP-003**: PowerShell 5.1 or PowerShell 7+ for parser and focused Windows tests.
- **DEP-004**: Docker for the existing Ubuntu, Fedora, and WSL-emulation bootstrap builds.
- **DEP-005**: A real Windows installation with WSL and VS Code for the final UI-extension smoke test.
- **DEP-006**: Network access to the Visual Studio Marketplace only for the real integration test; automated stub tests must not require Marketplace access.

## 5. Files

- **FILE-001**: `config/vscode/extensions.txt` — new shared extension manifest.
- **FILE-002**: `bootstrap.sh` — Bash manifest parser, installer, error aggregation, and invocation.
- **FILE-003**: `bootstrap.ps1` — PowerShell manifest parser, installer, error aggregation, and invocation.
- **FILE-004**: `os/windows/Dockerfile` — WSL-path stub and manifest-install assertions.
- **FILE-005**: `tests/bootstrap-vscode-extensions.bash` — focused Bash success and failure-path harness.
- **FILE-006**: `tests/bootstrap-vscode-extensions.Tests.ps1` — focused PowerShell success and failure-path harness.
- **FILE-007**: `README.md` — top-level VS Code configuration summary.
- **FILE-008**: `os/windows/README.md` — Windows and WSL behavior.
- **FILE-009**: `os/ubuntu/README.md` — native Ubuntu missing-CLI behavior.
- **FILE-010**: `os/fedora/README.md` — native Fedora missing-CLI behavior.
- **FILE-011**: `docs/superpowers/specs/2026-04-21-vscode-extension-install-design.md` — reconciled implementation specification.
- **FILE-012**: `config/vscode/settings.json` — validation-only file; it must not be changed or staged.
- **FILE-013**: `plan/feature-vscode-extension-bootstrap-1.md` — approved implementation plan and execution record.
- **FILE-014**: `tests/fixtures/code-stub.bash` — non-networking VS Code CLI stub shared by focused and Docker tests.
- **FILE-015**: `.github/workflows/run-installation-test.yml` — focused Bash and Windows PowerShell test jobs plus Docker dependency ordering.

## 6. Testing

- **TEST-001**: Manifest parser accepts comments, blank lines, and surrounding whitespace and emits the nine expected IDs in source order.
- **TEST-002**: Bash success-path stub records nine invocations containing `--install-extension <id> --force`.
- **TEST-003**: Bash failure-path stub proves that processing continues after failures and returns all failed IDs.
- **TEST-004**: PowerShell success-path stub records nine invocations containing `--install-extension <id> --force`.
- **TEST-005**: PowerShell failure-path stub proves that processing continues after failures and throws with all failed IDs.
- **TEST-006**: Missing `code` fails clearly on WSL and Windows PowerShell.
- **TEST-007**: Missing `code` warns and returns success on native Ubuntu and Fedora.
- **TEST-008**: `bash -n` reports no syntax errors in changed Bash files.
- **TEST-009**: PowerShell AST parsing reports no syntax errors in `bootstrap.ps1`.
- **TEST-010**: Ubuntu, Fedora, and WSL-emulation Docker builds pass.
- **TEST-011**: Real Windows and WSL smoke test shows Catppuccin installed locally and `Catppuccin Macchiato` selected from the Windows user settings.
- **TEST-012**: `git diff --check` reports no whitespace errors before and after merging.

## 7. Risks & Assumptions

- **RISK-001**: The original `main` worktree is currently dirty. Integrating while it remains dirty can mix unrelated changes or obscure conflicts; TASK-023 is therefore a hard gate.
- **RISK-002**: VS Code themes are UI extensions and are installed locally when using WSL. A Linux settings symlink alone does not configure the Windows UI, so the PowerShell phase remains required.
- **RISK-003**: Marketplace availability, publisher trust prompts, proxy settings, or signature verification can fail real extension installation. `--force` avoids normal CLI prompts but must not bypass signature verification.
- **RISK-004**: The current design specification omits `PKief.material-icon-theme` even though committed settings select `material-icon-theme`. This plan adds the extension and updates the specification instead of changing the selected icon theme.
- **RISK-005**: `packages/apt.txt` and `packages/dnf.txt` do not install VS Code. Treating a missing CLI as fatal on native Linux would regress existing bootstrap behavior.
- **ASSUMPTION-001**: The committed `main` value `"workbench.colorTheme": "Catppuccin Macchiato"` remains the desired clean-install default.
- **ASSUMPTION-002**: The user's uncommitted removal of `workbench.colorTheme` must remain untouched and may intentionally override automatic theme selection in that working tree.
- **ASSUMPTION-003**: The nine publishers and extension IDs listed in REQ-002 are trusted by the repository owner.

## 8. Related Specifications / Further Reading

- [Current repository design specification](../docs/superpowers/specs/2026-04-21-vscode-extension-install-design.md)
- [VS Code command-line extension management](https://code.visualstudio.com/docs/configure/command-line)
- [VS Code extension marketplace documentation](https://code.visualstudio.com/docs/configure/extensions/extension-marketplace)
- [VS Code WSL extension placement](https://code.visualstudio.com/docs/remote/wsl)
- [VS Code extension host locations](https://code.visualstudio.com/api/advanced-topics/extension-host)
