<#
.SYNOPSIS
    Reclaim disk space from stale bootstrap backup directories.

.DESCRIPTION
    Target: directories directly under $HOME named
      .dotfiles_backup_<yyyyMMddHHmmss>[.<n>]
    created by bootstrap.ps1 (and bootstrap.sh, which may add a numeric
    collision suffix) before a config file is replaced. Only directories whose
    modification time is more than -MinAgeDays in the past are considered.

    Safety:
      * Dry run by default; pass -Apply to actually delete.
      * Never follows symlinks or junctions and never touches paths outside $HOME.
      * Ignores unrecognized names (e.g. .dotfiles_backup_notes).
      * Does not touch ~/.config, ~/.local, git worktrees, or session data.

.PARAMETER Apply
    Delete the listed directories (default: dry run).

.PARAMETER MinAgeDays
    Only remove backups older than this many days. Default: 30.

.PARAMETER Help
    Show this help and exit. -? also displays it.

.EXAMPLE
    .\scripts\cleanup.ps1

.EXAMPLE
    .\scripts\cleanup.ps1 -Apply -MinAgeDays 30
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Apply,
    [ValidateRange(0, [int]::MaxValue)][int]$MinAgeDays = 30,
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Log  { param([string]$Msg) Write-Host "[cleanup] $Msg" }
function Warn { param([string]$Msg) Write-Host "[cleanup][warn] $Msg" -ForegroundColor Yellow }

function Show-Usage {
    Write-Host @'
usage: scripts\cleanup.ps1 [-Apply] [-MinAgeDays <days>] [-Help]

Reclaim disk space from stale bootstrap backup directories.

Target: directories directly under $HOME named
  .dotfiles_backup_<yyyyMMddHHmmss>[.<n>]
created by bootstrap.ps1 (and bootstrap.sh, which may add a numeric collision
suffix) before a config file is replaced. Only directories whose modification
time is more than -MinAgeDays in the past are considered.

Safety:
  * Dry run by default; pass -Apply to actually delete.
  * Never follows symlinks or junctions and never touches paths outside $HOME.
  * Ignores unrecognized names (e.g. .dotfiles_backup_notes).
  * Does not touch ~/.config, ~/.local, git worktrees, or session data.

Parameters:
  -Apply               Delete the listed directories (default: dry run).
  -MinAgeDays <days>   Only remove backups older than <days>. Default: 30.
  -Help                Show this help and exit (-? also works).
'@
}

# $HOME is read-only in PowerShell, so it is resolved through this helper: the
# test suite redefines it in its own scope to point at a sandbox (the same seam
# bootstrap.ps1 uses for Get-DocumentsPath).
function Get-DotfilesHome {
    return $HOME
}

# bootstrap.ps1 names backups ".dotfiles_backup_<yyyyMMddHHmmss>"; bootstrap.sh
# may append a numeric collision suffix. Anything else is not ours to remove.
function Test-ManagedBackupName {
    param([string]$Name)
    return ($Name -match '^\.dotfiles_backup_[0-9]{14}(\.[0-9]+)?$')
}

function Test-IsReparsePoint {
    param([System.IO.FileSystemInfo]$Item)
    return (($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
}

# Refuse to run against a HOME that could point somewhere catastrophic.
function Test-SafeHome {
    param([string]$HomePath)

    if (-not $HomePath) {
        Warn 'HOME is not set; refusing to run.'
        return $false
    }
    if (-not [System.IO.Path]::IsPathRooted($HomePath)) {
        Warn "HOME is not an absolute path ('$HomePath'); refusing to run."
        return $false
    }

    $homeFull = [System.IO.Path]::GetFullPath($HomePath)
    if ($homeFull -eq [System.IO.Path]::GetPathRoot($homeFull)) {
        Warn 'HOME points at a filesystem root; refusing to run.'
        return $false
    }
    if (-not (Test-Path -LiteralPath $HomePath -PathType Container)) {
        Warn "HOME is not a directory: $HomePath"
        return $false
    }
    return $true
}

# Return the managed, old-enough backup directories directly under $HomePath.
function Get-StaleBackup {
    param(
        [string]$HomePath,
        [int]$MinAge
    )

    $cutoff = (Get-Date).AddDays(-$MinAge)
    return @(
        Get-ChildItem -LiteralPath $HomePath -Directory -Force -ErrorAction SilentlyContinue |
            Where-Object { Test-ManagedBackupName -Name $_.Name } |
            Where-Object { -not (Test-IsReparsePoint -Item $_) } |
            Where-Object { $_.LastWriteTime -lt $cutoff } |
            Sort-Object -Property FullName
    )
}

# Remove a single backup, re-checking every guard so a caller cannot pass an
# unexpected path by mistake.
function Remove-StaleBackup {
    param(
        [System.IO.DirectoryInfo]$Item,
        [string]$HomePath
    )

    $parent   = Split-Path $Item.FullName -Parent
    $homeFull = [System.IO.Path]::GetFullPath($HomePath)

    if ([System.IO.Path]::GetFullPath($parent) -ne $homeFull) {
        Warn "Refusing to remove path outside HOME: $($Item.FullName)"
        return $false
    }
    if (-not (Test-ManagedBackupName -Name $Item.Name)) {
        Warn "Refusing to remove unrecognized name: $($Item.Name)"
        return $false
    }
    if (Test-IsReparsePoint -Item $Item) {
        Warn "Refusing to remove symlink or junction: $($Item.FullName)"
        return $false
    }

    try {
        Remove-Item -LiteralPath $Item.FullName -Recurse -Force
        Log "Removed $($Item.FullName)"
        return $true
    } catch {
        Warn "Failed to remove $($Item.FullName): $($_.Exception.Message)"
        return $false
    }
}

function Invoke-Cleanup {
    param(
        [switch]$Apply,
        [ValidateRange(0, [int]::MaxValue)][int]$MinAgeDays = 30,
        [switch]$Help
    )

    if ($Help) {
        Show-Usage
        return $true
    }

    $homeDir = Get-DotfilesHome
    if (-not (Test-SafeHome -HomePath $homeDir)) {
        return $false
    }

    $candidates = @(Get-StaleBackup -HomePath $homeDir -MinAge $MinAgeDays)

    $mode = 'dry run'
    if ($Apply) {
        $mode = 'apply'
    }

    Log "HOME:        $homeDir"
    Log "Minimum age: $MinAgeDays day(s)"
    Log "Mode:        $mode"

    if ($candidates.Count -eq 0) {
        Log 'No stale bootstrap backups found.'
        return $true
    }

    Log "Found $($candidates.Count) stale bootstrap backup(s):"
    foreach ($candidate in $candidates) {
        Write-Host "  $($candidate.FullName)"
    }

    if (-not $Apply) {
        Log 'Dry run: nothing was removed. Re-run with -Apply to delete these directories.'
        return $true
    }

    $failed = $false
    foreach ($candidate in $candidates) {
        if (-not (Remove-StaleBackup -Item $candidate -HomePath $homeDir)) {
            $failed = $true
        }
    }

    if ($failed) {
        Warn 'Some directories could not be removed.'
        return $false
    }

    Log "Removed $($candidates.Count) stale bootstrap backup(s)."
    return $true
}

if ($MyInvocation.InvocationName -ne '.') {
    if (Invoke-Cleanup -Apply:$Apply -MinAgeDays $MinAgeDays -Help:$Help) {
        exit 0
    }
    exit 1
}
