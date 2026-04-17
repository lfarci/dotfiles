#!/usr/bin/env bash
# WSL (Windows Subsystem for Linux) setup.
# WSL runs a Linux distro; source the matching distro script for packages.

WSL_DISTRO_ID="$(. /etc/os-release 2>/dev/null && echo "${ID:-ubuntu}")"
WSL_OS_SCRIPT="$DOTFILES_DIR/os/$WSL_DISTRO_ID/install.sh"

if [[ -f "$WSL_OS_SCRIPT" ]]; then
  log "WSL distro: $WSL_DISTRO_ID — sourcing $WSL_OS_SCRIPT"
  # shellcheck source=/dev/null
  source "$WSL_OS_SCRIPT"
else
  warn "No OS script for WSL distro '$WSL_DISTRO_ID'; skipping package install"
fi
