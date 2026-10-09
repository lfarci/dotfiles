#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TEST_DIR/.." && pwd)"
REAL_MV="$(command -v mv)"

# shellcheck source=../bootstrap.sh
source "$REPO_DIR/bootstrap.sh"

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

# A stub `mv` that fails for the given path pattern and defers to the real `mv`
# everywhere else. Mirrors the fixture-stub pattern used elsewhere in tests/.
install_mv_stub() {
  local stub_dir="$1" pattern="$2"

  mkdir -p "$stub_dir"
  cat > "$stub_dir/mv" <<EOF
#!/usr/bin/env bash
for arg in "\$@"; do
  case "\$arg" in
    $pattern) exit 1 ;;
  esac
done
exec "$REAL_MV" "\$@"
EOF
  chmod +x "$stub_dir/mv"
}

# A stub `date` that always reports the same timestamp, so two runs in the same
# second can be simulated deterministically.
install_frozen_date_stub() {
  local stub_dir="$1"

  mkdir -p "$stub_dir"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "20240101000000"\n' > "$stub_dir/date"
  chmod +x "$stub_dir/date"
}

make_sources() {
  local repo="$1" vscode_content="$2" claude_content="$3"

  mkdir -p "$repo/config/vscode" "$repo/config/claude"
  printf '%s\n' "$vscode_content" > "$repo/config/vscode/settings.json"
  printf '%s\n' "$claude_content" > "$repo/config/claude/settings.json"
}

test_same_basename_collision() (
  local temp_dir repo home
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT

  repo="$temp_dir/repo"
  home="$temp_dir/home"
  make_sources "$repo" "vscode-new" "claude-new"
  mkdir -p "$home/.config/Code/User" "$home/.claude"
  printf 'vscode-original\n' > "$home/.config/Code/User/settings.json"
  printf 'claude-original\n' > "$home/.claude/settings.json"

  DOTFILES_DIR="$repo" HOME="$home" backup_and_link config/vscode/settings.json .config/Code/User/settings.json
  DOTFILES_DIR="$repo" HOME="$home" backup_and_link config/claude/settings.json .claude/settings.json

  [[ -f "$BACKUP_DIR/.config/Code/User/settings.json" ]] ||
    fail "VS Code settings backup was not mirrored into $BACKUP_DIR"
  [[ -f "$BACKUP_DIR/.claude/settings.json" ]] ||
    fail "Claude settings backup was not mirrored into $BACKUP_DIR"

  [[ "$(cat "$BACKUP_DIR/.config/Code/User/settings.json")" == "vscode-original" ]] ||
    fail "VS Code settings backup does not hold its original contents"
  [[ "$(cat "$BACKUP_DIR/.claude/settings.json")" == "claude-original" ]] ||
    fail "Claude settings backup was overwritten by the colliding settings.json backup"

  [[ "$(cat "$home/.config/Code/User/settings.json")" == "vscode-new" ]] ||
    fail "VS Code settings destination was not re-linked"
  [[ "$(cat "$home/.claude/settings.json")" == "claude-new" ]] ||
    fail "Claude settings destination was not re-linked"
)

test_backup_failure_keeps_destination() (
  local temp_dir repo home output status
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT

  repo="$temp_dir/repo"
  home="$temp_dir/home"
  make_sources "$repo" "vscode-new" "claude-new"
  mkdir -p "$home/.config/Code/User"
  printf 'vscode-original\n' > "$home/.config/Code/User/settings.json"

  install_mv_stub "$temp_dir/bin" "*"

  status=0
  output="$(PATH="$temp_dir/bin:$PATH" DOTFILES_DIR="$repo" HOME="$home" \
    backup_and_link config/vscode/settings.json .config/Code/User/settings.json 2>&1)" || status=$?

  [[ "$status" -ne 0 ]] ||
    fail "a failed backup must report failure instead of logging success"
  [[ "$output" == *"Failed to back up"* ]] ||
    fail "a failed backup must warn about it; got: $output"

  [[ -f "$home/.config/Code/User/settings.json" ]] ||
    fail "destination was deleted when the backup move failed"
  [[ "$(cat "$home/.config/Code/User/settings.json")" == "vscode-original" ]] ||
    fail "destination contents changed when the backup move failed"

  if can_symlink; then
    [[ ! -L "$home/.config/Code/User/settings.json" ]] ||
      fail "destination was re-linked even though its backup failed"
  fi
)

