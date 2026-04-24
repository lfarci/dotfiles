#Requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$DotfilesDir = $PSScriptRoot
$BackupDir = Join-Path $HOME ".dotfiles_backup_$(Get-Date -Format 'yyyyMMddHHmmss')"

function Log { param([string]$Msg) Write-Host "[dotfiles] $Msg" }
function Warn { param([string]$Msg) Write-Host "[dotfiles][warn] $Msg" -ForegroundColor Yellow }

# ── Symlink capability ──────────────────────────────────────────────────────

function Test-CanSymlink {
    $src = Join-Path $env:TEMP "dotfiles_src_$(Get-Random)"
    $link = Join-Path $env:TEMP "dotfiles_link_$(Get-Random)"
    try {
        New-Item -Path $src  -ItemType File         -Force | Out-Null
        New-Item -Path $link -ItemType SymbolicLink -Target $src -Force | Out-Null
        return $true
    }
    catch {
        return $false
    }
    finally {
        if (Test-Path $link) { Remove-Item $link -Force -ErrorAction SilentlyContinue }
        if (Test-Path $src) { Remove-Item $src  -Force -ErrorAction SilentlyContinue }
    }
}

if (-not (Test-CanSymlink)) {
    Warn "Cannot create symbolic links."
    Warn "Either enable Developer Mode (Settings > System > For developers)"
    Warn "or re-run this script as Administrator."
    exit 1
}

# ── PATH refresh ────────────────────────────────────────────────────────────

function Update-EnvPath {
    $machine = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine')
    $user = [System.Environment]::GetEnvironmentVariable('PATH', 'User')
    # Merge without clobbering any session-only additions already in $env:PATH
    $existing = $env:PATH -split ';' | Where-Object { $_ }
    $merged = (($machine, $user | Where-Object { $_ }) -join ';') -split ';' | Where-Object { $_ }
    $combined = ($existing + $merged | Select-Object -Unique) -join ';'
    $env:PATH = $combined
}

# ── Winget packages ─────────────────────────────────────────────────────────

function Install-WingetPackages {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Warn "winget not found; skipping package install."
        Warn "Install 'App Installer' from the Microsoft Store to get winget."
        return
    }

    $pkgFile = Join-Path $DotfilesDir 'packages\winget.txt'
    if (-not (Test-Path $pkgFile)) {
        Warn "Package list not found: $pkgFile"
        return
    }

    $packages = Get-Content $pkgFile |
    ForEach-Object { ($_ -replace '#.*$', '').Trim() } |
    Where-Object { $_ -ne '' }

    if (-not $packages) {
        Warn "No packages listed in $pkgFile"
        return
    }

    Log "Installing winget packages..."
    foreach ($pkg in $packages) {
        Log "  $pkg"
        winget install --id $pkg --exact --accept-source-agreements --accept-package-agreements --silent
        if ($LASTEXITCODE -ne 0) {
            Warn "  winget exited $LASTEXITCODE for $pkg (may already be installed)"
        }
    }

    Update-EnvPath
}

# ── Nerd Font ───────────────────────────────────────────────────────────────

function Install-NerdFont {
    if (-not (Get-Command oh-my-posh -ErrorAction SilentlyContinue)) {
        Warn "oh-my-posh not found after PATH refresh; skipping font install."
        Warn "Reopen the terminal and re-run to install the font, or run:"
        Warn "  oh-my-posh font install JetBrainsMono"
        return
    }

    Log "Installing JetBrainsMono Nerd Font..."
    oh-my-posh font install JetBrainsMono
    if ($LASTEXITCODE -ne 0) {
        Warn "Font install exited $LASTEXITCODE"
    }
}

function Install-VSCodeExtensions {
    if (-not (Get-Command code -ErrorAction SilentlyContinue)) {
        throw "VS Code CLI 'code' not found on PATH. Ensure VS Code is installed from the package list and PATH has been refreshed."
    }

    $extensionsFile = Join-Path $DotfilesDir 'config\vscode\extensions.txt'
    if (-not (Test-Path $extensionsFile)) {
        throw "VS Code extension list not found: $extensionsFile"
    }

    $extensions = Get-Content $extensionsFile |
    ForEach-Object { ($_ -replace '#.*$', '').Trim() } |
    Where-Object { $_ -ne '' }

    if (-not $extensions) {
        Warn "No VS Code extensions listed in $extensionsFile"
        return
    }

    $failed = New-Object System.Collections.Generic.List[string]

    Log "Installing VS Code extensions..."
    foreach ($extension in $extensions) {
        Log "  $extension"
        code --install-extension $extension
        if ($LASTEXITCODE -ne 0) {
            Warn "  extension install exited $LASTEXITCODE for $extension"
            $failed.Add($extension) | Out-Null
        }
    }

    if ($failed.Count -gt 0) {
        throw "Failed to install VS Code extensions: $($failed -join ', ')"
    }
}

# ── Symlink helpers ─────────────────────────────────────────────────────────

