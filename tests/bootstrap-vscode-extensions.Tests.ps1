$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoDir = Split-Path $PSScriptRoot -Parent
. (Join-Path $RepoDir 'bootstrap.ps1')

$ExpectedExtensions = @(
    'catppuccin.catppuccin-vsc'
    'catppuccin.catppuccin-vsc-icons'
    'PKief.material-icon-theme'
    'ms-dotnettools.csharp'
    'stackbreak.comment-divider'
    'github.vscode-github-actions'
    'github.vscode-pull-request-github'
    'codezombiech.gitignore'
    'mermaidchart.vscode-mermaid-chart'
)

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw "FAIL: $Message"
    }
}

function New-CodeStub {
    param([string]$Directory)

    New-Item -Path $Directory -ItemType Directory -Force | Out-Null
    $isWindowsPlatform = $env:OS -eq 'Windows_NT'
    if ($isWindowsPlatform) {
        $stubPath = Join-Path $Directory 'code.cmd'
        @'
@echo off
echo %*>>"%DOTFILES_CODE_LOG%"
echo ;%DOTFILES_CODE_FAIL_IDS%; | %SystemRoot%\System32\findstr.exe /C:";%2;" >nul
if not errorlevel 1 exit /b 23
exit /b 0
'@ | Set-Content -Path $stubPath -Encoding Ascii
    } else {
        $stubPath = Join-Path $Directory 'code'
        @'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$DOTFILES_CODE_LOG"
for extension in ${DOTFILES_CODE_FAIL_IDS//;/ }; do
  if [[ "${2:-}" == "$extension" ]]; then
    exit 23
  fi
done
'@ | Set-Content -Path $stubPath -Encoding utf8NoBOM
        & chmod +x $stubPath
    }
}

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "dotfiles-vscode-test-$([guid]::NewGuid())"
$originalPath = $env:PATH
$originalDotfilesDir = $DotfilesDir
$locationPushed = $false
try {
    Push-Location ([System.IO.Path]::GetTempPath())
    $locationPushed = $true

    $binDir = Join-Path $tempDir 'bin'
    New-CodeStub -Directory $binDir
    $separator = [System.IO.Path]::PathSeparator
    $env:PATH = "$binDir$separator$originalPath"
    $env:DOTFILES_CODE_LOG = Join-Path $tempDir 'code.log'
    $env:DOTFILES_CODE_FAIL_IDS = ''

    Install-VSCodeExtensions

    $lines = @(Get-Content $env:DOTFILES_CODE_LOG)
    Assert-True ($lines.Count -eq $ExpectedExtensions.Count) "expected $($ExpectedExtensions.Count) code invocations"
    foreach ($extension in $ExpectedExtensions) {
        $expected = "--install-extension $extension --force"
        Assert-True (@($lines | Where-Object { $_ -eq $expected }).Count -eq 1) "missing or duplicate install for $extension"
    }

    Clear-Content $env:DOTFILES_CODE_LOG
    $env:DOTFILES_CODE_FAIL_IDS = 'ms-dotnettools.csharp;mermaidchart.vscode-mermaid-chart'
    $failureMessage = ''
    try {
        Install-VSCodeExtensions
        throw 'FAIL: expected extension installation to throw'
    } catch {
        $failureMessage = $_.Exception.Message
    }

    Assert-True ($failureMessage.Contains('ms-dotnettools.csharp')) 'aggregate error omitted ms-dotnettools.csharp'
    Assert-True ($failureMessage.Contains('mermaidchart.vscode-mermaid-chart')) 'aggregate error omitted mermaidchart.vscode-mermaid-chart'
    Assert-True (@(Get-Content $env:DOTFILES_CODE_LOG).Count -eq $ExpectedExtensions.Count) 'installer stopped before processing the full manifest'

    $fixtureRepo = Join-Path $tempDir 'repo'
    $fixtureConfig = Join-Path $fixtureRepo 'config\vscode'
    New-Item -Path $fixtureConfig -ItemType Directory -Force | Out-Null
    @'
# comment
  catppuccin.catppuccin-vsc  # inline comment

    PKief.material-icon-theme
'@ | Set-Content -Path (Join-Path $fixtureConfig 'extensions.txt') -Encoding Ascii
    $DotfilesDir = $fixtureRepo
    $env:DOTFILES_CODE_FAIL_IDS = ''
    Clear-Content $env:DOTFILES_CODE_LOG

    Install-VSCodeExtensions

    $fixtureLines = @(Get-Content $env:DOTFILES_CODE_LOG)
    Assert-True ($fixtureLines.Count -eq 2) 'comments, blank lines, or whitespace were not parsed correctly'
    Assert-True ($fixtureLines[0] -eq '--install-extension catppuccin.catppuccin-vsc --force') 'inline comments were not removed'
    Assert-True ($fixtureLines[1] -eq '--install-extension PKief.material-icon-theme --force') 'surrounding whitespace was not removed'

    $DotfilesDir = $originalDotfilesDir
    $emptyBin = Join-Path $tempDir 'empty-bin'
    New-Item -Path $emptyBin -ItemType Directory -Force | Out-Null
    $env:PATH = $emptyBin
    $missingCliMessage = ''
    try {
        Install-VSCodeExtensions
        throw 'FAIL: missing code CLI must throw'
    } catch {
        $missingCliMessage = $_.Exception.Message
    }
    Assert-True ($missingCliMessage.Contains("VS Code CLI 'code' not found")) 'missing code CLI error was not actionable'
} finally {
    $DotfilesDir = $originalDotfilesDir
    $env:PATH = $originalPath
    Remove-Item Env:DOTFILES_CODE_LOG -ErrorAction SilentlyContinue
    Remove-Item Env:DOTFILES_CODE_FAIL_IDS -ErrorAction SilentlyContinue
    if ($locationPushed) {
        Pop-Location
    }
    if (Test-Path $tempDir) {
        Remove-Item $tempDir -Recurse -Force
    }
}

Write-Host 'PASS: bootstrap-vscode-extensions.Tests.ps1'
