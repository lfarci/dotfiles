#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TEST_DIR/.." && pwd)"
GITCONFIG="$REPO_DIR/config/git/.gitconfig"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

# The tracked config includes ~/.gitconfig.local, so point HOME at an isolated
# directory to keep the checks independent of the machine running the tests.
export HOME="$TMP_ROOT/home"
mkdir -p "$HOME"

# The tracked config must not hard-code a Linux-only gh path: it must resolve
# gh from PATH so it works with both Git for Windows and Linux Git.
test_no_absolute_gh_path() {
  ! grep -Fq -- '!/usr/bin/gh' "$GITCONFIG" ||
    fail "gitconfig still hard-codes the Linux-only /usr/bin/gh path"
  grep -Fq -- 'helper = !gh auth git-credential' "$GITCONFIG" ||
    fail "gitconfig does not use a PATH-resolved gh credential helper"
}

# ~/.gitconfig.local must be included after the credential section so local
# authentication overrides win over the tracked default.
test_local_include_wins() {
  local git_include line credential_line
  git_include="$(git config --file "$GITCONFIG" --get include.path)" ||
    fail "gitconfig does not include a .gitconfig.local"
  [[ "$git_include" == *".gitconfig.local" ]] ||
    fail "unexpected include path: $git_include"

  line="$(git config --file "$GITCONFIG" --list | grep -n '^include\.path=' | cut -d: -f1)"
  credential_line="$(git config --file "$GITCONFIG" --list | grep -n '^credential\.' | tail -n1 | cut -d: -f1)"
  [[ -n "$line" && "$line" -gt "$credential_line" ]] ||
    fail "include is not ordered after the credential section"
}

# Exercise credential fill with a local helper that returns a distinct
# credential. Helpers are chained by Git, so inspect the result and confirm
# the tracked gh helper was not invoked rather than only checking config order.
test_local_override_beats_default() {
  local output
  cat > "$HOME/.gitconfig.local" <<'EOF'
[credential "https://github.com"]
	helper =
	helper = !printf 'username=local-user\\npassword=local-secret\\n\\n'
EOF

  export GIT_CONFIG_GLOBAL="$GITCONFIG"
  export GIT_CONFIG_NOSYSTEM=1
  unset GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT || true
  unset GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0 GIT_CONFIG_KEY_1 GIT_CONFIG_VALUE_1 || true
  unset GIT_CONFIG_KEY_2 GIT_CONFIG_VALUE_2 || true

  local temp_dir="$TMP_ROOT/override"
  local bin_dir="$temp_dir/bin"
  mkdir -p "$bin_dir"
  cp "$TEST_DIR/fixtures/gh-stub.bash" "$bin_dir/gh"
  chmod +x "$bin_dir/gh"
  export DOTFILES_GH_LOG="$temp_dir/gh.log"

  output="$(printf 'protocol=https\nhost=github.com\n\n' | PATH="$bin_dir:$PATH" git credential fill)"
  [[ "$output" == *"username=local-user"* && "$output" == *"password=local-secret"* ]] ||
    fail "git credential fill did not use the local helper (got: $output)"
  [[ ! -e "$DOTFILES_GH_LOG" ]] ||
    fail "tracked gh helper ran despite the local helper override"
  rm -f "$HOME/.gitconfig.local"
}

# Resolve the helper through git with a stub gh on PATH and confirm git invokes
# it. No real credentials, gh installation, or network access is required.
test_helper_invocation() {
  local temp_dir bin_dir output
  temp_dir="$TMP_ROOT/invoke"
  mkdir -p "$temp_dir"

  bin_dir="$temp_dir/bin"
  mkdir -p "$bin_dir"
  cp "$TEST_DIR/fixtures/gh-stub.bash" "$bin_dir/gh"
  chmod +x "$bin_dir/gh"

  export DOTFILES_GH_LOG="$temp_dir/gh.log"
  export GIT_CONFIG_GLOBAL="$GITCONFIG"
  export GIT_CONFIG_NOSYSTEM=1
  export GIT_TERMINAL_PROMPT=0
  unset GIT_ASKPASS GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT || true

  output="$(
    printf 'protocol=https\nhost=github.com\n\n' |
      PATH="$bin_dir:$PATH" git credential fill
  )"

  [[ "$output" == *"username=stub-user"* ]] ||
    fail "git did not return credentials from the stub gh helper"
  [[ "$(cat "$DOTFILES_GH_LOG")" == "auth git-credential get" ]] ||
    fail "stub gh helper was not invoked as 'gh auth git-credential get'"
}

test_no_absolute_gh_path
test_local_include_wins
test_local_override_beats_default
test_helper_invocation
printf 'PASS: git-credential-helper.bash\n'
