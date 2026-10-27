#!/usr/bin/env bash
# Assertions for the dotfiles-update / dotfiles-clean shell helpers in
# config/bash/.bash_aliases: repo resolution through the ~/.bashrc symlink, the
# non-symlinked guard, and argument forwarding to the repo scripts.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TEST_DIR/.." && pwd)"
ALIASES="$REPO_DIR/config/bash/.bash_aliases"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

# Symlinks are unavailable on some platforms (e.g. Git for Windows without
# developer mode, where `ln -s` degrades to a copy). The helpers resolve the
# repo through the ~/.bashrc symlink, so skip rather than fail there.
can_symlink() {
  local probe_dir
  probe_dir="$(mktemp -d)"
  : > "$probe_dir/src"
  if ln -sfn "$probe_dir/src" "$probe_dir/link" 2>/dev/null && [[ -L "$probe_dir/link" ]]; then
    rm -rf "$probe_dir"
    return 0
  fi
  rm -rf "$probe_dir"
  return 1
}

# Build a fixture checkout whose stub scripts record the arguments they receive,
# plus a HOME whose ~/.bashrc is symlinked into it (the anchor the helpers use).
make_fixture() {
  local root="$1"
  mkdir -p "$root/repo/config/bash" "$root/repo/scripts" "$root/home"
  : > "$root/repo/bootstrap.sh"
  : > "$root/repo/config/bash/.bashrc"
  cat > "$root/repo/scripts/update.sh" <<'STUB'
#!/usr/bin/env bash
printf 'update:%s\n' "$*" >> "$DOTFILES_HELPERS_LOG"
STUB
  cat > "$root/repo/scripts/cleanup.sh" <<'STUB'
#!/usr/bin/env bash
printf 'cleanup:%s\n' "$*" >> "$DOTFILES_HELPERS_LOG"
STUB
  chmod +x "$root/repo/scripts/update.sh" "$root/repo/scripts/cleanup.sh"
  ln -sfn "$root/repo/config/bash/.bashrc" "$root/home/.bashrc"
}

test_resolution_and_forwarding() (
  local temp_dir root log resolved
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT

  root="$temp_dir"
  log="$temp_dir/calls.log"
  : > "$log"
  make_fixture "$root"

  resolved="$(HOME="$root/home" bash -c 'source "$1"; _dotfiles_dir' _ "$ALIASES")" ||
    fail "the helpers could not resolve the repo root through a symlinked ~/.bashrc"
  [[ "$resolved" == "$root/repo" ]] ||
    fail "_dotfiles_dir returned '$resolved', expected '$root/repo'"

  HOME="$root/home" DOTFILES_HELPERS_LOG="$log" bash -c '
    source "$1"
    dotfiles-update --no-bootstrap extra
    dotfiles-clean --apply --min-age-days 7
  ' _ "$ALIASES"

  grep -qx 'update:--no-bootstrap extra' "$log" ||
    fail "dotfiles-update did not forward its arguments to scripts/update.sh"
  grep -qx 'cleanup:--apply --min-age-days 7' "$log" ||
    fail "dotfiles-clean did not forward its arguments to scripts/cleanup.sh"
)

test_guard_without_symlink() (
  local temp_dir root log status
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT

  root="$temp_dir"
  log="$temp_dir/calls.log"
  : > "$log"
  make_fixture "$root"
  rm -f "$root/home/.bashrc"
  : > "$root/home/.bashrc" # a real file, not a symlink

  status=0
  HOME="$root/home" DOTFILES_HELPERS_LOG="$log" bash -c '
    source "$1"
    dotfiles-update
    dotfiles-clean --apply
  ' _ "$ALIASES" 2>/dev/null || status=$?

  [[ "$status" -ne 0 ]] ||
    fail "dotfiles-update must fail when ~/.bashrc is not symlinked into the repo"
  [[ ! -s "$log" ]] ||
    fail "the helpers ran a repo script despite an unresolved repo root"
)

if can_symlink; then
  test_resolution_and_forwarding
  test_guard_without_symlink
else
  printf 'SKIP: symlinks unavailable; dotfiles helpers suite skipped\n'
fi
printf 'PASS: dotfiles-helpers.bash\n'
