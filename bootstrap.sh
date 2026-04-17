#!/usr/bin/env bash
set -euo pipefail

log()  { printf "[dotfiles] %s\n" "$*"; }
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
      local current target
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
    "config/bash/.bashrc:.bashrc"
    "config/bash/.bash_aliases:.bash_aliases"
    "config/git/.gitconfig:.gitconfig"
    "config/ohmyposh/theme.omp.json:.config/ohmyposh/theme.omp.json"
  )

  local entry src dst
  for entry in "${mappings[@]}"; do
    src="${entry%%:*}"
    dst="${entry#*:}"
    backup_and_link "$src" "$dst"
  done
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

OS="${DOTFILES_OS:-$(detect_os)}"
log "Detected OS: $OS"

OS_SCRIPT="$DOTFILES_DIR/os/$OS.sh"
if [[ -f "$OS_SCRIPT" ]]; then
  # shellcheck source=/dev/null
  source "$OS_SCRIPT"
else
  warn "No OS script found for '$OS'; skipping package install"
fi

install_oh_my_posh
link_all
