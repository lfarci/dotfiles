#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TEST_DIR/.." && pwd)"
CLEANUP_SCRIPT="$REPO_DIR/scripts/cleanup.sh"

# shellcheck source=../scripts/cleanup.sh
source "$REPO_DIR/scripts/cleanup.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

# Symlinks are unavailable on some platforms (e.g. Git for Windows without
# developer mode, where `ln -s` degrades to a copy). Assertions that depend on
# real symlink semantics are skipped rather than reported as failures.
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

# An old timestamp that is unambiguously older than any sane age threshold.
set_old_mtime() {
  touch -t 202001010000.00 "$@"
}

test_help_exits_zero() {
  local output status=0
  output="$(bash "$CLEANUP_SCRIPT" --help 2>&1)" || status=$?
  [[ "$status" -eq 0 ]] || fail "--help must exit 0 (rc=$status)"
  [[ "$output" == *"usage: scripts/cleanup.sh"* ]] ||
    fail "--help output does not show the usage line: $output"
}

test_parse_args() {
  local status=0
  parse_args --min-age-days abc >/dev/null 2>&1 || status=$?
  [[ "$status" -ne 0 ]] || fail "a non-numeric --min-age-days must fail"

  status=0
  parse_args --min-age-days >/dev/null 2>&1 || status=$?
  [[ "$status" -ne 0 ]] || fail "--min-age-days without a value must fail"

  parse_args --min-age-days 7 --apply
  [[ "$MIN_AGE_DAYS" -eq 7 ]] || fail "--min-age-days did not set the threshold"
  [[ "$APPLY" -eq 1 ]] || fail "--apply did not enable deletion"
}

test_is_managed_backup() {
  is_managed_backup ".dotfiles_backup_20240101000000" ||
    fail "a 14-digit backup name should be managed"
  is_managed_backup ".dotfiles_backup_20240101000000.1" ||
    fail "a suffixed backup name should be managed"

  if is_managed_backup ".dotfiles_backup_notes"; then
    fail "an unrecognized name must not be managed"
  fi
  if is_managed_backup ".dotfiles_backup_2024010100000"; then
    fail "a 13-digit name must not be managed"
  fi
  if is_managed_backup "dotfiles_backup_20240101000000"; then
    fail "a name without the leading dot must not be managed"
  fi
  if is_managed_backup ".dotfiles_backup_20240101000000.abc"; then
    fail "a non-numeric suffix must not be managed"
  fi
}

test_require_safe_home() (
  local status=0

  HOME=""
  require_safe_home >/dev/null 2>&1 || status=$?
  [[ "$status" -ne 0 ]] || fail "an empty HOME must be refused"

  status=0
  HOME="/"
  require_safe_home >/dev/null 2>&1 || status=$?
  [[ "$status" -ne 0 ]] || fail "HOME=/ must be refused"

  status=0
  HOME="relative/path"
  require_safe_home >/dev/null 2>&1 || status=$?
  [[ "$status" -ne 0 ]] || fail "a relative HOME must be refused"
)

test_delete_backup_guards() (
  local temp_dir status=0
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT

  HOME="$temp_dir/home"
  mkdir -p "$HOME/.dotfiles_backup_20200101000000" "$temp_dir/outside"
  set_old_mtime "$HOME/.dotfiles_backup_20200101000000"

  delete_backup "$temp_dir/outside" >/dev/null 2>&1 || status=$?
  [[ "$status" -ne 0 ]] || fail "delete_backup must refuse a path outside HOME"
  [[ -d "$temp_dir/outside" ]] || fail "delete_backup removed a path outside HOME"

  status=0
  delete_backup "$HOME/.dotfiles_backup_notes" >/dev/null 2>&1 || status=$?
  [[ "$status" -ne 0 ]] || fail "delete_backup must refuse an unrecognized name"

  delete_backup "$HOME/.dotfiles_backup_20200101000000" >/dev/null 2>&1 ||
    fail "delete_backup must remove a managed backup"
  [[ ! -e "$HOME/.dotfiles_backup_20200101000000" ]] ||
    fail "delete_backup did not remove the managed backup"
)

