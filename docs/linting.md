# Script linting

The Bash and PowerShell lint checks run separately in
[`check-bash-scripts.yml`](../.github/workflows/check-bash-scripts.yml) and
[`check-powershell-scripts.yml`](../.github/workflows/check-powershell-scripts.yml).
Both workflows run on pull requests, pushes to `main`, and manual dispatches.
They analyze explicit lists of maintained scripts; vendored skills under
`config/agents/` are intentionally excluded. The Python end-to-end harness under
`tests/e2e/` is not part of either lint scope.

## Bash

ShellCheck is installed from Ubuntu's signed package repositories. The runner
reports the installed version in the workflow log. CI checks these files at
warning severity:

```bash
shellcheck --severity=warning \
  bootstrap.sh os/ubuntu/install.sh os/fedora/install.sh \
  os/windows/install.sh scripts/update.sh scripts/cleanup.sh \
  tests/bootstrap-vscode-extensions.bash tests/fixtures/code-stub.bash
```

`.shellcheckrc` provides `external-sources` and `source-path=SCRIPTDIR:.` so
source directives resolve without inline suppressions. ShellCheck's severity
threshold is passed on the command line because it is not a supported rc key.

## PowerShell

PSScriptAnalyzer 1.25.0 is installed and explicitly imported at that version;
the workflow verifies the loaded version before analyzing the bootstrap
entrypoint, the maintained `scripts/` helpers, and the Pester test using
`PSScriptAnalyzerSettings.psd1`. Test suites do not enter the analyzer scope
(only `tests/bootstrap-vscode-extensions.Tests.ps1`, which predates that split,
is analyzed).

```powershell
Install-Module PSScriptAnalyzer -RequiredVersion 1.25.0 -Force -Scope CurrentUser
Import-Module PSScriptAnalyzer -RequiredVersion 1.25.0 -Force
Invoke-ScriptAnalyzer -Path bootstrap.ps1 -Settings ./PSScriptAnalyzerSettings.psd1
Invoke-ScriptAnalyzer -Path scripts/update.ps1 -Settings ./PSScriptAnalyzerSettings.psd1
Invoke-ScriptAnalyzer -Path scripts/cleanup.ps1 -Settings ./PSScriptAnalyzerSettings.psd1
Invoke-ScriptAnalyzer -Path tests/bootstrap-vscode-extensions.Tests.ps1 -Settings ./PSScriptAnalyzerSettings.psd1
```

The analyzer settings explain the narrow excluded rules. The `.gitattributes`
file keeps maintained shell and PowerShell scripts at LF; vendored skill files
are deliberately not normalized or linted as locally maintained scripts.
