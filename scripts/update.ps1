<#
.SYNOPSIS
    Update this dotfiles checkout and re-apply it.

.DESCRIPTION
    Pull the latest commit for this dotfiles checkout and re-apply it.

    Before touching anything the script verifies all of the following and stops
    with an actionable message when one fails:

      * the script lives in a Git work tree
      * HEAD is attached to a branch (not detached)
      * the checked-out branch matches -Branch (default: main)
      * the working tree is clean (no staged, unstaged, or untracked changes)

    It then runs `git pull --ff-only` and, unless -NoBootstrap is given, re-runs
    .\bootstrap.ps1 from the repository root. Both steps are safe to re-run.

.PARAMETER Branch
    Branch to update. Default: main.

.PARAMETER NoBootstrap
    Pull only; do not re-run bootstrap.ps1.

.PARAMETER Help
    Show this help and exit. -? also displays it.

.EXAMPLE
    .\scripts\update.ps1

.EXAMPLE
    .\scripts\update.ps1 -Branch main -NoBootstrap
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Branch = 'main',
    [switch]$NoBootstrap,
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$DotfilesDir = Split-Path $PSScriptRoot -Parent

function Log  { param([string]$Msg) Write-Host "[update] $Msg" }
function Warn { param([string]$Msg) Write-Host "[update][warn] $Msg" -ForegroundColor Yellow }

function Show-Usage {
    Write-Host @'
usage: scripts\update.ps1 [-Branch <name>] [-NoBootstrap] [-Help]

Pull the latest commit for this dotfiles checkout and re-apply it.

Before touching anything the script verifies all of the following and stops
with an actionable message when one fails:

  * the script lives in a Git work tree
  * HEAD is attached to a branch (not detached)
  * the checked-out branch matches -Branch (default: main)
  * the working tree is clean (no staged, unstaged, or untracked changes)

It then runs `git pull --ff-only` and, unless -NoBootstrap is given, re-runs
.\bootstrap.ps1 from the repository root. Both steps are safe to re-run.

Parameters:
  -Branch <name>  Branch to update. Default: main.
  -NoBootstrap    Pull only; do not re-run bootstrap.ps1.
  -Help           Show this help and exit (-? also works).
'@
}

function Test-GitWorkTree {
    param([string]$Dir)

    Push-Location $Dir
    try {
        git rev-parse --is-inside-work-tree *> $null
        return ($LASTEXITCODE -eq 0)
    } finally {
        Pop-Location
    }
}

function Get-CurrentBranch {
    param([string]$Dir)

    Push-Location $Dir
    try {
        $branch = git symbolic-ref --quiet --short HEAD
        if ($LASTEXITCODE -ne 0) {
            return $null
        }
        return $branch
    } finally {
        Pop-Location
    }
}

function Test-CleanTree {
    param([string]$Dir)

    Push-Location $Dir
    try {
        $status = git status --porcelain
        if ($LASTEXITCODE -ne 0) {
            Warn 'Could not read the working tree status.'
            return $false
        }
        if ($status) {
            Warn 'Working tree is not clean; refusing to update.'
            Warn 'Commit or stash the following changes and try again:'
            foreach ($line in @($status)) {
                Warn "  $line"
            }
            return $false
        }
        return $true
    } finally {
        Pop-Location
    }
}

function Test-Preconditions {
    param(
        [string]$Dir,
        [string]$ExpectedBranch
    )

    if (-not (Test-GitWorkTree -Dir $Dir)) {
        Warn "Not inside a Git work tree: $Dir"
        Warn 'Clone the dotfiles repository and run this script from its checkout.'
        return $false
    }

    $branch = Get-CurrentBranch -Dir $Dir
    if (-not $branch) {
        Warn 'HEAD is detached; refusing to update.'
        Warn "Check out the expected branch first: git -C `"$Dir`" switch $ExpectedBranch"
        return $false
    }

    if ($branch -ne $ExpectedBranch) {
        Warn "On branch '$branch' but expected '$ExpectedBranch'; refusing to update."
        Warn "Switch with 'git switch $ExpectedBranch' or re-run with -Branch '$branch'."
        return $false
    }

    if (-not (Test-CleanTree -Dir $Dir)) {
        return $false
    }

    return $true
}

function Invoke-Pull {
    param(
        [string]$Dir,
        [string]$ExpectedBranch
    )

    Log "Pulling latest '$ExpectedBranch' with --ff-only..."
    Push-Location $Dir
    try {
        git pull --ff-only
        return ($LASTEXITCODE -eq 0)
    } finally {
        Pop-Location
    }
}

function Invoke-Bootstrap {
    param([string]$Dir)

    $bootstrap = Join-Path $Dir 'bootstrap.ps1'
    if (-not (Test-Path -LiteralPath $bootstrap)) {
        Warn "Bootstrap script not found: $bootstrap"
        return $false
    }

    Log 'Re-applying dotfiles: .\bootstrap.ps1'
    Push-Location $Dir
    try {
        & $bootstrap
        return $true
    } catch {
        Warn "bootstrap.ps1 failed: $($_.Exception.Message)"
        return $false
    } finally {
        Pop-Location
    }
}

function Invoke-Update {
    param(
        [string]$Dir,
        [string]$ExpectedBranch = 'main',
        [switch]$SkipBootstrap,
        [switch]$Help
    )

    if ($Help) {
        Show-Usage
        return $true
    }

    $steps = 'git pull --ff-only'
    if (-not $SkipBootstrap) {
        $steps = 'git pull --ff-only; .\bootstrap.ps1'
    }

    Log "Dotfiles checkout: $Dir"
    Log "Expected branch:   $ExpectedBranch"
    Log "Then run:          $steps"

    if (-not (Test-Preconditions -Dir $Dir -ExpectedBranch $ExpectedBranch)) {
        Warn 'Nothing was changed.'
        return $false
    }

    if (-not (Invoke-Pull -Dir $Dir -ExpectedBranch $ExpectedBranch)) {
        Warn 'git pull failed; the checkout was not re-applied.'
        return $false
    }

    if (-not $SkipBootstrap) {
        if (-not (Invoke-Bootstrap -Dir $Dir)) {
            Warn 'bootstrap.ps1 failed; review the output above.'
            return $false
        }
    } else {
        Log 'Skipping bootstrap.ps1 (-NoBootstrap).'
    }

    Log 'Update complete.'
    return $true
}

if ($MyInvocation.InvocationName -ne '.') {
    if (Invoke-Update -Dir $DotfilesDir -ExpectedBranch $Branch -SkipBootstrap:$NoBootstrap -Help:$Help) {
        exit 0
    }
    exit 1
}