test_dry_run_removes_nothing() (
  local temp_dir output status=0
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT

  HOME="$temp_dir/home"
  mkdir -p "$HOME"
  local old="$HOME/.dotfiles_backup_20200101000000"
  local recent="$HOME/.dotfiles_backup_20260101000000"
  mkdir -p "$old" "$recent"
  set_old_mtime "$old"

  output="$(main 2>&1)" || status=$?
  [[ "$status" -eq 0 ]] || fail "a dry run must succeed (rc=$status): $output"
  [[ -d "$old" ]] || fail "a dry run removed a directory"
  [[ "$output" == *"Dry run"* ]] ||
    fail "a dry run did not report that nothing was removed: $output"
  [[ "$output" == *"$old"* ]] ||
    fail "a dry run did not list the stale backup: $output"
  [[ "$output" != *"$recent"* ]] ||
    fail "a dry run listed a too-recent backup: $output"
)

test_apply_removes_only_old_managed() (
  local temp_dir output rc2=0
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT

  HOME="$temp_dir/home"
  mkdir -p "$HOME/.config/opencode"
  printf '{}\n' > "$HOME/.config/opencode/opencode.json"

  local old="$HOME/.dotfiles_backup_20200101000000"
  local old_suffixed="$HOME/.dotfiles_backup_20200102000000.1"
  local recent="$HOME/.dotfiles_backup_20260101000000"
  local unmanaged="$HOME/.dotfiles_backup_notes"
  mkdir -p "$old" "$old_suffixed" "$recent" "$unmanaged"
  set_old_mtime "$old" "$old_suffixed" "$unmanaged"

  local symlinked="$HOME/.dotfiles_backup_20200103000000"
  local have_symlinks=0
  if can_symlink; then
    have_symlinks=1
    ln -s "$old" "$symlinked"
  fi

  local status=0
  output="$(main --apply 2>&1)" || status=$?
  [[ "$status" -eq 0 ]] || fail "apply must succeed (rc=$status): $output"

  [[ ! -e "$old" ]] || fail "an old managed backup was not removed"
  [[ ! -e "$old_suffixed" ]] || fail "an old suffixed backup was not removed"
  [[ -d "$recent" ]] || fail "a too-recent backup must be kept"
  [[ -d "$unmanaged" ]] || fail "an unrecognized .dotfiles_backup_* name must be kept"
  if [[ "$have_symlinks" -eq 1 ]]; then
    [[ -L "$symlinked" ]] || fail "a symlinked backup must be kept"
  fi
  [[ -f "$HOME/.config/opencode/opencode.json" ]] ||
    fail "cleanup must not touch ~/.config/opencode"

  local output2
  output2="$(main --apply 2>&1)" || rc2=$?
  [[ "$rc2" -eq 0 ]] || fail "a second apply run must succeed (rc=$rc2): $output2"
  [[ "$output2" == *"No stale bootstrap backups"* ]] ||
    fail "a second apply run should find nothing to remove: $output2"
)

# --min-age-days must be honoured: a 2020 backup is older than 1 day but not
# older than 3650 days.
test_min_age_threshold() (
  local temp_dir status=0
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT

  HOME="$temp_dir/home"
  mkdir -p "$HOME"
  local old="$HOME/.dotfiles_backup_20200101000000"
  mkdir -p "$old"
  set_old_mtime "$old"

  main --apply --min-age-days 3650 >/dev/null 2>&1 || status=$?
  [[ "$status" -eq 0 ]] || fail "a high threshold run must succeed (rc=$status)"
  [[ -d "$old" ]] || fail "a backup younger than the threshold must be kept"

  main --apply --min-age-days 1 >/dev/null 2>&1 || status=$?
  [[ "$status" -eq 0 ]] || fail "a low threshold run must succeed (rc=$status)"
  [[ ! -e "$old" ]] || fail "a backup older than the threshold must be removed"
)

run_tests() {
  test_help_exits_zero
  test_parse_args
  test_is_managed_backup
  test_require_safe_home
  test_delete_backup_guards
  test_dry_run_removes_nothing
  test_apply_removes_only_old_managed
  test_min_age_threshold
  printf 'PASS: cleanup-script.bash\n'
}

run_tests "$@"
