# VS Code Extension Install From Shared Manifest

## Goal

Install the required VS Code extensions during bootstrap on both Windows and Unix-like systems so editor themes and related tooling are available immediately after setup.

## Constraints

- Use the VS Code CLI via `code --install-extension <id> --force` rather than OS package managers.
- Keep a single shared extension list for all supported operating systems.
- Fit the repo's existing pattern of plain text package manifests and top-level bootstrap orchestration.
- Fail clearly if `code` is not available on Windows or WSL, where the Windows
  setup installs VS Code.
- Warn and skip extension installation on native Ubuntu and Fedora when `code`
  is unavailable, because their package lists do not install VS Code.
- Leave unrelated working tree changes untouched.

## Design

### Shared manifest

Add `config/vscode/extensions.txt` as a line-delimited manifest of extension IDs.

Behavior:

- One extension ID per line.
- Allow blank lines.
- Allow `#` comments so the list stays readable.

Initial contents:

- `catppuccin.catppuccin-vsc`
- `catppuccin.catppuccin-vsc-icons`
- `PKief.material-icon-theme`
- `ms-dotnettools.csharp`
- `stackbreak.comment-divider`
- `github.vscode-github-actions`
- `github.vscode-pull-request-github`
- `codezombiech.gitignore`
- `mermaidchart.vscode-mermaid-chart`

### Bootstrap behavior

Extend both `bootstrap.ps1` and `bootstrap.sh` with a dedicated VS Code extension install helper.

The helper will:

1. Verify the `code` CLI is available on `PATH`.
2. Read `config/vscode/extensions.txt`.
3. Strip comments and blank lines.
4. Install each listed extension with `code --install-extension <id> --force`.
5. Continue through the full list even if one install fails.
6. Fail at the end if any install failed, with a clear message identifying the failing extension IDs.

This keeps bootstrap resilient enough to surface all extension issues in one
run. A missing editor CLI is a setup failure on Windows and WSL but a warning
on native Ubuntu and Fedora.

### Ordering

Run the VS Code extension install step after package installation and before
skills restoration. PowerShell must run it immediately after winget package
installation refreshes the process `PATH`.

### WSL extension location

The WSL bootstrap uses the Windows `code` CLI. VS Code installs extensions that
affect the user interface, such as color and icon themes, locally on Windows.
The Windows PowerShell phase links `config/vscode/settings.json` into
`%APPDATA%\Code\User`, so it remains responsible for selecting the tracked
theme.

### Documentation

Update the top-level README to mention that VS Code settings are linked from `config/vscode/` and that extensions are installed from `config/vscode/extensions.txt` during bootstrap.

## Validation

- Confirm the new manifest is parsed correctly on both PowerShell and bash with comments and blank lines present.
- Run focused syntax checks on `bootstrap.ps1` and `bootstrap.sh` after editing.
- Verify the README accurately describes the new shared manifest behavior.

## Out of scope

- OS-specific or machine-specific extension manifests.
- Automatic export of the extension list from a live VS Code installation.
- Profile-specific VS Code extension installation.
- Installing VS Code itself outside the existing package-management flow.
