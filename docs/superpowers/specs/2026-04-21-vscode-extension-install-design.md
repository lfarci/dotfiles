# VS Code Extension Install Plan

## Goal

Track the preferred VS Code extensions in this repository and have both bootstrap entrypoints install them when the VS Code CLI is available.

## Constraints

- Keep the existing repo pattern of tracked config under `config/vscode/`.
- Make extension installation additive and idempotent.
- Skip the install step cleanly on machines where the `code` CLI is not available yet.
- Keep unrelated bootstrap and package-install behavior unchanged.

## Design

### Tracked configuration

Add `config/vscode/extensions.txt` with one Visual Studio Marketplace extension ID per line. Blank lines and `#` comments are ignored.

Seed the initial list with the extensions required by the tracked VS Code settings:

- `catppuccin.catppuccin-vsc`
- `PKief.material-icon-theme`

### Bootstrap behavior

Extend both `bootstrap.sh` and `bootstrap.ps1` with a small helper that:

1. Reads `config/vscode/extensions.txt`
2. Skips blank lines and comments
3. Checks whether the `code` CLI is available
4. Runs `code --install-extension <id> --force` for each listed extension

If the file is missing, empty, or the `code` CLI is unavailable, log a warning and continue without failing the rest of bootstrap.

### Documentation

Update the root and OS setup docs to describe the new repo-managed VS Code extension list and when it is applied.

## Validation

- Run shell syntax checks on `bootstrap.sh` and the sourced OS install scripts.
- Run a PowerShell parse check on `bootstrap.ps1`.
- Manually exercise the Bash bootstrap with a stub `code` command to verify listed extensions are installed from `config/vscode/extensions.txt`.

## Out of scope

- Uninstalling extensions that are not listed in `extensions.txt`
- Adding OS-specific VS Code extension lists
- Installing VS Code itself on Linux distributions that do not already provide the `code` CLI
