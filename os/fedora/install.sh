#!/usr/bin/env bash

install_packages() {
  local packages_file="$DOTFILES_DIR/packages/dnf.txt"
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
    [[ -n "$trimmed" ]] && packages+=("$trimmed")
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

  log "Installing dnf packages..."
  if ! "${sudo_cmd[@]}" dnf install -y "${packages[@]}"; then
    warn "dnf install failed"
  fi
}

install_ghostty() {
  if command -v ghostty >/dev/null 2>&1; then
    log "ghostty already installed"
    return
  fi

  local sudo_cmd=()
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
      sudo_cmd=(sudo)
    else
      warn "sudo not found; skipping ghostty install"
      return
    fi
  fi

  log "Installing ghostty via COPR..."
  if "${sudo_cmd[@]}" dnf copr enable -y scottames/ghostty && \
     "${sudo_cmd[@]}" dnf install -y ghostty; then
    log "Installed ghostty"
  else
    warn "Failed to install ghostty"
  fi
}

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    log "docker already installed"
    return
  fi

  local sudo_cmd=()
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
      sudo_cmd=(sudo)
    else
      warn "sudo not found; skipping docker install"
      return
    fi
  fi

  log "Installing Docker..."
  if "${sudo_cmd[@]}" dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo && \
     "${sudo_cmd[@]}" dnf install -y \
       docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
    "${sudo_cmd[@]}" systemctl enable --now docker
    "${sudo_cmd[@]}" usermod -aG docker "$USER" && log "Added $USER to docker group"
    log "Installed Docker"
  else
    warn "Failed to install Docker"
  fi
}

install_packages
install_ghostty
install_docker
