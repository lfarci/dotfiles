#!/usr/bin/env bash
set -euo pipefail

log()  { printf "[dotfiles] %s\n" "$*"; }
warn() { printf "[dotfiles][warn] %s\n" "$*" >&2; }

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR=""

if [[ "${EUID:-$(id -u)}" -eq 0 && "${DOTFILES_ALLOW_ROOT:-0}" != "1" ]]; then
  warn "Do not run as root; this script links into \$HOME and installs user tools."
  warn "Re-run without sudo or set DOTFILES_ALLOW_ROOT=1 to override."
  exit 1
fi

ensure_backup_dir() {
  if [[ -n "$BACKUP_DIR" ]]; then
    return 0
  fi

  local base candidate suffix
  base="$HOME/.dotfiles_backup_$(date +%Y%m%d%H%M%S)"
  candidate="$base"
  suffix=0
  # mkdir itself reserves the name atomically. Never separate an existence
  # check from creation: concurrent bootstrap runs could otherwise choose the
  # same directory and mix their backups.
  while ! mkdir "$candidate" 2>/dev/null; do
    [[ -e "$candidate" ]] || return 1
    suffix=$((suffix + 1))
    candidate="$base.$suffix"
  done

  BACKUP_DIR="$candidate"
}

# Mirror the destination's path structure inside BACKUP_DIR so that
# destinations sharing a basename (e.g. two settings.json files) cannot
# overwrite each other's backup.
backup_path_for() {
  local dst="$1" relative

  if [[ "$dst" == "$HOME"/* ]]; then
    relative="${dst#"$HOME"/}"
  else
    relative="${dst#/}"
  fi

  printf '%s\n' "$BACKUP_DIR/$relative"
}

backup_and_link() {
  local src="$DOTFILES_DIR/$1"
  local dst="$HOME/$2"

  if [[ ! -e "$src" ]]; then
    warn "Source missing: $src"
    return 0
  fi

  mkdir -p "$(dirname "$dst")"

  if [[ -e "$dst" || -L "$dst" ]]; then
    if [[ -L "$dst" ]]; then
      local current target
      current="$(readlink -f "$dst" 2>/dev/null || true)"
      target="$(readlink -f "$src" 2>/dev/null || true)"
      if [[ -n "$current" && -n "$target" && "$current" == "$target" ]]; then
        return 0
      fi
    fi

    if ! ensure_backup_dir; then
      warn "Could not create backup directory for $dst; leaving it untouched and skipping link"
      return 1
    fi

    local backup_dst
    backup_dst="$(backup_path_for "$dst")"

    if ! mkdir -p "$(dirname "$backup_dst")"; then
      warn "Could not create backup directory for $dst; leaving it untouched and skipping link"
      return 1
    fi

    # Never delete the destination as a fallback: if it cannot be moved it is
    # left exactly as it was, and the link is not created.
    if ! mv "$dst" "$backup_dst"; then
      warn "Failed to back up $dst; leaving it untouched and skipping link"
      return 1
    fi

    log "Backed up $dst to $backup_dst"
  fi

  ln -sfn "$src" "$dst"
  log "Linked $dst -> $src"
}

# Link each "source:destination" mapping, continuing past individual failures so
# one un-backupable destination cannot stop the remaining links.
link_mappings() {
  local failed=0 entry src dst

  for entry in "$@"; do
    src="${entry%%:*}"
    dst="${entry#*:}"
    if ! backup_and_link "$src" "$dst"; then
      failed=1
    fi
  done

  if [[ "$failed" -ne 0 ]]; then
    warn "One or more configs could not be linked; existing files were left untouched"
    return 1
  fi
}

link_all() {
  link_mappings \
    "config/bash/.bashrc:.bashrc" \
    "config/bash/.bash_aliases:.bash_aliases" \
    "config/git/.gitconfig:.gitconfig" \
    "config/ohmyposh/theme.omp.json:.config/ohmyposh/theme.omp.json" \
    "config/ghostty/config.ghostty:.config/ghostty/config.ghostty" \
    "config/vscode/settings.json:.config/Code/User/settings.json" \
    "config/vscode/keybindings.json:.config/Code/User/keybindings.json" \
    "config/git/.gitignore_global:.gitignore_global" \
    "config/bash/.inputrc:.inputrc" \
    "config/agents:.agents" \
    "config/agents/skills:.copilot/skills" \
    "config/claude/settings.json:.claude/settings.json" \
    "config/opencode/opencode.json:.config/opencode/opencode.json" \
    "config/opencode/themes:.config/opencode/themes"
}

# Copy a "seed:source:destination" entry into $HOME only when the destination
# does not exist. Used for files a client owns and rewrites after first
# creation (the TUI replaces cli.json atomically on every settings change), so
# a symlink would be destroyed and a re-link would restore a stale copy over
# the live preferences.
seed_if_missing() {
  local src="$DOTFILES_DIR/$1"
  local dst="$HOME/$2"

  if [[ ! -e "$src" ]]; then
    warn "Source missing: $src"
    return 0
  fi

  if [[ -e "$dst" || -L "$dst" ]]; then
    log "Seed destination exists, leaving untouched: $dst"
    return 0
  fi

  mkdir -p "$(dirname "$dst")"
  if ! cp "$src" "$dst"; then
    warn "Failed to seed $dst"
    return 1
  fi
  log "Seeded $dst"
}

# Seed entries carry a "seed:" prefix so the mapping-sources test can tell
# them apart from symlink mappings.
seed_all() {
  local failed=0 entry spec src dst

  # The list intentionally starts with a single entry and grows as more seed
  # files appear; the loop shape keeps seeding uniform with link_mappings.
  # shellcheck disable=SC2043
  for entry in \
    "seed:config/opencode/cli.json:.config/opencode/cli.json"; do
    spec="${entry#seed:}"
    src="${spec%%:*}"
    dst="${spec#*:}"
    if ! seed_if_missing "$src" "$dst"; then
      failed=1
    fi
  done

  if [[ "$failed" -ne 0 ]]; then
    warn "One or more configs could not be seeded"
    return 1
  fi
}

install_oh_my_posh() {
  if command -v oh-my-posh >/dev/null 2>&1; then
    log "oh-my-posh already installed"
    return
  fi

  local req
  for req in curl unzip; do
    if ! command -v "$req" >/dev/null 2>&1; then
      warn "$req not found; skipping oh-my-posh install"
      return
    fi
  done

  local install_dir="$HOME/.local/bin"
  mkdir -p "$install_dir"
  case ":$PATH:" in
    *":$install_dir:"*) ;;
    *) export PATH="$PATH:$install_dir" ;;
  esac

  if curl -fsSL https://ohmyposh.dev/install.sh | bash -s -- -d "$install_dir"; then
    log "Installed oh-my-posh to $install_dir"
  else
    warn "Failed to install oh-my-posh"
  fi
}

install_opencode() {
  if command -v opencode >/dev/null 2>&1; then
    log "opencode already installed"
    return
  fi

  if ! command -v curl >/dev/null 2>&1; then
    warn "curl not found; skipping opencode install"
    return
  fi

  # --no-modify-path keeps the installer from editing shell config files:
  # ~/.bashrc is a symlink to the tracked config/bash/.bashrc, so the installer
  # must not append to it. PATH is managed by config/bash/.bashrc instead.
  log "Installing OpenCode CLI..."
  if curl -fsSL https://opencode.ai/v2/install | bash -s -- --no-modify-path; then
    log "Installed OpenCode CLI"
  else
    warn "Failed to install OpenCode CLI"
  fi
}

detect_os() {
  if grep -qi microsoft /proc/version 2>/dev/null; then
    echo "windows"
    return
  fi
  if [[ -f /etc/os-release ]]; then
    # shellcheck source=/dev/null
    local id
    id="$(. /etc/os-release && echo "${ID:-}")"
    echo "$id"
    return
  fi
  echo "unknown"
}

install_skills() {
  if ! command -v npx >/dev/null 2>&1; then
    warn "npx not found; skipping skills restore"
    return
  fi

  local agents_dir="$HOME/.agents"
  local lock_file="$agents_dir/.skill-lock.json"
  if [[ ! -f "$lock_file" ]]; then
    log "No .skill-lock.json found; skipping skills restore"
    return
  fi

  # `experimental_install` restores from ./skills-lock.json into ./.agents/skills/,
  # so stage a directory whose .agents points at the tracked store and hand it the
  # tracked lock verbatim (no hashes are recomputed or invented).
  local staging
  if ! staging="$(mktemp -d)"; then
    warn "Skills restore failed: cannot create staging directory"
    return
  fi

  if ! ln -s "$agents_dir" "$staging/.agents" 2>/dev/null; then
    warn "Skills restore failed: cannot create staging symlink"
    rm -rf "$staging"
    return
  fi

  cp "$lock_file" "$staging/skills-lock.json"

  log "Restoring skills from .skill-lock.json..."
  if (cd "$staging" && npx skills experimental_install -y); then
    log "Skills restored"
  else
    warn "Skills restore failed"
  fi

  rm -rf "$staging"
}

install_nvm_node() {
  local nvm_dir="${NVM_DIR:-$HOME/.nvm}"

  if [[ ! -d "$nvm_dir" ]]; then
    log "Installing nvm..."
    if ! curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash; then
      warn "Failed to install nvm"
      return
    fi
    log "Installed nvm"
  else
    log "nvm already installed"
  fi

  export NVM_DIR="$nvm_dir"
  # shellcheck source=/dev/null
  [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"

  if ! type nvm &>/dev/null; then
    warn "nvm not available after install; skipping Node LTS install"
    return
  fi

  log "Installing latest Node LTS..."
  if nvm install --lts && nvm use --lts; then
    log "Installed Node LTS: $(node --version)"
  else
    warn "Failed to install Node LTS"
  fi
}

install_vscode_extensions() {
  local extensions_file="$DOTFILES_DIR/config/vscode/extensions.txt"
  if [[ ! -f "$extensions_file" ]]; then
    warn "VS Code extension list not found: $extensions_file"
    return 1
  fi

  if ! command -v code >/dev/null 2>&1; then
    if [[ "${OS:-$(detect_os)}" == "windows" ]]; then
      warn "VS Code CLI 'code' not found on PATH"
      warn "Install VS Code on Windows, reopen the terminal, and rerun bootstrap"
      return 1
    fi

    warn "VS Code CLI 'code' not found; skipping extension install"
    return
  fi

  local extensions=()
  local line trimmed
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    trimmed="${line#"${line%%[![:space:]]*}"}"
    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
    [[ -n "$trimmed" ]] && extensions+=("$trimmed")
  done < "$extensions_file"

  if [[ "${#extensions[@]}" -eq 0 ]]; then
    warn "No VS Code extensions listed in $extensions_file"
    return
  fi

  local failed=()
  local extension
  log "Installing VS Code extensions..."
  for extension in "${extensions[@]}"; do
    log "  $extension"
    if ! code --install-extension "$extension" --force; then
      warn "  failed to install $extension"
      failed+=("$extension")
    fi
  done

  if [[ "${#failed[@]}" -gt 0 ]]; then
    warn "Failed to install VS Code extensions: ${failed[*]}"
    return 1
  fi
}

main() {
  OS="${DOTFILES_OS:-$(detect_os)}"
  log "Detected OS: $OS"

  local os_script="$DOTFILES_DIR/os/$OS/install.sh"
  if [[ -f "$os_script" ]]; then
    # shellcheck source=/dev/null
    source "$os_script"
  else
    warn "No OS script found for '$OS'; skipping package install"
  fi

  install_oh_my_posh
  install_opencode
  link_all
  seed_all
  install_nvm_node
  install_vscode_extensions
  install_skills
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
