# ~/.bash_aliases

if command -v eza >/dev/null 2>&1; then
  alias ls='eza --icons'
  alias ll='eza --icons -alF'
else
  alias ll='ls -alF'
fi
alias gs='git status -sb'
alias cdc='cd /mnt/c'
alias cdr='change_directory_to_first_match "/mnt/c/Development/Repos" "/mnt/c/Users/*/Development/Repos"'

change_directory_to_first_match() {
  local pattern
  local target
  local nullglob_was_set=0

  if shopt -q nullglob; then
    nullglob_was_set=1
  else
    shopt -s nullglob
  fi

  for pattern in "$@"; do
    for target in $pattern; do
      if [ -d "$target" ]; then
        cd "$target" || { [ "$nullglob_was_set" -eq 1 ] || shopt -u nullglob; return; }
        [ "$nullglob_was_set" -eq 1 ] || shopt -u nullglob
        return
      fi
    done
  done

  [ "$nullglob_was_set" -eq 1 ] || shopt -u nullglob
  echo "change_directory_to_first_match: no matching directory found" >&2
  return 1
}

# Resolve the dotfiles repo root via the ~/.bashrc symlink bootstrap creates
# (`~/.bashrc` -> `<repo>/config/bash/.bashrc`). Guards against a non-symlinked
# ~/.bashrc, where dirname walks up to `/` and `git -C / pull` would run in the
# wrong place: the derived directory must actually contain bootstrap.sh.
_dotfiles_dir() {
  local target=""
  local dir=""

  target="$(readlink -f "$HOME/.bashrc" 2>/dev/null)" || target=""

  if [ -n "$target" ]; then
    dir="$(dirname "$(dirname "$(dirname "$target")")")"
  fi

  if [ -n "$dir" ] && [ -f "$dir/bootstrap.sh" ]; then
    printf '%s\n' "$dir"
    return 0
  fi

  echo "dotfiles: cannot locate the dotfiles repo (~/.bashrc not symlinked?)" >&2
  return 1
}

# Update the dotfiles checkout and re-apply it, using the repo's update script
# so the preconditions (attached branch, clean tree) and the pull/relink logic
# live in one place. Arguments are forwarded, e.g. --no-bootstrap or
# --branch <name>.
dotfiles-update() {
  local dir
  dir="$(_dotfiles_dir)" || return 1

  "$dir/scripts/update.sh" "$@"
}

# Reclaim disk space from stale bootstrap backups via the repo's cleanup script
# (a dry run unless --apply is given). Arguments are forwarded, e.g. --apply or
# --min-age-days <days>.
dotfiles-clean() {
  local dir
  dir="$(_dotfiles_dir)" || return 1

  "$dir/scripts/cleanup.sh" "$@"
}
