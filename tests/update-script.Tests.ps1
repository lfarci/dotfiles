$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoDir = Split-Path $PSScriptRoot -Parent
. (Join-Path $RepoDir 'scripts\update.ps1')

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw "FAIL: $Message"
    }
}

# Capture Write-Host output (information stream) plus any success output so the
# safety messages can be asserted without a subprocess.
function Get-CapturedOutput {
    param([scriptblock]$Body)
    return (& $Body *>&1 | Out-String)
}

# A stub `git` on PATH driven by environment variables, so the preconditions can
# be exercised without a repository or any network access. Windows uses a .cmd
# shim; other platforms use a bash script (mirrors New-CodeStub). An undefined
# variable in a batch file is not reliably empty, so every switch uses a
# non-empty sentinel instead of a blank string.
function New-GitStub {
    param([string]$Directory)

    New-Item -Path $Directory -ItemType Directory -Force | Out-Null
    if ($env:OS -eq 'Windows_NT') {
        $stubPath = Join-Path $Directory 'git.cmd'
        @'
@echo off
>>"%DOTFILES_GIT_LOG%" echo %*
if "%~1"=="rev-parse" (
  if "%DOTFILES_GIT_IN_REPO%"=="1" exit /b 0
  exit /b 1
)
if "%~1"=="symbolic-ref" (
  if "%DOTFILES_GIT_DETACHED%"=="1" exit /b 1
  echo %DOTFILES_GIT_BRANCH%
  exit /b 0
)
if "%~1"=="status" (
  if not "%DOTFILES_GIT_STATUS%"=="__CLEAN__" echo %DOTFILES_GIT_STATUS%
  exit /b 0
)
if "%~1"=="pull" exit /b %DOTFILES_GIT_PULL_RC%
exit /b 0
'@ | Set-Content -Path $stubPath -Encoding Ascii
    } else {
        $stubPath = Join-Path $Directory 'git'
        @'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$DOTFILES_GIT_LOG"
case "${1:-}" in
  rev-parse)
    if [ "${DOTFILES_GIT_IN_REPO:-1}" = "1" ]; then exit 0; else exit 1; fi ;;
  symbolic-ref)
    if [ "${DOTFILES_GIT_DETACHED:-0}" = "1" ]; then exit 1; fi
    printf '%s\n' "${DOTFILES_GIT_BRANCH:-main}"; exit 0 ;;
  status)
    if [ "${DOTFILES_GIT_STATUS:-__CLEAN__}" != "__CLEAN__" ]; then printf '%s\n' "$DOTFILES_GIT_STATUS"; fi
    exit 0 ;;
  pull) exit "${DOTFILES_GIT_PULL_RC:-0}" ;;
  *) exit 0 ;;
