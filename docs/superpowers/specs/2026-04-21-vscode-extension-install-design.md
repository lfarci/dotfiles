# VS Code Extension Install From Shared Manifest

## Goal

Install the required VS Code extensions during bootstrap on both Windows and Unix-like systems so editor themes and related tooling are available immediately after setup.

## Constraints

- Use the VS Code CLI via `code --install-extension` rather than OS package managers.
- Keep a single shared extension list for all supported operating systems.
- Fit the repo's existing pattern of plain text package manifests and top-level bootstrap orchestration.
- Fail clearly if `code` is not available, because VS Code is already expected to be installed from the package lists.
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
4. Install each listed extension with `code --install-extension <id>`.
5. Continue through the full list even if one install fails.
6. Fail at the end if any install failed, with a clear message identifying the failing extension IDs.

This keeps bootstrap resilient enough to surface all extension issues in one run while still treating a missing editor CLI or broken extension install as a setup failure.

### Ordering

Run the VS Code extension install step after package installation and before or after symlink creation. The exact placement is not behaviorally sensitive as long as it runs after package installation, but placing it near the other tool setup steps keeps the flow easier to follow.

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
