#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TEST_DIR/.." && pwd)"

# shellcheck source=../bootstrap.sh
source "$REPO_DIR/bootstrap.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

# A PATH holding only an empty directory hides the host's real commands; shell
# functions still take precedence, so curl/bash are stubbed without a network
# call. Every case runs in its own subshell so its stubs cannot leak.

test_already_installed_skips() (
  local temp_dir marker output
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT

  marker="$temp_dir/curl-ran"
  mkdir -p "$temp_dir/bin"
  : > "$temp_dir/bin/opencode"
  chmod +x "$temp_dir/bin/opencode"

  # shellcheck disable=SC2317  # invoked by install_opencode's pipeline
  curl() { : > "$marker"; }

  output="$(PATH="$temp_dir/bin" install_opencode 2>&1)"
  [[ "$output" == *"already installed"* ]] ||
    fail "opencode on PATH should skip the install, got: $output"
  [[ ! -e "$marker" ]] ||
    fail "curl must not run when opencode is already installed"
)

test_missing_curl_warns() (
  local temp_dir empty output
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT
  empty="$temp_dir/empty"
  mkdir -p "$empty"

  output="$(PATH="$empty" install_opencode 2>&1)"
  [[ "$output" == *"curl not found"* ]] ||
    fail "a missing curl should warn and skip, got: $output"
)

test_installs_with_no_modify_path() (
  local temp_dir empty args_log output
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT
  empty="$temp_dir/empty"
  mkdir -p "$empty"
  args_log="$temp_dir/installer-args"

  # shellcheck disable=SC2317  # invoked by install_opencode's pipeline
  curl() { printf 'fake installer script\n'; }
  # shellcheck disable=SC2317  # consumes the piped script and records its args
  bash() {
    printf '%s\n' "$*" > "$args_log"
    cat > /dev/null
    return 0
  }

  output="$(PATH="$empty" install_opencode 2>&1)"
  [[ "$output" == *"Installed OpenCode CLI"* ]] ||
    fail "a successful install should be logged, got: $output"
  [[ "$(cat "$args_log")" == "-s -- --no-modify-path" ]] ||
    fail "the installer must run with --no-modify-path, got: $(cat "$args_log")"
)

test_install_failure_warns() (
  local temp_dir empty output
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT
  empty="$temp_dir/empty"
  mkdir -p "$empty"

  # shellcheck disable=SC2317  # invoked by install_opencode's pipeline
  curl() { printf 'fake installer script\n'; }
  # shellcheck disable=SC2317  # fails the pipeline to simulate installer failure
  bash() {
    cat > /dev/null
    return 1
  }

  output="$(PATH="$empty" install_opencode 2>&1)"
  [[ "$output" == *"Failed to install OpenCode CLI"* ]] ||
    fail "a failed install should warn, got: $output"
)

main() {
  test_already_installed_skips
  test_missing_curl_warns
  test_installs_with_no_modify_path
  test_install_failure_warns
  printf 'PASS: bootstrap-opencode-install.bash\n'
}

main "$@"
