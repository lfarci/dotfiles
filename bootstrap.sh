#!/usr/bin/env bash
set -euo pipefail

log() { printf "[dotfiles] %s\n" "$*"; }
warn() { printf "[dotfiles][warn] %s\n" "$*" >&2; }

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/.dotfiles_backup_$(date +%Y%m%d%H%M%S)"

if [[ "${EUID:-$(id -u)}" -eq 0 && "${DOTFILES_ALLOW_ROOT:-0}" != "1" ]]; then
  warn "Do not run as root; this script links into \$HOME and installs user tools."
  warn "Re-run without sudo or set DOTFILES_ALLOW_ROOT=1 to override."
  exit 1
fi

backup_and_link() {
  local src="$DOTFILES_DIR/$1"
  local dst="$HOME/$2"

  if [[ ! -e "$src" ]]; then
    warn "Source missing: $src"
    return
  fi

  mkdir -p "$(dirname "$dst")"

  if [[ -e "$dst" || -L "$dst" ]]; then
    if [[ -L "$dst" ]]; then
      local current
      local target
      current="$(readlink -f "$dst" 2>/dev/null || true)"
      target="$(readlink -f "$src" 2>/dev/null || true)"
      if [[ -n "$current" && -n "$target" && "$current" == "$target" ]]; then
        return
      fi
    fi
    mkdir -p "$BACKUP_DIR"
    mv "$dst" "$BACKUP_DIR/" 2>/dev/null || rm -rf "$dst"
    log "Backed up $dst to $BACKUP_DIR"
  fi

  ln -sfn "$src" "$dst"
  log "Linked $dst -> $src"
}

link_all() {
  local mappings=(
    ".bashrc:.bashrc"
    ".bash_aliases:.bash_aliases"
    ".gitconfig:.gitconfig"
    ".config/ohmyposh/theme.omp.json:.config/ohmyposh/theme.omp.json"
  )

  local entry src dst
  for entry in "${mappings[@]}"; do
    src="${entry%%:*}"
    dst="${entry#*:}"
    backup_and_link "$src" "$dst"
  done
}

install_oh_my_posh_linux() {
  ensure_oh_my_posh_init() {
    local bashrc="$HOME/.bashrc"
    if [[ ! -f "$bashrc" ]]; then
      touch "$bashrc"
    fi
    if grep -Fq "oh-my-posh init bash" "$bashrc" 2>/dev/null; then
      log "oh-my-posh init already configured in $bashrc"
      return
    fi
    {
      cat <<'EOF'

# Oh My Posh prompt (Linux)
# Docs: https://ohmyposh.dev/docs/installation/prompt
if [[ $- == *i* ]] && command -v oh-my-posh >/dev/null 2>&1; then
  eval "$(oh-my-posh init bash --config "$HOME/.config/ohmyposh/theme.omp.json")"
fi
EOF
    } >> "$bashrc"
    log "Added oh-my-posh init to $bashrc"
  }

  if command -v oh-my-posh >/dev/null 2>&1; then
    ensure_oh_my_posh_init
    return
  fi

  if [[ "$(uname -s)" != "Linux" ]]; then
    return
  fi

  local req
  for req in curl unzip realpath dirname; do
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
    ensure_oh_my_posh_init
  else
    warn "Failed to install oh-my-posh"
  fi
}

install_packages_apt() {
  if [[ "$(uname -s)" != "Linux" ]]; then
    return
  fi

  if ! command -v apt-get >/dev/null 2>&1; then
    warn "apt-get not found; skipping package install"
    return
  fi

  local packages_file="$DOTFILES_DIR/bootstrap.packages"
  if [[ ! -f "$packages_file" ]]; then
    warn "Package list not found: $packages_file"
    return
  fi

  local packages=()
  local line trimmed
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    trimmed="${line#"${line%%[![:space:]]*}"}"
    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
    if [[ -n "$trimmed" ]]; then
      packages+=("$trimmed")
    fi
  done < "$packages_file"

  if [[ "${#packages[@]}" -eq 0 ]]; then
    warn "No packages listed in $packages_file"
    return
  fi

  local sudo_cmd=()
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
      sudo_cmd=(sudo)
    else
      warn "sudo not found; skipping package install"
      return
    fi
  fi

  log "Installing packages from $packages_file"
  if ! "${sudo_cmd[@]}" env SYSTEMD_OFFLINE=1 apt-get update; then
    warn "Package update failed; skipping apt install"
    return
  fi

  if ! "${sudo_cmd[@]}" env SYSTEMD_OFFLINE=1 apt-get install -y "${packages[@]}"; then
    warn "Package install failed"
  fi
}

install_packages_apt
link_all
install_oh_my_posh_linux
