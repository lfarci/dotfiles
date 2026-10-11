# Continuous integration

Each lightweight assertion suite has a dedicated `check-test-<script>` workflow:

- [`check-test-bootstrap-vscode-extensions.yml`](../.github/workflows/check-test-bootstrap-vscode-extensions.yml)
  runs the Bash and PowerShell VS Code extension suites.
- [`check-test-git-credential-helper.yml`](../.github/workflows/check-test-git-credential-helper.yml)
  runs the Git credential-helper Bash assertions.
- [`check-test-windows-terminal-settings.yml`](../.github/workflows/check-test-windows-terminal-settings.yml)
  runs the Windows Terminal settings assertions.
- [`check-test-bootstrap-powershell-profile.yml`](../.github/workflows/check-test-bootstrap-powershell-profile.yml)
  runs the PowerShell profile path assertions.
- [`check-test-bootstrap-mapping-sources.yml`](../.github/workflows/check-test-bootstrap-mapping-sources.yml)
  runs the bootstrap symlink-mapping source assertions.

These workflows run on pull requests, pushes to `main`, and manual dispatch.
The assertions live in `tests/`; each workflow checks out the repo and invokes
its corresponding test script.

[`run-installation-test.yml`](../.github/workflows/run-installation-test.yml)
handles Bash syntax validation and the slower Docker installation matrix. Docker
builds run only on the weekly schedule (Mondays 04:00 UTC) or when a manual run
sets `run_installation` to `true`. They depend on Bash syntax validation and do
not run on ordinary pull requests or pushes.

For lint workflows and local analyzer commands, see [`linting.md`](linting.md).