test_backups_do_not_collide_across_runs() (
  local temp_dir repo home first_dir second_dir
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT

  repo="$temp_dir/repo"
  home="$temp_dir/home"
  make_sources "$repo" "vscode-new" "claude-new"
  mkdir -p "$home/.config/Code/User"

  # Freeze the clock so both runs would resolve the same timestamp directory.
  install_frozen_date_stub "$temp_dir/bin"

  printf 'run-one\n' > "$home/.config/Code/User/settings.json"
  PATH="$temp_dir/bin:$PATH" DOTFILES_DIR="$repo" HOME="$home" \
    backup_and_link config/vscode/settings.json .config/Code/User/settings.json
  first_dir="$BACKUP_DIR"

  BACKUP_DIR=""
  printf 'run-two\n' > "$home/.config/Code/User/settings.json"
  PATH="$temp_dir/bin:$PATH" DOTFILES_DIR="$repo" HOME="$home" \
    backup_and_link config/vscode/settings.json .config/Code/User/settings.json
  second_dir="$BACKUP_DIR"

  [[ -n "$first_dir" && -n "$second_dir" ]] || fail "a backup directory was not created"
  [[ "$first_dir" != "$second_dir" ]] ||
    fail "both runs reused the same backup directory ($first_dir)"
  [[ -d "$first_dir" && -d "$second_dir" ]] ||
    fail "a per-run backup directory is missing"

  [[ "$(cat "$first_dir/.config/Code/User/settings.json")" == "run-one" ]] ||
    fail "the first run's backup was lost"
  [[ "$(cat "$second_dir/.config/Code/User/settings.json")" == "run-two" ]] ||
    fail "the second run's backup overwrote or missed the first"
)

test_existing_correct_symlink_untouched() (
  local temp_dir repo home before after
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT

  if ! can_symlink; then
    printf 'SKIP: existing-symlink assertions need symlink support\n'
    return 0
  fi

  repo="$temp_dir/repo"
  home="$temp_dir/home"
  make_sources "$repo" "vscode-new" "claude-new"
  mkdir -p "$home/.config/Code/User"
  ln -sfn "$repo/config/vscode/settings.json" "$home/.config/Code/User/settings.json"

  before="$(readlink -f "$home/.config/Code/User/settings.json")"

  DOTFILES_DIR="$repo" HOME="$home" \
    backup_and_link config/vscode/settings.json .config/Code/User/settings.json

  after="$(readlink -f "$home/.config/Code/User/settings.json")"

  [[ "$before" == "$after" ]] || fail "an already-correct symlink was replaced"
  [[ -z "$BACKUP_DIR" ]] || fail "a correct symlink should not trigger a backup"
)

test_link_mappings_reports_failure_and_continues() (
  local temp_dir repo home status output out_file
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT

  repo="$temp_dir/repo"
  home="$temp_dir/home"
  make_sources "$repo" "vscode-new" "claude-new"
  mkdir -p "$home/.config/Code/User" "$home/.claude"
  printf 'vscode-original\n' > "$home/.config/Code/User/settings.json"
  printf 'claude-original\n' > "$home/.claude/settings.json"

  install_mv_stub "$temp_dir/bin" "*/.config/Code/User/settings.json"

  # Run in this subshell (not a command substitution) so BACKUP_DIR is visible.
  out_file="$temp_dir/output"
  status=0
  PATH="$temp_dir/bin:$PATH" DOTFILES_DIR="$repo" HOME="$home" \
    link_mappings \
    "config/vscode/settings.json:.config/Code/User/settings.json" \
    "config/claude/settings.json:.claude/settings.json" > "$out_file" 2>&1 || status=$?
  output="$(cat "$out_file")"

  [[ "$status" -ne 0 ]] || fail "link_mappings must report failure when a backup fails"
  [[ "$output" == *"could not be linked"* ]] ||
    fail "link_mappings must summarise the failure; got: $output"

  [[ "$(cat "$home/.config/Code/User/settings.json")" == "vscode-original" ]] ||
    fail "the un-backupable destination was not left intact"

  [[ -f "$BACKUP_DIR/.claude/settings.json" ]] ||
    fail "linking stopped after the failure instead of continuing to later mappings"
  [[ "$(cat "$BACKUP_DIR/.claude/settings.json")" == "claude-original" ]] ||
    fail "the later mapping's backup does not hold its original contents"
)

test_same_basename_collision
test_backup_failure_keeps_destination
test_backups_do_not_collide_across_runs
test_existing_correct_symlink_untouched
test_link_mappings_reports_failure_and_continues
printf 'PASS: bootstrap-backup.bash\n'
