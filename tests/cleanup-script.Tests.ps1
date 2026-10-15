$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoDir = Split-Path $PSScriptRoot -Parent
. (Join-Path $RepoDir 'scripts\cleanup.ps1')

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw "FAIL: $Message"
    }
}

function Get-CapturedOutput {
    param([scriptblock]$Body)
    return (& $Body *>&1 | Out-String)
}

function Test-CanSymlink {
    $src  = Join-Path ([System.IO.Path]::GetTempPath()) "dotfiles-sym-src-$([guid]::NewGuid())"
    $link = Join-Path ([System.IO.Path]::GetTempPath()) "dotfiles-sym-link-$([guid]::NewGuid())"
    try {
        New-Item -Path $src -ItemType File -Force | Out-Null
        New-Item -Path $link -ItemType SymbolicLink -Target $src -Force | Out-Null
        return $true
    } catch {
        return $false
    } finally {
        if (Test-Path -LiteralPath $link) { Remove-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $src) { Remove-Item -LiteralPath $src -Force -ErrorAction SilentlyContinue }
    }
}

# NOTE: $HOME is read-only in PowerShell and variable names are case-insensitive,
# so the sandbox is held in $sandboxHome (not $home) to avoid touching it.
$sandbox = Join-Path ([System.IO.Path]::GetTempPath()) "dotfiles-cleanup-test-$([guid]::NewGuid())"
$sandboxHome = Join-Path $sandbox 'home'
$reparse = ''
$haveReparse = $false
try {
    New-Item -Path $sandboxHome -ItemType Directory -Force | Out-Null

    # Redirect the production HOME to the sandbox. $HOME is read-only, so the
    # Get-DotfilesHome seam (dot-sourced into this scope) is redefined to point
    # here; every production helper resolves it dynamically.
    function Get-DotfilesHome { return $sandboxHome }

    # ── help ────────────────────────────────────────────────────────────────
    $usage = Get-CapturedOutput { Show-Usage }
    Assert-True ($usage.Contains('usage: scripts\cleanup.ps1')) 'usage text is missing the usage line'
    Assert-True (Invoke-Cleanup -Help) '-Help should succeed'

    # ── managed-name matching ───────────────────────────────────────────────
    Assert-True (Test-ManagedBackupName -Name '.dotfiles_backup_20240101000000') 'a 14-digit name should be managed'
    Assert-True (Test-ManagedBackupName -Name '.dotfiles_backup_20240101000000.1') 'a suffixed name should be managed'
    Assert-True (-not (Test-ManagedBackupName -Name '.dotfiles_backup_notes')) 'an unrecognized name must not be managed'
    Assert-True (-not (Test-ManagedBackupName -Name '.dotfiles_backup_2024010100000')) 'a 13-digit name must not be managed'
    Assert-True (-not (Test-ManagedBackupName -Name 'dotfiles_backup_20240101000000')) 'a name without the leading dot must not be managed'

    # ── unsafe HOME ─────────────────────────────────────────────────────────
    Assert-True (-not (Test-SafeHome -HomePath '')) 'an empty HOME must be refused'
    Assert-True (-not (Test-SafeHome -HomePath '/')) 'HOME=/ must be refused'
    Assert-True (-not (Test-SafeHome -HomePath 'relative\path')) 'a relative HOME must be refused'

    # ── -MinAgeDays validation ──────────────────────────────────────────────
    $threw = $false
    try { Invoke-Cleanup -MinAgeDays -1 | Out-Null } catch { $threw = $true }
    Assert-True $threw 'a negative -MinAgeDays should be rejected'

    # ── fixtures ────────────────────────────────────────────────────────────
    $old       = Join-Path $sandboxHome '.dotfiles_backup_20200101000000'
    $oldSuffix = Join-Path $sandboxHome '.dotfiles_backup_20200102000000.1'
    $recent    = Join-Path $sandboxHome '.dotfiles_backup_29990101000000'
    $unmanaged = Join-Path $sandboxHome '.dotfiles_backup_notes'
    New-Item -Path $old -ItemType Directory -Force | Out-Null
    New-Item -Path $oldSuffix -ItemType Directory -Force | Out-Null
    New-Item -Path $recent -ItemType Directory -Force | Out-Null
    New-Item -Path $unmanaged -ItemType Directory -Force | Out-Null
    (Get-Item -LiteralPath $old).LastWriteTime       = (Get-Date).AddDays(-100)
    (Get-Item -LiteralPath $oldSuffix).LastWriteTime = (Get-Date).AddDays(-100)
    (Get-Item -LiteralPath $unmanaged).LastWriteTime = (Get-Date).AddDays(-100)
    New-Item -Path (Join-Path $sandboxHome '.config\opencode') -ItemType Directory -Force | Out-Null
    Set-Content -Path (Join-Path $sandboxHome '.config\opencode\opencode.json') -Value '{}' -Encoding Ascii

    # A symlink/junction named like a backup must never be considered a target.
    $reparse = Join-Path $sandboxHome '.dotfiles_backup_20200103000000'
    if ($env:OS -eq 'Windows_NT') {
        New-Item -Path $reparse -ItemType Junction -Target $recent | Out-Null
        $haveReparse = $true
    } elseif (Test-CanSymlink) {
        New-Item -Path $reparse -ItemType SymbolicLink -Target $recent | Out-Null
        $haveReparse = $true
    }

    # At -MinAgeDays 0 every managed, non-reparse directory is a candidate, so
    # this isolates the reparse-point filter from the age filter. Compare leaf
    # names so drive-letter/short-name normalization cannot cause false misses.
    $all = @(Get-StaleBackup -HomePath $sandboxHome -MinAge 0)
    $allNames = @($all | ForEach-Object { $_.Name })
    Assert-True ($allNames -contains (Split-Path $recent -Leaf)) 'a managed directory should be a candidate at MinAge 0'
    Assert-True ($allNames -notcontains (Split-Path $unmanaged -Leaf)) 'an unrecognized name must not be a candidate'
    if ($haveReparse) {
        Assert-True (Test-IsReparsePoint -Item (Get-Item -LiteralPath $reparse -Force)) 'a junction/symlink must be detected as a reparse point'
        Assert-True ($allNames -notcontains (Split-Path $reparse -Leaf)) 'a reparse-point backup must not be a candidate'
    } else {
        Write-Host 'SKIP: reparse-point assertions (junction/symlink creation unavailable)'
    }

    # ── dry run ─────────────────────────────────────────────────────────────
    $dryOutput = Get-CapturedOutput { Invoke-Cleanup }
    Assert-True ($dryOutput.Contains('Dry run')) 'dry run did not report that nothing was removed'
    Assert-True ($dryOutput.Contains((Split-Path $old -Leaf))) 'dry run did not list the stale backup'
    Assert-True (-not $dryOutput.Contains((Split-Path $recent -Leaf))) 'dry run listed a too-recent backup'
    Assert-True (Test-Path -LiteralPath $old) 'dry run removed a directory'

    # ── apply ───────────────────────────────────────────────────────────────
    $applyOutput = Get-CapturedOutput { Invoke-Cleanup -Apply }
    Assert-True ($applyOutput.Contains('Removed')) 'apply did not report removals'
    Assert-True (-not (Test-Path -LiteralPath $old)) 'an old managed backup was not removed'
    Assert-True (-not (Test-Path -LiteralPath $oldSuffix)) 'an old suffixed backup was not removed'
    Assert-True (Test-Path -LiteralPath $recent) 'a too-recent backup must be kept'
    Assert-True (Test-Path -LiteralPath $unmanaged) 'an unrecognized name must be kept'
    if ($haveReparse) {
        Assert-True (Test-Path -LiteralPath $reparse) 'a reparse-point backup must be kept'
    }
    Assert-True (Test-Path -LiteralPath (Join-Path $sandboxHome '.config\opencode\opencode.json')) 'cleanup touched ~/.config/opencode'

    # A second apply run finds nothing left and still succeeds.
    $again = Get-CapturedOutput { Invoke-Cleanup -Apply }
    Assert-True ($again.Contains('No stale bootstrap backups')) 'a second apply run should find nothing to remove'

    # ── Remove-StaleBackup guards ───────────────────────────────────────────
    $outside = Join-Path $sandbox 'outside'
    New-Item -Path $outside -ItemType Directory -Force | Out-Null
    Assert-True (-not (Remove-StaleBackup -Item (Get-Item -LiteralPath $outside) -HomePath $sandboxHome)) 'a path outside HOME must be refused'
    Assert-True (-not (Remove-StaleBackup -Item (Get-Item -LiteralPath $unmanaged) -HomePath $sandboxHome)) 'an unrecognized name must be refused'
    Assert-True (Test-Path -LiteralPath $unmanaged) 'an unrecognized name was removed'
    if ($haveReparse) {
        $reparseItem = Get-Item -LiteralPath $reparse -Force
        Assert-True (-not (Remove-StaleBackup -Item $reparseItem -HomePath $sandboxHome)) 'a reparse-point backup must be refused'
        Assert-True (Test-Path -LiteralPath $reparse) 'a reparse-point backup was removed'
    }

    # ── age threshold ───────────────────────────────────────────────────────
    $aged = Join-Path $sandboxHome '.dotfiles_backup_20200104000000'
    New-Item -Path $aged -ItemType Directory -Force | Out-Null
    (Get-Item -LiteralPath $aged).LastWriteTime = (Get-Date).AddDays(-100)

    Invoke-Cleanup -Apply -MinAgeDays 3650 | Out-Null
    Assert-True (Test-Path -LiteralPath $aged) 'a backup younger than the threshold must be kept'

    Invoke-Cleanup -Apply -MinAgeDays 1 | Out-Null
    Assert-True (-not (Test-Path -LiteralPath $aged)) 'a backup older than the threshold must be removed'
} finally {
    # Restore the real-HOME seam. Remove the reparse point first so the
    # recursive sandbox delete cannot traverse it, then remove the sandbox.
    function Get-DotfilesHome { return $HOME }
    if ($reparse -and (Test-Path -LiteralPath $reparse)) {
        Remove-Item -LiteralPath $reparse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $sandbox) {
        Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host 'PASS: cleanup-script.Tests.ps1'
# The suite intentionally exercises refusals. Clear any final status so the
# GitHub Actions PowerShell runner treats this successful test script as
# successful too.
$global:LASTEXITCODE = 0
