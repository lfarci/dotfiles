# Continuous integration

All CI is defined by [`.github/workflows/run-installation-test.yml`](../.github/workflows/run-installation-test.yml).

## Fast checks (automatic)

These run automatically on every pull request and every push to `main`:

- `bash-vscode-extensions` — `bash -n` syntax check of the Bash entrypoints
  (`bootstrap.sh`, `os/*/install.sh`) and the Bash VS Code extension test.
- `powershell-vscode-extensions` — the PowerShell VS Code extension test on
  `windows-latest`.

They are offline, so they cover the common case of a vendored skill or config
update without pulling anything from the network.

## Expensive installation jobs (opt-in / scheduled)

`docker-bootstrap` builds the `os/ubuntu`, `os/fedora`, and `os/windows`
Dockerfiles, which install packages over the network. Because it is slow and
network-dependent it does **not** run on ordinary pull requests or pushes. It
runs only when:

- the **weekly schedule** fires (Mondays 04:00 UTC), as a safety net, or
- a **manual run** sets the `run_installation` input to `true`.

Either way it depends on both fast-check jobs (`needs`), so a broken fast check
blocks the installation build.

## Manual runs

Use **Actions → Bootstrap checks → Run workflow** to trigger the workflow by
hand:

- leaving `run_installation` unchecked runs only the fast checks;
- checking `run_installation` also runs the Docker installation jobs.
