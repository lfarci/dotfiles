#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TEST_DIR/.." && pwd)"

# shellcheck source=../bootstrap.sh
source "$REPO_DIR/bootstrap.sh"

EXPECTED_EXTENSIONS=(
  "catppuccin.catppuccin-vsc"
  "catppuccin.catppuccin-vsc-icons"
  "PKief.material-icon-theme"
  "ms-dotnettools.csharp"
  "stackbreak.comment-divider"
  "github.vscode-github-actions"
  "github.vscode-pull-request-github"
  "codezombiech.gitignore"
  "mermaidchart.vscode-mermaid-chart"
)

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

make_code_stub() {
  local stub_dir="$1"
  mkdir -p "$stub_dir"
  cp "$TEST_DIR/fixtures/code-stub.bash" "$stub_dir/code"
  chmod +x "$stub_dir/code"
}

test_success() (
  local temp_dir
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT

  make_code_stub "$temp_dir/bin"
  export DOTFILES_CODE_LOG="$temp_dir/code.log"
  export DOTFILES_CODE_FAIL_IDS=""

  OS=windows PATH="$temp_dir/bin:$PATH" install_vscode_extensions

  [[ "$(wc -l < "$DOTFILES_CODE_LOG")" -eq "${#EXPECTED_EXTENSIONS[@]}" ]] ||
    fail "expected ${#EXPECTED_EXTENSIONS[@]} code invocations"

  local extension
  for extension in "${EXPECTED_EXTENSIONS[@]}"; do
    [[ "$(grep -Fxc -- "--install-extension $extension --force" "$DOTFILES_CODE_LOG")" -eq 1 ]] ||
      fail "missing or duplicate install for $extension"
  done
)

test_aggregate_failure() (
  local temp_dir output
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT

  make_code_stub "$temp_dir/bin"
  export DOTFILES_CODE_LOG="$temp_dir/code.log"
  export DOTFILES_CODE_FAIL_IDS="ms-dotnettools.csharp mermaidchart.vscode-mermaid-chart"

  if output="$(OS=windows PATH="$temp_dir/bin:$PATH" install_vscode_extensions 2>&1)"; then
    fail "expected extension installation to fail"
  fi

  [[ "$output" == *"ms-dotnettools.csharp"* ]] ||
    fail "aggregate error omitted ms-dotnettools.csharp"
  [[ "$output" == *"mermaidchart.vscode-mermaid-chart"* ]] ||
    fail "aggregate error omitted mermaidchart.vscode-mermaid-chart"
  [[ "$(wc -l < "$DOTFILES_CODE_LOG")" -eq "${#EXPECTED_EXTENSIONS[@]}" ]] ||
    fail "installer stopped before processing the full manifest"
)

test_manifest_parsing() (
  local temp_dir
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT

  make_code_stub "$temp_dir/bin"
  mkdir -p "$temp_dir/repo/config/vscode"
  {
    printf '# comment\n'
    printf '  catppuccin.catppuccin-vsc  # inline comment\n'
    printf '\n'
    printf '\tPKief.material-icon-theme\t\n'
  } > "$temp_dir/repo/config/vscode/extensions.txt"

  export DOTFILES_CODE_LOG="$temp_dir/code.log"
  export DOTFILES_CODE_FAIL_IDS=""
  DOTFILES_DIR="$temp_dir/repo"

  OS=windows PATH="$temp_dir/bin:$PATH" install_vscode_extensions

  [[ "$(wc -l < "$DOTFILES_CODE_LOG")" -eq 2 ]] ||
    fail "comments, blank lines, or whitespace were not parsed correctly"
  grep -Fqx -- "--install-extension catppuccin.catppuccin-vsc --force" "$DOTFILES_CODE_LOG" ||
    fail "inline comments were not removed"
  grep -Fqx -- "--install-extension PKief.material-icon-theme --force" "$DOTFILES_CODE_LOG" ||
    fail "surrounding whitespace was not removed"
)

test_missing_cli() (
  local empty_path
  empty_path="$(mktemp -d)"
  trap 'rm -rf "$empty_path"' EXIT

  PATH="$empty_path" OS=ubuntu install_vscode_extensions
  if PATH="$empty_path" OS=windows install_vscode_extensions; then
    fail "missing code CLI must fail on WSL"
  fi
)

test_success
test_aggregate_failure
test_manifest_parsing
test_missing_cli
printf 'PASS: bootstrap-vscode-extensions.bash\n'
