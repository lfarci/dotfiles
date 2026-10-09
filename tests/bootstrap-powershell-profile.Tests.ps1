$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoDir = Split-Path $PSScriptRoot -Parent
. (Join-Path $RepoDir 'bootstrap.ps1')

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw "FAIL: $Message"
    }
}

function Get-ProfileInitCount {
    param([string]$ProfilePath)

    if (-not (Test-Path $ProfilePath)) {
        return 0
    }

    $content = Get-Content $ProfilePath -Raw -ErrorAction SilentlyContinue
    if (-not $content) {
        return 0
    }

    return ([regex]::Matches($content, 'oh-my-posh init pwsh')).Count
}

# A stable fingerprint of every file under a directory. Comparing fingerprints
# before/after proves whether anything was written there, even when the
# directory (and its profiles) already existed on this machine.
function Get-TreeFingerprint {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        return '<missing>'
    }

    $entries = Get-ChildItem -Path $Path -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
        "$($_.FullName)|$($_.Length)|$($_.LastWriteTimeUtc.Ticks)"
    }

    return ($entries -join ';')
}

function New-OhMyPoshStub {
    param([string]$Directory)

    New-Item -Path $Directory -ItemType Directory -Force | Out-Null

    if ($env:OS -eq 'Windows_NT') {
        Set-Content -Path (Join-Path $Directory 'oh-my-posh.cmd') -Value '@exit /b 0' -Encoding Ascii
    } else {
        $ompPath = Join-Path $Directory 'oh-my-posh'
        Set-Content -Path $ompPath -Value "#!/usr/bin/env bash`nexit 0" -Encoding utf8
        & chmod +x $ompPath
    }
}

# Runs a test body with PATH restricted to a temporary stub directory, so the
# oh-my-posh installed on this machine is never invoked, and removes the temp
# tree afterwards. The body is invoked from this scope, so the script-scope
# Get-DocumentsPath override below is what the production helpers resolve.
function Invoke-IsolatedProfileTest {
    [CmdletBinding()]
    param(
        [scriptblock]$Body,
        [bool]$ProvideOhMyPosh = $true
    )

    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "dotfiles-profile-test-$([guid]::NewGuid())"
    $stubDir = Join-Path $tempRoot 'stub'
    New-Item -Path $stubDir -ItemType Directory -Force | Out-Null

    if ($ProvideOhMyPosh) {
        New-OhMyPoshStub -Directory $stubDir
    }

    $originalPath = $env:PATH
    $separator = [System.IO.Path]::PathSeparator
    if ($ProvideOhMyPosh) {
        $env:PATH = "$stubDir$separator$originalPath"
    } else {
        $env:PATH = $stubDir
    }

    try {
        & $Body
    } finally {
        $env:PATH = $originalPath
        if (Test-Path $tempRoot) {
            Remove-Item $tempRoot -Recurse -Force
        }
    }
}

# ── Real resolution: the Documents special folder is used verbatim ──────────

$realDocuments = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::MyDocuments)

Assert-True ((Get-DocumentsPath) -eq $realDocuments) 'Get-DocumentsPath did not return the Documents special folder'

foreach ($edition in @('WindowsPowerShell', 'PowerShell')) {
    $expected = Join-Path (Join-Path $realDocuments $edition) 'Microsoft.PowerShell_profile.ps1'
    Assert-True ((Get-PowerShellProfilePath -Edition $edition) -eq $expected) "Get-PowerShellProfilePath did not resolve the $edition profile under the real Documents folder"
}

$homeRelativeDocuments = Join-Path $HOME 'Documents'
Assert-True ((Resolve-DocumentsPath -KnownFolderPath '') -eq $homeRelativeDocuments) 'an unresolved known folder did not fall back to $HOME\Documents'
Assert-True ((Resolve-DocumentsPath -KnownFolderPath 'C:\Redirected\Documents') -eq 'C:\Redirected\Documents') 'a resolved known folder was not returned as-is'

