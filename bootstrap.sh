#!/bin/sh
set -e

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

ensure_apt_packages() {
  sudo apt-get update
  sudo apt-get install -y "$@"
}

read_package_list() {
  package_file="$1"
  packages=""
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ""|\#*) continue ;;
      *) packages="$packages $line" ;;
    esac
  done < "$package_file"
  echo "$packages"
}

add_apt_repo() {
  keyring="$1"
  keyring_path="$2"
  source_line="$3"
  source_path="$4"

  if [ ! -f "$source_path" ]; then
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL "$keyring" | gpg --dearmor | sudo tee "$keyring_path" > /dev/null
    echo "$source_line" | sudo tee "$source_path" > /dev/null
    sudo apt-get update
  fi
}

package_list="$(read_package_list "$script_dir/bootstrap.packages")"
ensure_apt_packages $package_list

if ! has_cmd gh; then
  add_apt_repo \
    https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    /etc/apt/sources.list.d/github-cli.list
  ensure_apt_packages gh
fi

if ! has_cmd az; then
  add_apt_repo \
    https://packages.microsoft.com/keys/microsoft.asc \
    /etc/apt/keyrings/microsoft.gpg \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ $(lsb_release -cs) main" \
    /etc/apt/sources.list.d/azure-cli.list
  ensure_apt_packages azure-cli
fi

if ! has_cmd terraform; then
  add_apt_repo \
    https://apt.releases.hashicorp.com/gpg \
    /etc/apt/keyrings/hashicorp.gpg \
    "deb [signed-by=/etc/apt/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
    /etc/apt/sources.list.d/hashicorp.list
  ensure_apt_packages terraform
fi

if ! has_cmd azd; then
  azd_install="$(mktemp)"
  if curl -fsSL https://aka.ms/azd/install.sh -o "$azd_install"; then
    if head -n 1 "$azd_install" | grep -q "^#!"; then
      bash "$azd_install"
    else
      echo "Warning: azd install script did not look like a shell script; skipping."
    fi
  else
    echo "Warning: failed to download azd install script; skipping."
  fi
  rm -f "$azd_install"
fi

if ! has_cmd dotnet; then
  # Install into /usr/local to avoid per-user path setup.
  curl -fsSL https://dot.net/v1/dotnet-install.sh | sudo bash -s -- --install-dir /usr/local/dotnet --channel LTS
  if [ ! -x /usr/local/bin/dotnet ]; then
    sudo ln -s /usr/local/dotnet/dotnet /usr/local/bin/dotnet
  fi
fi

export NVM_DIR="$HOME/.nvm"
if [ ! -s "$NVM_DIR/nvm.sh" ]; then
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
fi
if ! has_cmd node; then
  # Use login shell so nvm is available for the install.
  bash -lc "source \"$NVM_DIR/nvm.sh\" && nvm install --lts && nvm use --lts"
fi

ln -sf "$PWD/.bashrc" "$HOME/.bashrc"
ln -sf "$PWD/.bash_aliases" "$HOME/.bash_aliases"
