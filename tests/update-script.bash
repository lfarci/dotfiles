#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TEST_DIR/.." && pwd)"
UPDATE_SCRIPT="$REPO_DIR/scripts/update.sh"

# shellcheck source=../scripts/update.sh
source "$REPO_DIR/scripts/update.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

# Replace `git` with a stub driven by environment variables so the preconditions
# can be exercised without a repository or any network access. The stub is a
# shell function, which takes precedence over the real `git` on PATH.
install_git_stub() {
  # shellcheck disable=SC2317  # invoked indirectly by update.sh's functions
  git() {
    if [[ -n "${GIT_LOG:-}" ]]; then
      printf '%s\n' "$*" >> "$GIT_LOG"
    fi

    case "$*" in
      *"rev-parse --is-inside-work-tree"*)
        return "${GIT_IN_REPO:-0}"
        ;;
      *"symbolic-ref --quiet --short HEAD"*)
        if [[ "${GIT_DETACHED:-0}" -eq 1 ]]; then
          return 1
        fi
        printf '%s\n' "${GIT_BRANCH:-main}"
        return 0
        ;;
      *"status --porcelain"*)
        printf '%s' "${GIT_STATUS:-}"
        return 0
        ;;
      *"pull --ff-only"*)
        return "${GIT_PULL_RC:-0}"
        ;;
      *)
        return 0
        ;;
    esac
  }
}

test_help_exits_zero() {
  local output status=0
  output="$(bash "$UPDATE_SCRIPT" --help 2>&1)" || status=$?
  [[ "$status" -eq 0 ]] || fail "--help must exit 0 (rc=$status)"
  [[ "$output" == *"usage: scripts/update.sh"* ]] ||
    fail "--help output does not show the usage line: $output"
}

test_parse_args() {
  parse_args --branch develop --no-bootstrap
  [[ "$EXPECTED_BRANCH" == "develop" ]] ||
    fail "--branch did not set the expected branch (got '$EXPECTED_BRANCH')"
  [[ "$RUN_BOOTSTRAP" -eq 0 ]] ||
    fail "--no-bootstrap did not disable the bootstrap step"

  parse_args
  [[ "$EXPECTED_BRANCH" == "main" ]] ||
    fail "the default branch should be main (got '$EXPECTED_BRANCH')"
  [[ "$RUN_BOOTSTRAP" -eq 1 ]] ||
    fail "the bootstrap step should run by default"

  local status=0
  parse_args --branch >/dev/null 2>&1 || status=$?
  [[ "$status" -ne 0 ]] || fail "--branch without a value must fail"

  status=0
  parse_args --bogus >/dev/null 2>&1 || status=$?
  [[ "$status" -ne 0 ]] || fail "an unknown flag must fail"
}

test_precondition_not_a_repo() (
  local temp_dir output status=0
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT

  install_git_stub
  DOTFILES_DIR="$temp_dir/repo"
  EXPECTED_BRANCH="main"
  GIT_IN_REPO=1

  output="$(check_preconditions 2>&1)" || status=$?
  [[ "$status" -ne 0 ]] || fail "a non-repository checkout must fail the preconditions"
  [[ "$output" == *"Not inside a Git work tree"* ]] ||
    fail "non-repository message missing: $output"
)

test_precondition_detached_head() (
  local temp_dir output status=0
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT

  install_git_stub
  DOTFILES_DIR="$temp_dir/repo"
  EXPECTED_BRANCH="main"
  GIT_DETACHED=1

  output="$(check_preconditions 2>&1)" || status=$?
  [[ "$status" -ne 0 ]] || fail "a detached HEAD must fail the preconditions"
  [[ "$output" == *"detached"* ]] || fail "detached-HEAD message missing: $output"
)

test_precondition_wrong_branch() (
  local temp_dir output status=0
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT

  install_git_stub
  DOTFILES_DIR="$temp_dir/repo"
  EXPECTED_BRANCH="main"
  GIT_BRANCH="develop"

  output="$(check_preconditions 2>&1)" || status=$?
  [[ "$status" -ne 0 ]] || fail "a branch mismatch must fail the preconditions"
  [[ "$output" == *"expected 'main'"* ]] ||
    fail "branch-mismatch message missing: $output"
)

