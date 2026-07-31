#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "$DOTFILES_CODE_LOG"

for extension in ${DOTFILES_CODE_FAIL_IDS//;/ }; do
  if [[ "${2:-}" == "$extension" ]]; then
    exit 23
  fi
done
