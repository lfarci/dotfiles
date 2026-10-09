#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TEST_DIR/.." && pwd)"
CHECK="$REPO_DIR/tests/skills-inventory-consistency.mjs"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

# Builds a throwaway repo skeleton with the given lock entries and skill dirs.
# Usage: make_fixture <dir> <lock-skills-json> <skill-dir>...
make_fixture() {
  local dir="$1" skills_json="$2"
  shift 2
  mkdir -p "$dir/config/agents/skills"
  printf '{"version":3,"skills":%s}\n' "$skills_json" > "$dir/config/agents/.skill-lock.json"
  local name
  for name in "$@"; do
    mkdir -p "$dir/config/agents/skills/$name"
  done
}

run_check() {
  node "$CHECK" "$1"
}

test_tracked_inventory_is_consistent() {
  run_check "$REPO_DIR" || fail "committed skills inventory is inconsistent"
}

test_missing_lock_entry_is_detected() (
  local temp_dir output status
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT

  # Two lock entries, two skill directories, but the names differ.
  make_fixture "$temp_dir" '{"brainstorming":{},"docx":{}}' docx xlsx

  set +e
  output="$(node "$CHECK" "$temp_dir" 2>&1)"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "drift with equal counts must fail"
  [[ "$output" == *"locked but no matching skill directory: brainstorming"* ]] ||
    fail "locked-but-missing skill was not reported"
  [[ "$output" == *"skill directory without a lock entry: xlsx"* ]] ||
    fail "present-but-unlocked skill was not reported"
  [[ "$output" == *"Equal counts do not imply matching inventories."* ]] ||
    fail "equal-count caveat was not reported"
)

test_missing_skill_directory_is_detected() (
  local temp_dir output status
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT

  make_fixture "$temp_dir" '{"docx":{},"pdf":{}}' docx

  set +e
  output="$(node "$CHECK" "$temp_dir" 2>&1)"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "a lock entry without a skill directory must fail"
  [[ "$output" == *"locked but no matching skill directory: pdf"* ]] ||
    fail "orphaned lock entry was not reported"
)

test_non_directory_entries_are_ignored() (
  local temp_dir
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT

  make_fixture "$temp_dir" '{"docx":{},"pdf":{}}' docx pdf
  : > "$temp_dir/config/agents/skills/README.md"

  run_check "$temp_dir" || fail "non-directory files must not count as skills"
)

test_empty_lock_is_consistent() (
  local temp_dir
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT

  make_fixture "$temp_dir" '{}'

  run_check "$temp_dir" || fail "an empty lock and empty skills dir must be consistent"
)

test_invalid_lock_fails() (
  local temp_dir status
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT

  mkdir -p "$temp_dir/config/agents/skills"
  printf 'not json\n' > "$temp_dir/config/agents/.skill-lock.json"

  set +e
  node "$CHECK" "$temp_dir" >/dev/null 2>&1
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "an unreadable lock must fail"
)

test_tracked_inventory_is_consistent
test_missing_lock_entry_is_detected
test_missing_skill_directory_is_detected
test_non_directory_entries_are_ignored
test_empty_lock_is_consistent
test_invalid_lock_fails
printf 'PASS: skills-inventory-consistency.bash\n'
