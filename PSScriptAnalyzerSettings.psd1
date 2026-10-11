@{
    # PSScriptAnalyzer baseline for this repository's maintained PowerShell
    # scripts. Only rules that cannot be satisfied without changing the
    # behaviour or the on-disk encoding of existing scripts are excluded; each
    # exclusion is justified below. CI and local runs share this file.
    Severity = @('Error', 'Warning')

    ExcludeRules = @(
        # Verb/noun naming guidelines on pre-existing public function names
        # (Install-WingetPackages, Link-All, Restore-Skills,
        # Install-VSCodeExtensions). Renaming them is a breaking change for
        # anyone calling or dot-sourcing these functions.
        'PSUseSingularNouns'
        'PSUseApprovedVerbs'

        # bootstrap.ps1 draws section rules with box-drawing characters and is
        # stored as UTF-8 without a BOM. Adding a BOM solely to satisfy this
        # rule would rewrite a file whose encoding is deliberately byte-stable.
        'PSUseBOMForUnicodeEncodedFile'

        # These functions change machine state but are intentionally called
        # directly by the bootstrap rather than through ShouldProcess, which
        # would interactively prompt during an unattended install.
        'PSUseShouldProcessForStateChangingFunctions'

        # Write-Host is the intended output mechanism for an interactive
        # bootstrap script; it is not a data stream consumed by other tools.
        'PSAvoidUsingWriteHost'
    )
}
