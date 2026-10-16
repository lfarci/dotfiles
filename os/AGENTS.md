# AGENTS.md — os

Per-OS setup: `install.sh` (package/tool installation), `Dockerfile`
(bootstrap smoke test), and `README.md` (user-facing setup docs) for
`ubuntu`, `fedora`, and `windows`.

## install.sh is sourced, not executed

`bootstrap.sh` detects the OS (`/proc/version` containing `microsoft` → WSL
reported as `windows`, otherwise the `/etc/os-release` `ID`) and `source`s
`os/$OS/install.sh`. `os/windows/install.sh` is a WSL shim that resolves the
Linux distro (`$WSL_DISTRO_ID`, default `ubuntu`) and sources that distro's
`install.sh` — Windows-native setup lives in `bootstrap.ps1`, not here. Each
install script therefore:

- **Depends on the caller's context:** `$DOTFILES_DIR` and the `log`/`warn`
  helpers from `bootstrap.sh` are already defined. Do not redefine them and do
  not add a `main`/entrypoint guard — suites parse the file and cut it before
  its trailing invocation block (`tests/docker-service-activation.bash`), which
  relies on the script ending with unconditional installer calls such as
  `install_packages`, `install_gh_cli`, ..., `install_docker`.
- **Warns and returns on failure** instead of exiting: bootstrap must continue
  with the rest of setup. Use the shared `warn`, never `exit`/`set -e` semantics.
- **Is idempotent:** guard each installer with `command -v <tool>` and return
  early when already installed.
- **Avoids plain sudo:** build a `sudo_cmd=()` array (empty when running as
  root, `(sudo)` otherwise) and skip the step with a `warn` when neither is
  available.
- **Ubuntu's `apt-get` invocations pass `SYSTEMD_OFFLINE=1`** so dpkg
  maintainer scripts skip systemd in containers and WSL. This is an
  apt/dpkg-specific mechanism: Fedora's `dnf` calls do not pass it and have
  no equivalent guard today — do not present it as a cross-platform
  invariant.
- **Docker service activation defers when systemd is absent:**
  `systemd_is_running` (`/run/systemd/system`) gates `systemctl enable
  --now docker`, with actionable instructions otherwise (`/etc/wsl.conf`
  `[boot] systemd=true` on WSL).
- **Adds third-party tools via their official keyring + repo flow** (gh,
  terraform, azure-cli, docker on Linux). Ordinary distro packages belong in
  `packages/apt.txt` / `packages/dnf.txt`, not in `install.sh`. Windows is the
  exception: `packages/winget.txt` covers Windows packages and `bootstrap.ps1`
  installs them.

## Conventions

- **Keep the Ubuntu and Fedora installers structurally parallel** (same
  function names and ordering where the package manager allows); Windows
  follows its own shape.
- **Keep `Dockerfile` aligned with `install.sh`.** The Dockerfiles run
  `bootstrap.sh` end-to-end as an installation smoke test and may add
  non-networking stubs (e.g. a `code` stub on `PATH`) plus assertions after the
  bootstrap. Update them together when bootstrap behavior changes.
- **Keep `README.md` per OS accurate** about what the bootstrap does and does
  not do for that platform (e.g. missing `code` CLI warns on native Linux but
  fails on Windows/WSL). The OS READMEs are the setup docs linked from the
  root `README.md`.

## Verify

All `install.sh` files are in the CI ShellCheck scope:

```bash
bash -n bootstrap.sh os/windows/install.sh os/ubuntu/install.sh os/fedora/install.sh
shellcheck --severity=warning bootstrap.sh os/*/install.sh
```

`tests/docker-service-activation.bash` covers the Docker/systemd activation
logic for Ubuntu and Fedora; run it when touching those installers.
