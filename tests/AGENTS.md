# AGENTS.md — tests

Assertion suites for the bootstrap entrypoints and the skills store. They are
plain scripts (Bash) or plain PowerShell scripts — **not** a shared test
framework — and each runs offline: no network, no package installs, no
Marketplace access, and no writes outside a per-test temp directory.

## Suites and CI wiring

| Suite | CI |
| --- | --- |
| `bootstrap-backup.bash` | `run-installation-test.yml` → `bash-syntax` |
| `bootstrap-skills-restore.bash` | `run-installation-test.yml` → `bash-syntax` |
| `bootstrap-vscode-extensions.bash` / `.Tests.ps1` | own `check-test-*` workflow + `run-installation-test.yml` |
| `bootstrap-powershell-profile.Tests.ps1` | own `check-test-*` workflow |
| `bootstrap-mapping-sources.bash` / `.Tests.ps1` | own `check-test-*` workflow |
| `bootstrap-opencode-install.bash` | own `check-test-*` workflow |
| `skills-inventory-consistency.bash` / `.mjs` / `.Tests.ps1` | `run-installation-test.yml` (both jobs) |
| `git-credential-helper.bash` | own `check-test-*` workflow |
| `windows-terminal-settings.bash` | own `check-test-*` workflow |
| `docker-service-activation.bash` | own `check-test-*` workflow (runs `bash -n` first) |
| `update-script.bash` / `.Tests.ps1` | own `check-test-*` workflow (Bash + PowerShell jobs); fast preconditions |
| `cleanup-script.bash` / `.Tests.ps1` | own `check-test-*` workflow (Bash + PowerShell jobs); fast refusals |
| `e2e/run_update_cleanup.py` | `check-test-e2e.yml` (Linux + Windows) + `run-installation-test.yml` → `docker-e2e` (weekly/manual) |
| `fixtures/` | shared stubs (e.g. `code-stub.bash`, in the ShellCheck lint scope) |

Heavy Docker bootstrap builds (`os/*/Dockerfile`) run only on the weekly
schedule or manual `run_installation=true`; see `docs/ci.md`.

## End-to-end harness

`tests/e2e/run_update_cleanup.py` is a Python (stdlib-only) harness that drives
the **real** `scripts/update.{sh,ps1}` and `scripts/cleanup.{sh,ps1}`
entrypoints against throwaway `$HOME` directories and real local git remotes.
`--platform auto` picks `.ps1` on Windows and `.sh` elsewhere, so one file runs
on Linux (local and container) and on `windows-latest`.

- It is offline by default: the update scenarios use a controlled fixture
  bootstrap, and the cleanup scenarios synthesize `.dotfiles_backup_*`
  directories. Everything is confined to a per-run temp workspace; the real
  `$HOME`, the real backups, and `~/.config` are never touched.
- `--real-bootstrap` additionally runs the repository's real `bootstrap.sh`
  against a fake `HOME` to create genuine backups. That installs
  packages/CLIs (network), so it only runs in the weekly/manual
  `run-installation-test.yml` → `docker-e2e` container job, mirroring
  `os/*/Dockerfile`.
- The stub suites (`update-script.*`, `cleanup-script.*`) are retained as fast,
  offline precondition/refusal checks. The E2E harness is the authority for
  end-to-end behavior; keep unit-level assertions minimal so the two do not
  drift.

## Conventions

- **Parity.** Behavior implemented in both `bootstrap.sh` and `bootstrap.ps1`
  gets a `.bash` suite and a `.Tests.ps1` suite covering the same cases
  (success path, aggregate failure path, missing-CLI path). Keep the two in
  sync when adding cases.
- **Harness pattern.** Bash suites `source ../bootstrap.sh` (with a
  `# shellcheck source=...` directive) and call its functions directly;
  PowerShell suites dot-source `bootstrap.ps1` and call its functions. They
  never run the entrypoints end-to-end — stubs and env overrides isolate the
  function under test (`OS=windows`, `DOTFILES_DIR=...`, `$env:PATH`).
- **Stub executables over mocks.** Put a stub on `PATH` that appends its
  argument vector to a log file named by an env var (`DOTFILES_CODE_LOG`) and
  fails selected IDs via another env var (`DOTFILES_CODE_FAIL_IDS`). Shared
  stubs live in `tests/fixtures/`. PowerShell stubs branch on
  `$env:OS -eq 'Windows_NT'` (`code.cmd` vs `code`).
- **Stubbing by shell function also works** where PATH stubs are awkward
  (e.g. `sudo`, `apt-get`, `systemctl` in `docker-service-activation.bash`);
  functions take precedence over PATH lookups, and an empty PATH directory
  hides the host's real commands.
- **OS installers are cut before their invocation block.** `os/*/install.sh`
  ends with unconditional installer calls; suites that need only the function
  definitions must cut the script at `^install_packages$` (see
  `load_os_functions`) so nothing installs inside the harness. Do not add a
  `main` guard to those scripts — this pattern depends on the current shape.
- **Output contract.** Bash: `fail()` prints `FAIL: <message>` to stderr and
  `exit 1`; success ends with `PASS: <suite-name>`. PowerShell: `Assert-True`
  throws `"FAIL: $Message"`; success ends with
  `Write-Host 'PASS: <suite-name>'` and resets `$global:LASTEXITCODE = 0` so a
  failing native stub cannot mark the passing script as failed in Actions.
- **Hygiene.** Bash: `set -euo pipefail`, `mktemp -d` + `trap ... EXIT` cleanup.
  PowerShell: `Set-StrictMode -Version Latest`, `try/finally` restoring
  `$env:PATH`, `$DotfilesDir`, and removed env vars.
- **Symlink-dependent assertions skip, not fail,** when the platform cannot
  create real symlinks (probe first — see `can_symlink` in
  `bootstrap-backup.bash`).
- **Keep suites ShellCheck-clean.** Files intentionally in the ShellCheck lint
  scope (currently `bootstrap-vscode-extensions.bash`,
  `fixtures/code-stub.bash`, and the maintained `scripts/*.sh`) must pass
  `shellcheck --severity=warning`; `.shellcheckrc` resolves cross-file `source`
  directives so no inline suppressions are needed. Test suites do **not** enter
  the PSScriptAnalyzer or ShellCheck scopes: only `bootstrap.ps1`, the
  maintained `scripts/*.ps1`, and the pre-existing
  `bootstrap-vscode-extensions.Tests.ps1` are analyzed.

## Adding a suite

1. Write the `.bash` suite; add a `.Tests.ps1` counterpart when the behavior
   exists in `bootstrap.ps1` too.
2. Wire it into CI: create `check-test-<name>.yml` following the existing
   pattern (PRs, pushes to `main`, `workflow_dispatch`, `permissions:
   contents: read`, pinned action SHA) and/or a step in
   `run-installation-test.yml`'s `bash-syntax` job.
3. Update `docs/ci.md` (workflow mapping) and `docs/linting.md` if the suite
   enters the ShellCheck scope.
