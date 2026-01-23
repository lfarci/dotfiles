#!/usr/bin/env bash
set -euo pipefail

log() { printf "[dotfiles] %s\n" "$*"; }
warn() { printf "[dotfiles][warn] %s\n" "$*" >&2; }

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/.dotfiles_backup_$(date +%Y%m%d%H%M%S)"

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
    ".config/Code/User:.config/Code/User"
    ".config/gh/config.yml:.config/gh/config.yml"
    ".azure/config:.azure/config"
  )

  local entry src dst
  for entry in "${mappings[@]}"; do
    src="${entry%%:*}"
    dst="${entry#*:}"
    backup_and_link "$src" "$dst"
  done
}

link_all
