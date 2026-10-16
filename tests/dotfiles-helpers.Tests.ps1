$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoDir = Split-Path $PSScriptRoot -Parent
. (Join-Path $RepoDir (Join-Path 'config' (Join-Path 'powershell' 'helpers.ps1')))

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw "FAIL: $Message"
    }
}

function Test-CanSymlink {
    $src  = Join-Path ([System.IO.Path]::GetTempPath()) "dh_src_$(Get-Random)"
    $link = Join-Path ([System.IO.Path]::GetTempPath()) "dh_link_$(Get-Random)"
    try {
        New-Item -Path $src  -ItemType File         -Force | Out-Null
        New-Item -Path $link -ItemType SymbolicLink -Target $src -Force | Out-Null
        return $true
    } catch {
        return $false
    } finally {
        if (Test-Path $link) { Remove-Item $link -Force -ErrorAction SilentlyContinue }
        if (Test-Path $src)  { Remove-Item $src  -Force -ErrorAction SilentlyContinue }
    }
}

function Get-HelpersSourcePath {
    return Join-Path $RepoDir (Join-Path 'config' (Join-Path 'powershell' 'helpers.ps1'))
}

# Build a fixture checkout whose stub scripts record the arguments they receive.
# The helpers resolve the repo from the (overridden) helpers link path, so the
# fixture provides a real file whose parent chain walks up to the checkout root.
function New-Fixture {
    param([string]$Root)

    $repo        = Join-Path $Root 'repo'
    $repoHelpers = Join-Path $repo (Join-Path 'config' (Join-Path 'powershell' 'helpers.ps1'))
    $scriptsDir  = Join-Path $repo 'scripts'

    New-Item -ItemType Directory -Force -Path (Split-Path $repoHelpers -Parent) | Out-Null
    New-Item -ItemType Directory -Force -Path $scriptsDir | Out-Null
    New-Item -ItemType File -Force -Path (Join-Path $repo 'bootstrap.ps1') | Out-Null
    Copy-Item -Path (Get-HelpersSourcePath) -Destination $repoHelpers

    Set-Content -Path (Join-Path $scriptsDir 'update.ps1') -Value @'
param([string]$Branch = 'main', [switch]$NoBootstrap, [switch]$Help)
Add-Content -LiteralPath $env:DOTFILES_HELPERS_LOG -Value "update:$Branch|$($NoBootstrap.IsPresent)|$($Help.IsPresent)"
'@
    Set-Content -Path (Join-Path $scriptsDir 'cleanup.ps1') -Value @'
param([switch]$Apply, [int]$MinAgeDays = 30, [switch]$Help)
Add-Content -LiteralPath $env:DOTFILES_HELPERS_LOG -Value "cleanup:$($Apply.IsPresent)|$MinAgeDays|$($Help.IsPresent)"
'@

    return [pscustomobject]@{ Repo = $repo; HelpersFile = $repoHelpers }
}

# ── Repo resolution and argument forwarding ────────────────────────────────

function Test-ResolutionAndForwarding {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) "dotfiles-helpers-test-$([guid]::NewGuid())"
    $log  = Join-Path $root 'calls.log'
    New-Item -ItemType Directory -Force -Path $root | Out-Null

    $originalLog = $env:DOTFILES_HELPERS_LOG
    $env:DOTFILES_HELPERS_LOG = $log
    try {
        $fixture = New-Fixture -Root $root

        function Get-DotfilesHelpersLink { return $fixture.HelpersFile }

        $resolved = Get-DotfilesDir
        Assert-True ($resolved -eq $fixture.Repo) "Get-DotfilesDir returned '$resolved', expected '$($fixture.Repo)'"

        dotfiles-update -Branch dev -NoBootstrap
        dotfiles-clean -Apply -MinAgeDays 7

        $calls = @(Get-Content -LiteralPath $log)
        Assert-True ($calls -contains 'update:dev|True|False') 'dotfiles-update did not forward its parameters to scripts/update.ps1'
        Assert-True ($calls -contains 'cleanup:True|7|False') 'dotfiles-clean did not forward its parameters to scripts/cleanup.ps1'
    } finally {
        $env:DOTFILES_HELPERS_LOG = $originalLog
        if (Test-Path $root) {
            Remove-Item $root -Recurse -Force
        }
    }
}

# ── The link path is followed when it is a symlink ──────────────────────────

function Test-SymlinkResolution {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) "dotfiles-helpers-link-$([guid]::NewGuid())"
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    try {
        $fixture = New-Fixture -Root $root

        $link = Join-Path $root (Join-Path 'home' (Join-Path '.config' (Join-Path 'powershell' 'helpers.ps1')))
        New-Item -ItemType Directory -Force -Path (Split-Path $link -Parent) | Out-Null
        New-Item -ItemType SymbolicLink -Path $link -Target $fixture.HelpersFile | Out-Null

        function Get-DotfilesHelpersLink { return $link }

        $resolved = Get-DotfilesDir
        Assert-True ($resolved -eq $fixture.Repo) "Get-DotfilesDir did not follow the helpers symlink to the checkout root; got '$resolved'"
    } finally {
        if (Test-Path $root) {
            Remove-Item $root -Recurse -Force
        }
    }
}

# ── A missing link is refused, so no script runs ────────────────────────────

function Test-GuardWithoutHelpers {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) "dotfiles-helpers-guard-$([guid]::NewGuid())"
    $log  = Join-Path $root 'calls.log'
    New-Item -ItemType Directory -Force -Path $root | Out-Null

    $originalLog = $env:DOTFILES_HELPERS_LOG
    $env:DOTFILES_HELPERS_LOG = $log
    try {
        $missing = Join-Path $root (Join-Path '.config' (Join-Path 'powershell' 'helpers.ps1'))

        function Get-DotfilesHelpersLink { return $missing }

        $resolved = Get-DotfilesDir 3>$null
        Assert-True (-not $resolved) 'Get-DotfilesDir must return $null when the helpers link is missing'

        dotfiles-update 3>$null
        dotfiles-clean -Apply 3>$null
        Assert-True (-not (Test-Path $log)) 'the helpers ran a repo script despite an unresolved repo root'
    } finally {
        $env:DOTFILES_HELPERS_LOG = $originalLog
        if (Test-Path $root) {
            Remove-Item $root -Recurse -Force
        }
    }
}

Test-ResolutionAndForwarding
Test-GuardWithoutHelpers

if (Test-CanSymlink) {
    Test-SymlinkResolution
} else {
    Write-Host 'SKIP: symlinks unavailable; symlink resolution assertion skipped'
}

Write-Host 'PASS: dotfiles-helpers.Tests.ps1'
$global:LASTEXITCODE = 0