test_precondition_dirty_tree() (
  local temp_dir output status=0
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT

  install_git_stub
  DOTFILES_DIR="$temp_dir/repo"
  EXPECTED_BRANCH="main"
  GIT_STATUS=" M config/bash/.bashrc"

  output="$(check_preconditions 2>&1)" || status=$?
  [[ "$status" -ne 0 ]] || fail "a dirty working tree must fail the preconditions"
  [[ "$output" == *"not clean"* ]] || fail "dirty-tree message missing: $output"
)

test_precondition_clean_main_passes() (
  local temp_dir
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT

  install_git_stub
  DOTFILES_DIR="$temp_dir/repo"
  EXPECTED_BRANCH="main"

  check_preconditions || fail "a clean main checkout must pass the preconditions"
)

# A fixture repository with a recording bootstrap.sh so the full happy path can
# run without touching the real checkout.
make_fake_repo() {
  local dir="$1" marker="$2"
  mkdir -p "$dir"
  cat > "$dir/bootstrap.sh" <<EOF
#!/usr/bin/env bash
printf 'bootstrapped\n' > "$marker"
EOF
  chmod +x "$dir/bootstrap.sh"
}

test_main_pulls_and_bootstraps() (
  local temp_dir output status=0
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT

  DOTFILES_DIR="$temp_dir/repo"
  make_fake_repo "$DOTFILES_DIR" "$temp_dir/bootstrap-ran"
  GIT_LOG="$temp_dir/git.log"
  install_git_stub
  GIT_BRANCH="main"

  output="$(main 2>&1)" || status=$?
  [[ "$status" -eq 0 ]] || fail "main must succeed on a clean checkout (rc=$status): $output"
  grep -Fq -- "pull --ff-only" "$GIT_LOG" ||
    fail "main did not run 'git pull --ff-only': $(cat "$GIT_LOG")"
  [[ -f "$temp_dir/bootstrap-ran" ]] || fail "main did not run bootstrap.sh"
  [[ "$output" == *"Update complete"* ]] ||
    fail "main did not report completion: $output"
)

test_main_no_bootstrap_skips() (
  local temp_dir output status=0
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT

  DOTFILES_DIR="$temp_dir/repo"
  make_fake_repo "$DOTFILES_DIR" "$temp_dir/bootstrap-ran"
  GIT_LOG="$temp_dir/git.log"
  install_git_stub
  GIT_BRANCH="main"

  output="$(main --no-bootstrap 2>&1)" || status=$?
  [[ "$status" -eq 0 ]] || fail "main --no-bootstrap must succeed (rc=$status): $output"
  grep -Fq -- "pull --ff-only" "$GIT_LOG" ||
    fail "main --no-bootstrap did not run 'git pull --ff-only'"
  [[ ! -e "$temp_dir/bootstrap-ran" ]] ||
    fail "main --no-bootstrap must not run bootstrap.sh"
  [[ "$output" == *"Skipping bootstrap.sh"* ]] ||
    fail "main --no-bootstrap did not explain that bootstrap was skipped: $output"
)

# A failed pull must abort before bootstrap.sh is invoked, so a half-updated
# checkout is never re-applied.
test_main_aborts_on_pull_failure() (
  local temp_dir output status=0
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT

  DOTFILES_DIR="$temp_dir/repo"
  make_fake_repo "$DOTFILES_DIR" "$temp_dir/bootstrap-ran"
  install_git_stub
  GIT_BRANCH="main"
  GIT_PULL_RC=1

  output="$(main 2>&1)" || status=$?
  [[ "$status" -ne 0 ]] || fail "a failed pull must fail the update: $output"
  [[ ! -e "$temp_dir/bootstrap-ran" ]] ||
    fail "bootstrap.sh must not run after a failed pull"
)

run_tests() {
  test_help_exits_zero
  test_parse_args
  test_precondition_not_a_repo
  test_precondition_detached_head
  test_precondition_wrong_branch
  test_precondition_dirty_tree
  test_precondition_clean_main_passes
  test_main_pulls_and_bootstraps
  test_main_no_bootstrap_skips
  test_main_aborts_on_pull_failure
  printf 'PASS: update-script.bash\n'
}

run_tests "$@"