esac
'@ | Set-Content -Path $stubPath -Encoding utf8NoBOM
        & chmod +x $stubPath
    }
}

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "dotfiles-update-test-$([guid]::NewGuid())"
$originalPath = $env:PATH
$locationPushed = $false
try {
    New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
    Push-Location ([System.IO.Path]::GetTempPath())
    $locationPushed = $true

    $binDir = Join-Path $tempDir 'bin'
    New-GitStub -Directory $binDir
    $separator = [System.IO.Path]::PathSeparator
    $env:PATH = "$binDir$separator$originalPath"

    $env:DOTFILES_GIT_LOG = Join-Path $tempDir 'git.log'
    $env:DOTFILES_GIT_IN_REPO = '1'
    $env:DOTFILES_GIT_BRANCH = 'main'
    $env:DOTFILES_GIT_DETACHED = '0'
    $env:DOTFILES_GIT_STATUS = '__CLEAN__'
    $env:DOTFILES_GIT_PULL_RC = '0'

    $repo = Join-Path $tempDir 'repo'
    $marker = Join-Path $tempDir 'bootstrapped'
    New-Item -Path $repo -ItemType Directory -Force | Out-Null
    Set-Content -Path (Join-Path $repo 'bootstrap.ps1') -Encoding Ascii `
        -Value "Set-Content -LiteralPath '$marker' -Value 'yes'"

    function Reset-GitLog {
        Remove-Item -LiteralPath $env:DOTFILES_GIT_LOG -Force -ErrorAction SilentlyContinue
    }

    # ── help ────────────────────────────────────────────────────────────────
    $usage = Get-CapturedOutput { Show-Usage }
    Assert-True ($usage.Contains('usage: scripts\update.ps1')) 'usage text is missing the usage line'
    Assert-True (Invoke-Update -Dir $repo -Help) '-Help should succeed'

    # ── not a Git work tree ─────────────────────────────────────────────────
    $env:DOTFILES_GIT_IN_REPO = '0'
    Reset-GitLog
    $output = Get-CapturedOutput { Invoke-Update -Dir $repo -SkipBootstrap }
    Assert-True ($output.Contains('Not inside a Git work tree')) 'non-repository message missing'
    Assert-True (-not (Test-Path -LiteralPath $marker)) 'bootstrap.ps1 ran for a non-repository checkout'
    $env:DOTFILES_GIT_IN_REPO = '1'

    # ── detached HEAD ───────────────────────────────────────────────────────
    $env:DOTFILES_GIT_DETACHED = '1'
    $output = Get-CapturedOutput { Invoke-Update -Dir $repo -SkipBootstrap }
    Assert-True ($output.Contains('detached')) 'detached-HEAD message missing'
    $env:DOTFILES_GIT_DETACHED = '0'

    # ── wrong branch ────────────────────────────────────────────────────────
    $env:DOTFILES_GIT_BRANCH = 'develop'
    $output = Get-CapturedOutput { Invoke-Update -Dir $repo -SkipBootstrap -ExpectedBranch 'main' }
    Assert-True ($output.Contains("expected 'main'")) 'branch-mismatch message missing'
    $env:DOTFILES_GIT_BRANCH = 'main'

    # ── dirty tree ──────────────────────────────────────────────────────────
    $env:DOTFILES_GIT_STATUS = ' M config/bash/.bashrc'
    $output = Get-CapturedOutput { Invoke-Update -Dir $repo -SkipBootstrap }
    Assert-True ($output.Contains('not clean')) 'dirty-tree message missing'
    $env:DOTFILES_GIT_STATUS = '__CLEAN__'

    # ── clean main: pull + bootstrap ────────────────────────────────────────
    Reset-GitLog
    $ok = Invoke-Update -Dir $repo
    Assert-True $ok 'a clean main checkout should succeed'
    Assert-True (Test-Path -LiteralPath $marker) 'bootstrap.ps1 did not run'
    $log = @(Get-Content -LiteralPath $env:DOTFILES_GIT_LOG)
    Assert-True (@($log | Where-Object { $_ -like '*pull --ff-only*' }).Count -ge 1) 'git pull --ff-only was not invoked'

    # ── -SkipBootstrap: pull only ───────────────────────────────────────────
    Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue
    $ok = Invoke-Update -Dir $repo -SkipBootstrap
    Assert-True $ok '-SkipBootstrap should succeed'
    Assert-True (-not (Test-Path -LiteralPath $marker)) '-SkipBootstrap must not run bootstrap.ps1'
    $output = Get-CapturedOutput { Invoke-Update -Dir $repo -SkipBootstrap }
    Assert-True ($output.Contains('Skipping bootstrap.ps1')) 'skip message missing'

    # ── a failed pull aborts before bootstrap ───────────────────────────────
    Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue
    $env:DOTFILES_GIT_PULL_RC = '1'
    $ok = Invoke-Update -Dir $repo
    Assert-True (-not $ok) 'a failed pull must fail the update'
    Assert-True (-not (Test-Path -LiteralPath $marker)) 'bootstrap.ps1 must not run after a failed pull'
    $env:DOTFILES_GIT_PULL_RC = '0'
} finally {
    $env:PATH = $originalPath
    foreach ($name in @(
        'DOTFILES_GIT_LOG',
        'DOTFILES_GIT_IN_REPO',
        'DOTFILES_GIT_BRANCH',
        'DOTFILES_GIT_DETACHED',
        'DOTFILES_GIT_STATUS',
        'DOTFILES_GIT_PULL_RC'
    )) {
        Remove-Item "Env:$name" -ErrorAction SilentlyContinue
    }
    if ($locationPushed) {
        Pop-Location
    }
    if (Test-Path -LiteralPath $tempDir) {
        Remove-Item -LiteralPath $tempDir -Recurse -Force
    }
}

Write-Host 'PASS: update-script.Tests.ps1'
# The suite intentionally runs a failing `git pull` stub. Clear its exit status
# so the GitHub Actions PowerShell runner does not mark this successful test
# script as failed after it returns.
$global:LASTEXITCODE = 0