function Backup-AndLink {
    param(
        [string]$Src,
        [string]$Dst
    )

    if (-not (Test-Path $Src)) {
        Warn "Source missing: $Src"
        return
    }

    $parent = Split-Path $Dst -Parent
    if (-not (Test-Path $parent)) {
        New-Item -Path $parent -ItemType Directory -Force | Out-Null
    }

    if (Test-Path $Dst -PathType Any) {
        $existing = Get-Item $Dst -Force
        if ($existing.LinkType -eq 'SymbolicLink') {
            $target = ($existing.Target | Select-Object -First 1)
            if ($target -and ([System.IO.Path]::GetFullPath($target) -eq [System.IO.Path]::GetFullPath($Src))) {
                return
            }
        }

        # Mirror the destination's path structure inside BackupDir to avoid filename collisions
        $dstFull = [System.IO.Path]::GetFullPath($Dst)
        $homeFull = [System.IO.Path]::GetFullPath($HOME)
        if ($dstFull.StartsWith($homeFull, [System.StringComparison]::OrdinalIgnoreCase)) {
            $relative = $dstFull.Substring($homeFull.Length).TrimStart('\', '/')
        }
        else {
            $relative = $dstFull -replace '^[A-Za-z]:\\?', '' -replace '[:\\]', '_'
        }
        $backupDest = Join-Path $BackupDir $relative
        New-Item -Path (Split-Path $backupDest -Parent) -ItemType Directory -Force | Out-Null
        Move-Item -Path $Dst -Destination $backupDest -Force
        Log "Backed up $Dst to $backupDest"
    }

    New-Item -Path $Dst -ItemType SymbolicLink -Target $Src -Force | Out-Null
    Log "Linked $Dst -> $Src"
}

function Seed-GitConfigLocal {
    $src = Join-Path $DotfilesDir 'config\git\.gitconfig.local.example'
    $dst = Join-Path $HOME '.gitconfig.local'

    if (Test-Path $Dst -PathType Any) {
        return
    }

    if (-not (Test-Path $src -PathType Leaf)) {
        Warn "Local Git config example missing: $src"
        return
    }

    Copy-Item -Path $src -Destination $dst
    Log "Created $dst from $src"
}

function Get-WindowsTerminalSettingsPath {
    $candidates = @(
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json"
        "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    return $candidates[0]
}

function Link-All {
    $windowsTerminalSettingsPath = Get-WindowsTerminalSettingsPath
    $mappings = @(
        @{ Src = 'config\git\.gitconfig'; Dst = "$HOME\.gitconfig" }
        @{ Src = 'config\git\.gitignore_global'; Dst = "$HOME\.gitignore_global" }
        @{ Src = 'config\ohmyposh\theme.omp.json'; Dst = "$HOME\.config\ohmyposh\theme.omp.json" }
        @{ Src = 'config\vscode\settings.json'; Dst = "$env:APPDATA\Code\User\settings.json" }
        @{ Src = 'config\vscode\keybindings.json'; Dst = "$env:APPDATA\Code\User\keybindings.json" }
        @{ Src = 'config\windows-terminal\settings.json'; Dst = $windowsTerminalSettingsPath }
        @{ Src = 'config\agents'; Dst = "$HOME\.agents" }
        @{ Src = 'config\claude\settings.json'; Dst = "$HOME\.claude\settings.json" }
    )

    foreach ($m in $mappings) {
        $src = Join-Path $DotfilesDir $m.Src
        Backup-AndLink -Src $src -Dst $m.Dst
    }

    Seed-GitConfigLocal
}

# ── Skills restore ──────────────────────────────────────────────────────────

function Restore-Skills {
    if (-not (Get-Command npx -ErrorAction SilentlyContinue)) {
        Warn "npx not found; skipping skills restore."
        return
    }

    $lockFile = Join-Path $HOME '.agents\.skill-lock.json'
    if (-not (Test-Path $lockFile)) {
        Log "No .skill-lock.json found; skipping skills restore."
        return
    }

    Log "Restoring skills from .skill-lock.json..."
    Push-Location (Join-Path $HOME '.agents')
    try {
        npx skills experimental_install -y
        if ($LASTEXITCODE -ne 0) { Warn "Skills restore exited $LASTEXITCODE" }
        else { Log  "Skills restored." }
    }
    finally {
        Pop-Location
    }
}

# ── PowerShell profile ──────────────────────────────────────────────────────

function Add-OhMyPoshToProfile {
    param([string]$ProfilePath)

    $themePath = "$HOME\.config\ohmyposh\theme.omp.json"
    $ompInit = "oh-my-posh init pwsh --config `"$themePath`" | Invoke-Expression"

    $profileDir = Split-Path $ProfilePath -Parent
    if (-not (Test-Path $profileDir)) {
        New-Item -Path $profileDir -ItemType Directory -Force | Out-Null
    }
    if (-not (Test-Path $ProfilePath)) {
        New-Item -Path $ProfilePath -ItemType File -Force | Out-Null
        Log "Created profile: $ProfilePath"
    }

    $content = Get-Content $ProfilePath -Raw -ErrorAction SilentlyContinue
    if ($content -and $content.Contains('oh-my-posh')) {
        Log "oh-my-posh already configured in $ProfilePath"
        return
    }

    Add-Content -Path $ProfilePath -Value "`n# Oh My Posh`n$ompInit"
    Log "Configured oh-my-posh in $ProfilePath"
}

function Set-OhMyPoshProfile {
    if (-not (Get-Command oh-my-posh -ErrorAction SilentlyContinue)) {
        Warn "oh-my-posh not found; skipping profile setup."
        return
    }

    # Target both Windows PowerShell 5.1 and PowerShell 7+ profiles
    $profiles = @(
        "$HOME\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"
        "$HOME\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"
    )
    foreach ($p in $profiles) {
        Add-OhMyPoshToProfile -ProfilePath $p
    }
}

# ── Main ─────────────────────────────────────────────────────────────────────

Install-WingetPackages
Install-VSCodeExtensions
Install-NerdFont
Link-All
Restore-Skills
Set-OhMyPoshProfile

Log "Done! Restart your terminal for all changes to take effect."
Log "Windows Terminal settings are linked from config\\windows-terminal\\settings.json."
