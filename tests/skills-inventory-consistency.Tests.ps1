$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoDir = Split-Path $PSScriptRoot -Parent
$CheckScript = Join-Path $PSScriptRoot 'skills-inventory-consistency.mjs'

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw "FAIL: $Message"
    }
}

# Builds a throwaway repo skeleton with the given lock entries and skill dirs.
function New-InventoryFixture {
    param(
        [string]$Directory,
        [string]$SkillsJson,
        [string[]]$SkillNames = @()
    )

    $agentsDir = Join-Path $Directory 'config\agents'
    $skillsDir = Join-Path $agentsDir 'skills'
    New-Item -Path $skillsDir -ItemType Directory -Force | Out-Null
    Set-Content -Path (Join-Path $agentsDir '.skill-lock.json') -Encoding Ascii `
        -Value "{`"version`":3,`"skills`":$SkillsJson}"
    foreach ($name in $SkillNames) {
        New-Item -Path (Join-Path $skillsDir $name) -ItemType Directory -Force | Out-Null
    }
}

function Invoke-Check {
    param([string]$Directory)

    $output = & node $CheckScript $Directory 2>&1
    return @{
        ExitCode = $LASTEXITCODE
        Output   = ($output | Out-String)
    }
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "dotfiles-skills-inventory-$([guid]::NewGuid())"
New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
try {
    $tracked = Invoke-Check -Directory $RepoDir
    Assert-True ($tracked.ExitCode -eq 0) "committed skills inventory is inconsistent: $($tracked.Output)"

    $driftDir = Join-Path $tempRoot 'drift'
    New-InventoryFixture -Directory $driftDir -SkillsJson '{"brainstorming":{},"docx":{}}' -SkillNames @('docx', 'xlsx')
    $drift = Invoke-Check -Directory $driftDir
    Assert-True ($drift.ExitCode -ne 0) 'drift with equal counts must fail'
    Assert-True ($drift.Output.Contains('locked but no matching skill directory: brainstorming')) 'locked-but-missing skill was not reported'
    Assert-True ($drift.Output.Contains('skill directory without a lock entry: xlsx')) 'present-but-unlocked skill was not reported'
    Assert-True ($drift.Output.Contains('Equal counts do not imply matching inventories.')) 'equal-count caveat was not reported'

    $orphanDir = Join-Path $tempRoot 'orphan'
    New-InventoryFixture -Directory $orphanDir -SkillsJson '{"docx":{},"pdf":{}}' -SkillNames @('docx')
    $orphan = Invoke-Check -Directory $orphanDir
    Assert-True ($orphan.ExitCode -ne 0) 'a lock entry without a skill directory must fail'
    Assert-True ($orphan.Output.Contains('locked but no matching skill directory: pdf')) 'orphaned lock entry was not reported'

    $extraFileDir = Join-Path $tempRoot 'extra-file'
    New-InventoryFixture -Directory $extraFileDir -SkillsJson '{"docx":{},"pdf":{}}' -SkillNames @('docx', 'pdf')
    Set-Content -Path (Join-Path $extraFileDir 'config\agents\skills\README.md') -Encoding Ascii -Value '# skills'
    $extraFile = Invoke-Check -Directory $extraFileDir
    Assert-True ($extraFile.ExitCode -eq 0) "non-directory files must not count as skills: $($extraFile.Output)"

    $emptyDir = Join-Path $tempRoot 'empty'
    New-InventoryFixture -Directory $emptyDir -SkillsJson '{}'
    $empty = Invoke-Check -Directory $emptyDir
    Assert-True ($empty.ExitCode -eq 0) "an empty lock and empty skills dir must be consistent: $($empty.Output)"

    $invalidDir = Join-Path $tempRoot 'invalid'
    New-Item -Path (Join-Path $invalidDir 'config\agents\skills') -ItemType Directory -Force | Out-Null
    Set-Content -Path (Join-Path $invalidDir 'config\agents\.skill-lock.json') -Encoding Ascii -Value 'not json'
    $invalid = Invoke-Check -Directory $invalidDir
    Assert-True ($invalid.ExitCode -ne 0) 'an unreadable lock must fail'
} finally {
    if (Test-Path $tempRoot) {
        Remove-Item $tempRoot -Recurse -Force
    }
}

Write-Host 'PASS: skills-inventory-consistency.Tests.ps1'
