# ~/.bash_aliases

alias ll='ls -alF'
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
