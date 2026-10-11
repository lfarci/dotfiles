#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "$DOTFILES_GH_LOG"

if [[ "${1:-}" != "auth" || "${2:-}" != "git-credential" ]]; then
  exit 1
fi

cat >/dev/null

if [[ "${3:-}" == "get" ]]; then
  printf 'username=stub-user\n'
  printf 'password=stub-token\n'
fi
