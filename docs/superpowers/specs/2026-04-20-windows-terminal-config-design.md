# Windows Terminal Config In Repo

## Goal

Store Windows Terminal configuration in this repository and have Windows bootstrap manage it the same way the repo already manages Git, VS Code, and Oh My Posh settings.

## Constraints

- Preserve the user's current Windows Terminal settings as the initial tracked config.
- Keep the current repository pattern of repo-owned config files under `config/` plus symlinks created by `bootstrap.ps1`.
- Avoid hardcoding a single Windows Terminal installation shape when resolving the live settings file destination.
- Keep unrelated working tree changes untouched.

## Design

### Tracked configuration

Add `config/windows-terminal/settings.json` and seed it from the user's current live Windows Terminal settings file.

### Bootstrap behavior

Extend `bootstrap.ps1` with a helper that resolves the preferred Windows Terminal settings path from known locations:

1. Stable Store install
2. Preview Store install
3. Unpackaged install path under `%LOCALAPPDATA%\Microsoft\Windows Terminal`

If no file exists yet, default to the stable Store path because `bootstrap.ps1` already installs `Microsoft.WindowsTerminal` through `winget`.

`Link-All` will call this helper and add the repo Windows Terminal settings file to the existing backup-and-symlink flow.

### Documentation

Update the Windows README to show Windows Terminal settings as repo-managed rather than a mostly manual post-install step. Keep the font guidance, but make it clear that the font now lives in the tracked settings file.

## Validation

- Confirm the tracked `config/windows-terminal/settings.json` matches the current live Windows Terminal settings content.
- Run a focused PowerShell parse check on `bootstrap.ps1` after the edit.
- Review the Windows README for accurate destination and behavior descriptions.

## Out of scope

- Merging repo settings into an existing user-managed Windows Terminal file.
- Adding machine-specific override layers for Windows Terminal.
- Refactoring unrelated bootstrap behavior.
