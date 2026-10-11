#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TEST_DIR/.." && pwd)"

# shellcheck source=../bootstrap.sh
source "$REPO_DIR/bootstrap.sh"

OS_SCRIPTS=(
  "$REPO_DIR/os/ubuntu/install.sh"
  "$REPO_DIR/os/fedora/install.sh"
)

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

# Source only the function definitions: each OS script ends with unconditional
# installer invocations (install_packages, install_docker, ...) that must not
# run inside the test harness.
load_os_functions() {
  local script="$1" cut
  cut="$(grep -n '^install_packages$' "$script" | cut -d: -f1 | head -n 1 || true)"
  [[ -n "$cut" ]] ||
    fail "expected $script to end with installer invocations starting at 'install_packages'"
  # shellcheck disable=SC1090
  eval "$(sed -n "1,$((cut - 1))p" "$script")"
}

run_for_each_os_script() {
  local test_fn="$1" script
  for script in "${OS_SCRIPTS[@]}"; do
    "$test_fn" "$script"
  done
}

# Replace every external command install_docker reaches with a shell function.
# Functions take precedence over PATH lookups, so a PATH holding only an empty
# directory additionally hides the host's real docker or package manager.
# $1 is a directory receiving sudo.log (sudo invocations) and systemctl.log
# (systemctl invocations).
stub_commands() {
  DOTFILES_TEST_SUDO_LOG="$1/sudo.log"
  DOTFILES_TEST_SYSTEMCTL_LOG="$1/systemctl.log"

  curl() { return 0; }
  gpg() { return 0; }
  tee() { return 0; }
  dpkg() { echo amd64; }
  apt-get() { return 0; }
  dnf() { return 0; }
  usermod() { return 0; }
  env() {
    while [[ "${1:-}" == *=* ]]; do
      shift
    done
    "$@"
  }
  sudo() {
    printf 'sudo %s\n' "$*" >> "$DOTFILES_TEST_SUDO_LOG"
    "$@"
  }
  systemctl() {
    printf 'systemctl %s\n' "$*" >> "$DOTFILES_TEST_SYSTEMCTL_LOG"
    return "${DOTFILES_TEST_SYSTEMCTL_EXIT:-0}"
  }
}

test_systemd_detection_matches_environment() (
  local script="$1"
  load_os_functions "$script"

  if [[ -d /run/systemd/system ]]; then
      systemd_is_running ||
        fail "$script: systemd_is_running returned false while /run/systemd/system exists"
    elif systemd_is_running; then
      fail "$script: systemd_is_running returned true while /run/systemd/system is missing"
    fi
  )

test_activation_when_systemd_running() (
  local script="$1" temp_dir output rc=0
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT

  load_os_functions "$script"
  systemd_is_running() { return 0; }
  stub_commands "$temp_dir"

  output="$(activate_docker_service 2>&1)" || rc=$?

  [[ "$rc" -eq 0 ]] || fail "$script: activation on a systemd host must succeed (rc=$rc)"
  grep -Fqx -- 'systemctl enable --now docker' "$temp_dir/systemctl.log" ||
    fail "$script: systemctl enable --now docker was not invoked"
  if [[ "$output" == *"Failed to enable"* ]]; then
    fail "$script: unexpected activation warning: $output"
  fi
)

test_activation_preserves_sudo_prefix() (
  local script="$1" temp_dir rc=0
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT

  load_os_functions "$script"
  systemd_is_running() { return 0; }
  stub_commands "$temp_dir"

  activate_docker_service sudo >/dev/null 2>&1 || rc=$?

  [[ "$rc" -eq 0 ]] || fail "$script: activation with a sudo prefix must succeed (rc=$rc)"
  grep -Fqx -- 'sudo systemctl enable --now docker' "$temp_dir/sudo.log" ||
    fail "$script: the sudo prefix was not applied to systemctl"
  grep -Fqx -- 'systemctl enable --now docker' "$temp_dir/systemctl.log" ||
    fail "$script: systemctl enable --now docker was not invoked"
)

