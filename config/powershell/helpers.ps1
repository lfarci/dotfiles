# PowerShell equivalents of the Bash dotfiles-update / dotfiles-clean helpers.
#
# bootstrap.ps1 symlinks this file to ~\.config\powershell\helpers.ps1 and adds a
# dot-source line to the PowerShell profile, so both helpers are available in
# every session. Each one forwards to the repo-maintained script that owns the
# behavior, keeping the pull/relink and cleanup logic in a single place.

function Get-DotfilesHelpersLink {
    <#
    .SYNOPSIS
        Path of the helpers symlink bootstrap.ps1 creates.
    .DESCRIPTION
        Exposed as a function so a test can point it at a sandbox, the same way
        scripts\cleanup.ps1 exposes Get-DotfilesHome.
    #>
    return Join-Path $HOME (Join-Path '.config' (Join-Path 'powershell' 'helpers.ps1'))
}

function Get-DotfilesDir {
    <#
    .SYNOPSIS
        Resolve the dotfiles checkout root.
    .DESCRIPTION
        Follows the ~\.config\powershell\helpers.ps1 symlink bootstrap.ps1
        creates, then walks up to the checkout root (the directory containing
        bootstrap.ps1). Returns $null and warns when the symlink is missing, so
        a detached copy cannot run the scripts against the wrong tree.
    #>
    $link = Get-DotfilesHelpersLink

    $target = $link
    $item = Get-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue
    if ($item -and $item.PSObject.Properties['Target'] -and $item.Target) {
        $target = @($item.Target)[0]
    }

    if ($target -and (Test-Path -LiteralPath $target -PathType Leaf)) {
        # <repo>\config\powershell\helpers.ps1 -> same three levels of dirname.
        $repo = Split-Path (Split-Path (Split-Path $target -Parent) -Parent) -Parent
        if (Test-Path -LiteralPath (Join-Path $repo 'bootstrap.ps1') -PathType Leaf) {
            return $repo
        }
    }

    Write-Warning 'dotfiles: cannot locate the dotfiles repo (~\.config\powershell\helpers.ps1 not symlinked?)'
    return $null
}

function dotfiles-update {
    <#
    .SYNOPSIS
        Pull the latest dotfiles commit and re-apply it (scripts\update.ps1).
    .DESCRIPTION
        Forwards to the repo's update script, which checks that the checkout is
        on the expected branch with a clean working tree before pulling.
        Parameters mirror scripts\update.ps1.
    #>
    [CmdletBinding()]
    param(
        [string]$Branch = 'main',
        [switch]$NoBootstrap,
        [switch]$Help
    )

    $repo = Get-DotfilesDir
    if (-not $repo) {
        return
    }

    $script = Join-Path $repo (Join-Path 'scripts' 'update.ps1')
    & $script -Branch $Branch -NoBootstrap:$NoBootstrap -Help:$Help
}

function dotfiles-clean {
    <#
    .SYNOPSIS
        Reclaim disk space from stale bootstrap backups (scripts\cleanup.ps1).
    .DESCRIPTION
        Forwards to the repo's cleanup script, which is a dry run unless -Apply
        is given. Parameters mirror scripts\cleanup.ps1.
    #>
    [CmdletBinding()]
    param(
        [switch]$Apply,
        [ValidateRange(0, [int]::MaxValue)][int]$MinAgeDays = 30,
        [switch]$Help
    )

    $repo = Get-DotfilesDir
    if (-not $repo) {
        return
    }

    $script = Join-Path $repo (Join-Path 'scripts' 'cleanup.ps1')
    & $script -Apply:$Apply -MinAgeDays $MinAgeDays -Help:$Help
}
