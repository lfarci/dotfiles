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

# ── Seed-IfMissing / Seed-All: copy once, never overwrite ────────────────────

$sandbox = Join-Path ([System.IO.Path]::GetTempPath()) "dotfiles-seed-test-$([guid]::NewGuid())"
$repoSandbox = Join-Path $sandbox 'repo'
$seedHome = Join-Path $sandbox 'home'
New-Item -Path (Join-Path $repoSandbox 'config\opencode') -ItemType Directory -Force | Out-Null
New-Item -Path $seedHome -ItemType Directory -Force | Out-Null
Set-Content -Path (Join-Path $repoSandbox 'config\opencode\cli.json') -Value '{"theme":"midnight"}' -NoNewline

$originalDotfilesDir = $DotfilesDir
$originalHome = $HOME
$DotfilesDir = $repoSandbox

try {
    # A missing destination is seeded from the tracked source.
    $destination = Join-Path $seedHome '.config\opencode\cli.json'
    Seed-IfMissing -Src 'config\opencode\cli.json' -Dst $destination
    Assert-True (Test-Path $destination) 'Seed-IfMissing did not create a missing destination'
    Assert-True ((Get-Content $destination -Raw) -eq '{"theme":"midnight"}') 'seeded content did not match the tracked source'

    # An existing destination is never overwritten: the TUI owns it after seeding.
    Set-Content -Path $destination -Value 'live-tui-prefs' -NoNewline
    Seed-IfMissing -Src 'config\opencode\cli.json' -Dst $destination
    Assert-True ((Get-Content $destination -Raw) -eq 'live-tui-prefs') 'Seed-IfMissing overwrote an existing destination'

    # A missing source warns and creates nothing.
    $missingDestination = Join-Path $seedHome '.config\opencode\missing.json'
    Seed-IfMissing -Src 'config\opencode\does-not-exist.json' -Dst $missingDestination
    Assert-True (-not (Test-Path $missingDestination)) 'a missing source must not create a destination'

    # Seed-All wires the tracked cli.json into ~/.config/opencode.
    $seedAllHome = Join-Path $sandbox 'home-seed-all'
    New-Item -Path $seedAllHome -ItemType Directory -Force | Out-Null
    $HOME = $seedAllHome
    Seed-All
    $wiredDestination = Join-Path $seedAllHome '.config\opencode\cli.json'
    Assert-True (Test-Path $wiredDestination) 'Seed-All did not seed ~/.config/opencode/cli.json'
    Assert-True ((Get-Content $wiredDestination -Raw) -eq '{"theme":"midnight"}') 'Seed-All seeded the wrong content'

    # A dangling link destination is left alone rather than replaced.
    if (Test-CanSymlink) {
        $danglingDestination = Join-Path $seedHome '.config\opencode\dangling.json'
        New-Item -Path $danglingDestination -ItemType SymbolicLink -Target (Join-Path $sandbox 'gone') | Out-Null
        Seed-IfMissing -Src 'config\opencode\cli.json' -Dst $danglingDestination
        Assert-True ((Get-Item $danglingDestination -Force).LinkType -eq 'SymbolicLink') 'a dangling link destination was replaced'
    } else {
        Write-Host 'SKIP: dangling-link seed assertion (symlink creation unavailable)'
    }

    # The tracked seed source exists in the real repository.
    Assert-True (Test-Path (Join-Path $RepoDir 'config\opencode\cli.json')) 'the tracked cli.json seed source is missing'
} finally {
    $DotfilesDir = $originalDotfilesDir
    $HOME = $originalHome
    if (Test-Path $sandbox) {
        Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$global:LASTEXITCODE = 0
Write-Host 'PASS: bootstrap-mapping-sources.Tests.ps1'
