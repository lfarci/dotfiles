# Continuous integration

Lightweight test scripts each have a dedicated workflow named
`check-test-<script>`:

- [`check-test-bootstrap-vscode-extensions.yml`](../.github/workflows/check-test-bootstrap-vscode-extensions.yml)
  runs the Bash and PowerShell assertion suites.
- [`check-test-git-credential-helper.yml`](../.github/workflows/check-test-git-credential-helper.yml)
  runs the Git credential-helper Bash assertions.
- [`check-test-windows-terminal-settings.yml`](../.github/workflows/check-test-windows-terminal-settings.yml)
  runs the Windows Terminal settings Bash assertions.

Each runs on pull requests, pushes to `main`, and manual dispatch. The test
assertions live in `tests/`; workflows only check out the repository and invoke
the corresponding script.

[`run-installation-test.yml`](../.github/workflows/run-installation-test.yml)
handles Bash syntax validation and the slower Docker installation matrix. Docker
builds run only on the weekly schedule (Mondays 04:00 UTC) or when a manual run
sets `run_installation` to `true`. They depend on the Bash syntax job and do not
run on ordinary pull requests or pushes.

For lint workflows and local analyzer commands, see [`linting.md`](linting.md).