test_defers_when_systemd_unavailable() (
  local script="$1" temp_dir output rc=0
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT

  load_os_functions "$script"
  systemd_is_running() { return 1; }
  stub_commands "$temp_dir"

  output="$(activate_docker_service 2>&1)" || rc=$?

  [[ "$rc" -eq 0 ]] || fail "$script: deferred activation must not fail setup (rc=$rc)"
  if [[ -e "$temp_dir/systemctl.log" ]]; then
    fail "$script: systemctl must not run when systemd is unavailable"
  fi
  [[ "$output" == *"deferred"* ]] ||
    fail "$script: missing deferred-activation message: $output"
  [[ "$output" == *"systemctl enable --now docker"* ]] ||
    fail "$script: deferred message omitted the manual activation step: $output"
  [[ "$output" == *"systemd is not running"* ]] ||
    fail "$script: deferred message did not explain why activation was skipped: $output"
)

test_activation_failure_is_reported_not_fatal() (
  local script="$1" temp_dir output rc=0
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT

  load_os_functions "$script"
  systemd_is_running() { return 0; }
  stub_commands "$temp_dir"
  export DOTFILES_TEST_SYSTEMCTL_EXIT=1

  output="$(activate_docker_service 2>&1)" || rc=$?

  [[ "$rc" -eq 0 ]] || fail "$script: an activation failure must not abort setup (rc=$rc)"
  grep -Fqx -- 'systemctl enable --now docker' "$temp_dir/systemctl.log" ||
    fail "$script: systemctl enable --now docker was not invoked"
  [[ "$output" == *"Failed to enable"* ]] ||
    fail "$script: activation failure was not reported: $output"
)

test_install_docker_defers_without_systemd() (
  local script="$1" temp_dir output rc=0
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT
  mkdir -p "$temp_dir/bin"

  load_os_functions "$script"
  systemd_is_running() { return 1; }
  stub_commands "$temp_dir"

  output="$(PATH="$temp_dir/bin" USER=dotfiles-test install_docker 2>&1)" || rc=$?

  [[ "$rc" -eq 0 ]] || fail "$script: install_docker must complete without systemd (rc=$rc)"
  [[ "$output" == *"Installed Docker"* ]] ||
    fail "$script: install_docker did not report a successful install: $output"
  [[ "$output" == *"deferred"* ]] ||
    fail "$script: install_docker omitted the deferred-activation message: $output"
  if [[ -e "$temp_dir/systemctl.log" ]]; then
    fail "$script: install_docker invoked systemctl without a running systemd"
  fi
)

test_install_docker_activates_with_systemd() (
  local script="$1" temp_dir output rc=0
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT
  mkdir -p "$temp_dir/bin"

  load_os_functions "$script"
  systemd_is_running() { return 0; }
  stub_commands "$temp_dir"

  output="$(PATH="$temp_dir/bin" USER=dotfiles-test install_docker 2>&1)" || rc=$?

  [[ "$rc" -eq 0 ]] || fail "$script: install_docker must succeed on systemd (rc=$rc)"
  [[ "$output" == *"Installed Docker"* ]] ||
    fail "$script: install_docker did not report a successful install: $output"
  grep -Fqx -- 'systemctl enable --now docker' "$temp_dir/systemctl.log" ||
    fail "$script: install_docker did not activate the Docker service"
)

run_for_each_os_script test_systemd_detection_matches_environment
run_for_each_os_script test_activation_when_systemd_running
run_for_each_os_script test_activation_preserves_sudo_prefix
run_for_each_os_script test_defers_when_systemd_unavailable
run_for_each_os_script test_activation_failure_is_reported_not_fatal
run_for_each_os_script test_install_docker_defers_without_systemd
run_for_each_os_script test_install_docker_activates_with_systemd
printf 'PASS: docker-service-activation.bash\n'