#!/bin/sh
set -e

sudo apt-get update
sudo apt-get install -y \
  git \
  curl \
  fzf \
  ripgrep \
  powerline \
  fonts-powerline \
  bash-completion

ln -sf "$PWD/.bashrc" "$HOME/.bashrc"
ln -sf "$PWD/.bash_aliases" "$HOME/.bash_aliases"