$threwOnBadEdition = $false
try {
    Get-PowerShellProfilePath -Edition 'NotAnEdition' | Out-Null
} catch {
    $threwOnBadEdition = $true
}
Assert-True $threwOnBadEdition 'an unsupported edition name should be rejected'

# ── Redirected (e.g. OneDrive) Documents ────────────────────────────────────
# Get-DocumentsPath is redefined in this script scope, which is the scope the
# dot-sourced production helpers resolve, so every write below is redirected.

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "dotfiles-profile-redirect-$([guid]::NewGuid())"
$redirectedDocuments = Join-Path $tempRoot 'OneDrive - Contoso\Documents'
New-Item -Path $redirectedDocuments -ItemType Directory -Force | Out-Null

function Get-DocumentsPath { return $redirectedDocuments }

$defaultEditionDir = Join-Path $homeRelativeDocuments 'WindowsPowerShell'
$defaultBefore = Get-TreeFingerprint -Path $defaultEditionDir

try {
    Invoke-IsolatedProfileTest -Body {
        Set-OhMyPoshProfile

        foreach ($edition in @('WindowsPowerShell', 'PowerShell')) {
            $profilePath = Join-Path (Join-Path $redirectedDocuments $edition) 'Microsoft.PowerShell_profile.ps1'
            Assert-True (Test-Path $profilePath) "$edition profile was not created under the redirected Documents folder"
            Assert-True ((Get-ProfileInitCount -ProfilePath $profilePath) -eq 1) "$edition profile does not contain exactly one oh-my-posh init"
        }

        # Repeated bootstrap must not duplicate initialization.
        Set-OhMyPoshProfile
        Set-OhMyPoshProfile
        foreach ($edition in @('WindowsPowerShell', 'PowerShell')) {
            $profilePath = Join-Path (Join-Path $redirectedDocuments $edition) 'Microsoft.PowerShell_profile.ps1'
            Assert-True ((Get-ProfileInitCount -ProfilePath $profilePath) -eq 1) "repeated bootstrap duplicated initialization in $profilePath"
        }

        # Existing user content must survive.
        $wsProfile = Join-Path (Join-Path $redirectedDocuments 'WindowsPowerShell') 'Microsoft.PowerShell_profile.ps1'
        Add-Content -Path $wsProfile -Value '# user-owned line'
        Set-OhMyPoshProfile
        Assert-True ((Get-Content $wsProfile -Raw).Contains('# user-owned line')) 'existing profile content was not preserved'
        Assert-True ((Get-ProfileInitCount -ProfilePath $wsProfile) -eq 1) 'existing content caused duplicate initialization'
    }
} finally {
    if (Test-Path $tempRoot) {
        Remove-Item $tempRoot -Recurse -Force
    }
}

Assert-True ((Get-TreeFingerprint -Path $defaultEditionDir) -eq $defaultBefore) 'the default $HOME\Documents profile location was written to'

# ── Nothing to configure when oh-my-posh is unavailable ─────────────────────

$missingRoot = Join-Path ([System.IO.Path]::GetTempPath()) "dotfiles-profile-missing-$([guid]::NewGuid())"
$redirectedDocuments = Join-Path $missingRoot 'Documents'

try {
    Invoke-IsolatedProfileTest -ProvideOhMyPosh $false -Body {
        Set-OhMyPoshProfile

        $profilePath = Join-Path (Join-Path $missingRoot 'Documents\PowerShell') 'Microsoft.PowerShell_profile.ps1'
        Assert-True (-not (Test-Path $profilePath)) 'profile should not be written when oh-my-posh is missing'
    }
} finally {
    if (Test-Path $missingRoot) {
        Remove-Item $missingRoot -Recurse -Force
    }
}

Write-Host 'PASS: bootstrap-powershell-profile.Tests.ps1'
