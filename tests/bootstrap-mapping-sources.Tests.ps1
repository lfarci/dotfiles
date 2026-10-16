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

# ── Seed-IfMissing: copy once, never overwrite ───────────────────────────────
# $HOME is read-only in PowerShell, so Seed-All is not exercised end to end
# here; its wiring is checked below by reading the Seed entries out of
# bootstrap.ps1, the same way the Bash suite parses them.

$sandbox = Join-Path ([System.IO.Path]::GetTempPath()) "dotfiles-seed-test-$([guid]::NewGuid())"
$repoSandbox = Join-Path $sandbox 'repo'
$seedHome = Join-Path $sandbox 'home'
New-Item -Path (Join-Path $repoSandbox 'config\opencode') -ItemType Directory -Force | Out-Null
New-Item -Path $seedHome -ItemType Directory -Force | Out-Null
Set-Content -Path (Join-Path $repoSandbox 'config\opencode\cli.json') -Value '{"theme":"midnight"}' -NoNewline

$originalDotfilesDir = $DotfilesDir
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

    # A dangling link destination is left alone rather than replaced.
    if (Test-CanSymlink) {
        $goneTarget = Join-Path $sandbox 'gone'
        Set-Content -Path $goneTarget -Value 'temp' -NoNewline
        $danglingDestination = Join-Path $seedHome '.config\opencode\dangling.json'
        New-Item -Path $danglingDestination -ItemType SymbolicLink -Target $goneTarget | Out-Null
        Remove-Item $goneTarget -Force
        Seed-IfMissing -Src 'config\opencode\cli.json' -Dst $danglingDestination
        Assert-True ((Get-Item $danglingDestination -Force).LinkType -eq 'SymbolicLink') 'a dangling link destination was replaced'
    } else {
        Write-Host 'SKIP: dangling-link seed assertion (symlink creation unavailable)'
    }

    # Every seed entry in bootstrap.ps1 must reference a tracked source.
    $content = Get-Content (Join-Path $RepoDir 'bootstrap.ps1') -Raw
    $seedSources = @([regex]::Matches($content, "@\{ Seed = '([^']+)'") | ForEach-Object {
        $_.Groups[1].Value -replace '\\', '/'
    })
    Assert-True ($seedSources.Count -ge 1) 'bootstrap.ps1 declares no Seed entries'
    foreach ($source in $seedSources) {
        Assert-True (Test-Path (Join-Path $RepoDir $source)) "seed source '$source' is missing from the repository"
    }
} finally {
    $DotfilesDir = $originalDotfilesDir
    if (Test-Path $sandbox) {
        Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$global:LASTEXITCODE = 0
Write-Host 'PASS: bootstrap-mapping-sources.Tests.ps1'
