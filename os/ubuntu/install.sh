#!/usr/bin/env bash

install_packages() {
  local packages_file="$DOTFILES_DIR/packages/apt.txt"
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

  log "Installing apt packages..."
  if ! "${sudo_cmd[@]}" env SYSTEMD_OFFLINE=1 apt-get update; then
    warn "apt-get update failed; skipping package install"
    return
  fi

  if ! "${sudo_cmd[@]}" env SYSTEMD_OFFLINE=1 apt-get install -y "${packages[@]}"; then
    warn "apt-get install failed"
  fi
}

install_gh_cli() {
  if command -v gh >/dev/null 2>&1; then
    log "gh already installed"
    return
  fi

  local sudo_cmd=()
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
      sudo_cmd=(sudo)
    else
      warn "sudo not found; skipping gh install"
      return
    fi
  fi

  log "Installing GitHub CLI..."
  if ! curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | \
       "${sudo_cmd[@]}" gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg; then
    warn "Failed to add GitHub CLI GPG key"
    return
  fi

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] \
https://cli.github.com/packages stable main" | \
    "${sudo_cmd[@]}" tee /etc/apt/sources.list.d/github-cli.list > /dev/null

  if "${sudo_cmd[@]}" env SYSTEMD_OFFLINE=1 apt-get update && \
     "${sudo_cmd[@]}" env SYSTEMD_OFFLINE=1 apt-get install -y gh; then
    log "Installed GitHub CLI"
  else
    warn "Failed to install GitHub CLI"
  fi
}

install_terraform() {
  if command -v terraform >/dev/null 2>&1; then
    log "terraform already installed"
    return
  fi

  local sudo_cmd=()
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
      sudo_cmd=(sudo)
    else
      warn "sudo not found; skipping terraform install"
      return
    fi
  fi

  log "Installing Terraform..."
  if ! curl -fsSL https://apt.releases.hashicorp.com/gpg | \
       "${sudo_cmd[@]}" gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg; then
    warn "Failed to add HashiCorp GPG key"
    return
  fi

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
https://apt.releases.hashicorp.com $(. /etc/os-release && echo "$VERSION_CODENAME") main" | \
    "${sudo_cmd[@]}" tee /etc/apt/sources.list.d/hashicorp.list > /dev/null

  if "${sudo_cmd[@]}" env SYSTEMD_OFFLINE=1 apt-get update && \
     "${sudo_cmd[@]}" env SYSTEMD_OFFLINE=1 apt-get install -y terraform; then
    log "Installed Terraform"
  else
    warn "Failed to install Terraform"
  fi
}

install_azure_cli() {
  if command -v az >/dev/null 2>&1; then
    log "azure-cli already installed"
    return
  fi

  local sudo_cmd=()
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
      sudo_cmd=(sudo)
    else
      warn "sudo not found; skipping azure-cli install"
      return
    fi
  fi

  log "Installing Azure CLI..."
  if ! curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | \
       "${sudo_cmd[@]}" gpg --dearmor -o /usr/share/keyrings/microsoft-archive-keyring.gpg; then
    warn "Failed to add Microsoft GPG key"
    return
  fi

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/microsoft-archive-keyring.gpg] \
https://packages.microsoft.com/repos/azure-cli/ $(. /etc/os-release && echo "$VERSION_CODENAME") main" | \
    "${sudo_cmd[@]}" tee /etc/apt/sources.list.d/azure-cli.list > /dev/null

  if "${sudo_cmd[@]}" env SYSTEMD_OFFLINE=1 apt-get update && \
     "${sudo_cmd[@]}" env SYSTEMD_OFFLINE=1 apt-get install -y azure-cli; then
    log "Installed Azure CLI"
  else
    warn "Failed to install Azure CLI"
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
  if ! curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
       "${sudo_cmd[@]}" gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg; then
    warn "Failed to add Docker GPG key"
    return
  fi

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    "${sudo_cmd[@]}" tee /etc/apt/sources.list.d/docker.list > /dev/null

  if "${sudo_cmd[@]}" env SYSTEMD_OFFLINE=1 apt-get update && \
     "${sudo_cmd[@]}" env SYSTEMD_OFFLINE=1 apt-get install -y \
       docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
    "${sudo_cmd[@]}" systemctl enable --now docker
    "${sudo_cmd[@]}" usermod -aG docker "$USER" && log "Added $USER to docker group"
    log "Installed Docker"
  else
    warn "Failed to install Docker"
  fi
}

install_packages
install_gh_cli
install_terraform
install_azure_cli
install_docker
