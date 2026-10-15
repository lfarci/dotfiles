#!/usr/bin/env bash
#
# Update this dotfiles checkout and re-apply it.
#
# Pulling is intentionally narrow: HEAD must be attached, the branch must match
# --branch, and the working tree must be clean. Anything else stops before any
# network or file change so a surprise conflict never strands the live config.
set -euo pipefail

log()  { printf "[update] %s\n" "$*"; }
warn() { printf "[update][warn] %s\n" "$*" >&2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

EXPECTED_BRANCH="main"
RUN_BOOTSTRAP=1
SHOW_HELP=0

usage() {
  cat <<'EOF'
usage: scripts/update.sh [--branch <name>] [--no-bootstrap] [-h|--help]

Pull the latest commit for this dotfiles checkout and re-apply it.

Before touching anything the script verifies all of the following and stops
with an actionable message when one fails:

  * the script lives in a Git work tree
  * HEAD is attached to a branch (not detached)
  * the checked-out branch matches --branch (default: main)
  * the working tree is clean (no staged, unstaged, or untracked changes)

It then runs `git pull --ff-only` and, unless --no-bootstrap is given, re-runs
./bootstrap.sh from the repository root. Both steps are safe to re-run.

Options:
  --branch <name>  Branch to update. Default: main.
  --no-bootstrap   Pull only; do not re-run bootstrap.sh.
  -h, --help       Show this help and exit.
EOF
}

parse_args() {
  EXPECTED_BRANCH="main"
  RUN_BOOTSTRAP=1
  SHOW_HELP=0

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --branch)
        if [[ "$#" -lt 2 || -z "$2" ]]; then
          warn "--branch requires a branch name"
          return 1
        fi
        EXPECTED_BRANCH="$2"
        shift 2
        ;;
      --no-bootstrap)
        RUN_BOOTSTRAP=0
        shift
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
}

git_in_repo() {
  git -C "$DOTFILES_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

current_branch() {
  git -C "$DOTFILES_DIR" symbolic-ref --quiet --short HEAD 2>/dev/null
}

check_clean_tree() {
  local status
  status="$(git -C "$DOTFILES_DIR" status --porcelain)"
  if [[ -n "$status" ]]; then
    warn "Working tree is not clean; refusing to update."
    warn "Commit or stash the following changes and try again:"
    printf '%s\n' "$status" >&2
    return 1
  fi
}

check_preconditions() {
  local branch

  if ! git_in_repo; then
    warn "Not inside a Git work tree: $DOTFILES_DIR"
    warn "Clone the dotfiles repository and run this script from its checkout."
    return 1
  fi

  if ! branch="$(current_branch)"; then
    warn "HEAD is detached; refusing to update."
    warn "Check out the expected branch first: git -C \"$DOTFILES_DIR\" switch $EXPECTED_BRANCH"
    return 1
  fi

  if [[ "$branch" != "$EXPECTED_BRANCH" ]]; then
    warn "On branch '$branch' but expected '$EXPECTED_BRANCH'; refusing to update."
    warn "Switch with 'git switch $EXPECTED_BRANCH' or re-run with --branch '$branch'."
    return 1
  fi

  if ! check_clean_tree; then
    return 1
  fi
}

pull_latest() {
  log "Pulling latest '$EXPECTED_BRANCH' with --ff-only..."
  git -C "$DOTFILES_DIR" pull --ff-only
}

run_bootstrap() {
  local bootstrap="$DOTFILES_DIR/bootstrap.sh"
  if [[ ! -f "$bootstrap" ]]; then
    warn "Bootstrap script not found: $bootstrap"
    return 1
  fi

  log "Re-applying dotfiles: ./bootstrap.sh"
  ( cd "$DOTFILES_DIR" && ./bootstrap.sh )
}

main() {
  if ! parse_args "$@"; then
    return 1
  fi

  if [[ "$SHOW_HELP" -eq 1 ]]; then
    usage
    return 0
  fi

  local steps="git pull --ff-only"
  if [[ "$RUN_BOOTSTRAP" -eq 1 ]]; then
    steps="git pull --ff-only; ./bootstrap.sh"
  fi

  log "Dotfiles checkout: $DOTFILES_DIR"
  log "Expected branch:   $EXPECTED_BRANCH"
  log "Then run:          $steps"

  if ! check_preconditions; then
    warn "Nothing was changed."
    return 1
  fi

  if ! pull_latest; then
    warn "git pull failed; the checkout was not re-applied."
    return 1
  fi

  if [[ "$RUN_BOOTSTRAP" -eq 1 ]]; then
    if ! run_bootstrap; then
      warn "bootstrap.sh failed; review the output above."
      return 1
    fi
  else
    log "Skipping bootstrap.sh (--no-bootstrap)."
  fi

  log "Update complete."
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
