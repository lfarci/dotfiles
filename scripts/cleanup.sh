#!/usr/bin/env bash
#
# Reclaim disk space used by stale bootstrap backups.
#
# Conservative by design: it only ever considers directories directly under
# $HOME named .dotfiles_backup_<14-digit timestamp>[.<n>]. Directories newer
# than the age threshold, unrecognized names, symlinks, and everything outside
# $HOME are left alone. It is a dry run unless --apply is given.
set -euo pipefail

log()  { printf "[cleanup] %s\n" "$*"; }
warn() { printf "[cleanup][warn] %s\n" "$*" >&2; }

MIN_AGE_DAYS=30
APPLY=0
SHOW_HELP=0

usage() {
  cat <<'EOF'
usage: scripts/cleanup.sh [--apply] [--min-age-days <days>] [-h|--help]

Reclaim disk space from stale bootstrap backup directories.

Target: directories directly under $HOME named
  .dotfiles_backup_<YYYYMMDDHHMMSS>[.<n>]
created by bootstrap.sh before it replaces a config file. Only directories
whose modification time is more than --min-age-days in the past are considered.

Safety:
  * Dry run by default; pass --apply to actually delete.
  * Never follows symlinks and never touches paths outside $HOME.
  * Ignores unrecognized names (e.g. .dotfiles_backup_notes).
  * Does not touch ~/.config, ~/.local, git worktrees, or session data.

Options:
  --apply               Delete the listed directories (default: dry run).
  --min-age-days <days> Only remove backups older than <days>. Default: 30.
  -h, --help            Show this help and exit.
EOF
}

parse_args() {
  MIN_AGE_DAYS=30
  APPLY=0
  SHOW_HELP=0

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --apply)
        APPLY=1
        shift
        ;;
      --min-age-days)
        if [[ "$#" -lt 2 ]]; then
          warn "--min-age-days requires a number"
          return 1
        fi
        MIN_AGE_DAYS="$2"
        shift 2
        ;;
      -h|--help)
        SHOW_HELP=1
        shift
        ;;
      *)
        warn "Unknown argument: $1"
        usage >&2
        return 1
        ;;
    esac
  done

  if [[ ! "$MIN_AGE_DAYS" =~ ^[0-9]+$ ]]; then
    warn "--min-age-days must be a non-negative integer, got: $MIN_AGE_DAYS"
    return 1
  fi
}

# Refuse to run against a HOME that could point somewhere catastrophic.
require_safe_home() {
  if [[ -z "${HOME:-}" ]]; then
    warn "HOME is not set; refusing to run."
    return 1
  fi
  if [[ "$HOME" != /* ]]; then
    warn "HOME is not an absolute path ('$HOME'); refusing to run."
    return 1
  fi
  if [[ "$HOME" == "/" ]]; then
    warn "HOME points at the filesystem root; refusing to run."
    return 1
  fi
  if [[ ! -d "$HOME" ]]; then
    warn "HOME is not a directory: $HOME"
    return 1
  fi
}

# bootstrap.sh names every backup with a 14-digit timestamp, sometimes with a
# numeric collision suffix. Anything else is not ours to remove.
is_managed_backup() {
  [[ "$1" =~ ^\.dotfiles_backup_[0-9]{14}(\.[0-9]+)?$ ]]
}

# True when the directory is older than $2 days, using find's portable -mtime
# test (24-hour granularity). `-mtime +N` matches a modification time strictly
# more than N days ago.
backup_is_old() {
  local path="$1" days="$2" matches
  matches="$(find "$path" -maxdepth 0 -mtime "+$days" -print 2>/dev/null)" || true
  [[ -n "$matches" ]]
}

# Print each managed, old-enough backup directory, one per line.
list_backups() {
  local dir base
  shopt -s nullglob
  for dir in "$HOME"/.dotfiles_backup_*; do
    [[ -d "$dir" && ! -L "$dir" ]] || continue
    base="$(basename "$dir")"
    is_managed_backup "$base" || continue
    backup_is_old "$dir" "$MIN_AGE_DAYS" || continue
    printf '%s\n' "$dir"
  done
  shopt -u nullglob
}

# Remove a single backup, re-checking every guard so a caller cannot pass an
# unexpected path by mistake.
delete_backup() {
  local dir="$1" base parent
  base="$(basename "$dir")"
  parent="$(dirname "$dir")"

  if [[ "$parent" != "$HOME" ]]; then
    warn "Refusing to remove path outside HOME: $dir"
    return 1
  fi
  if ! is_managed_backup "$base"; then
    warn "Refusing to remove unrecognized name: $base"
    return 1
  fi
  if [[ -L "$dir" ]]; then
    warn "Refusing to remove symlink: $dir"
    return 1
  fi

  rm -rf -- "$dir"
  log "Removed $dir"
}

main() {
  if ! parse_args "$@"; then
    return 1
  fi

  if [[ "$SHOW_HELP" -eq 1 ]]; then
    usage
    return 0
  fi

  if ! require_safe_home; then
    return 1
  fi

  local candidates=() dir
  while IFS= read -r dir; do
    candidates+=("$dir")
  done < <(list_backups)

  local mode="dry run"
  if [[ "$APPLY" -eq 1 ]]; then
    mode="apply"
  fi

  log "HOME:        $HOME"
  log "Minimum age: $MIN_AGE_DAYS day(s)"
  log "Mode:        $mode"

  if [[ "${#candidates[@]}" -eq 0 ]]; then
    log "No stale bootstrap backups found."
    return 0
  fi

  log "Found ${#candidates[@]} stale bootstrap backup(s):"
  local candidate
  for candidate in "${candidates[@]}"; do
    printf '  %s\n' "$candidate"
  done

  if [[ "$APPLY" -ne 1 ]]; then
    log "Dry run: nothing was removed. Re-run with --apply to delete these directories."
    return 0
  fi

  local failed=0
  for candidate in "${candidates[@]}"; do
    if ! delete_backup "$candidate"; then
      failed=1
    fi
  done

  if [[ "$failed" -ne 0 ]]; then
    warn "Some directories could not be removed."
    return 1
  fi

  log "Removed ${#candidates[@]} stale bootstrap backup(s)."
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
