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

# bootstrap.sh declares mappings as "source:destination" strings inside
# link_mappings. Return each quoted entry verbatim, one per line.
parse_bash_mappings() {
  sed -n 's/.*"\(config\/[^"]*:[^"]*\)".*/\1/p' "$REPO_DIR/bootstrap.sh"
}

# bootstrap.ps1 declares mappings as @{ Src = 'config\...'; Dst = ... }.
# Extract the source half and normalize backslashes so both bootstraps can be
# checked against the same tracked tree.
parse_powershell_mappings() {
  sed -n "s/.*@{ Src = '\(config\\\\[^']*\)'.*/\1/p" "$REPO_DIR/bootstrap.ps1" | tr '\\' '/'
}

# Every parsed source must exist in the repository. This catches typos and
# files deleted from config/ while their symlink mapping survived, without
# duplicating the mapping list here.
test_sources_exist() {
  local missing="" src
  while IFS= read -r entry; do
    [[ -n "$entry" ]] || continue
    src="${entry%%:*}"
    if [[ ! -e "$REPO_DIR/$src" ]]; then
      missing+="  $src"$'\n'
    fi
  done < <(parse_bash_mappings; parse_powershell_mappings)

  if [[ -n "$missing" ]]; then
    fail "bootstrap mappings reference missing sources:
$missing"
  fi
}

# A stale extraction pattern must fail loudly instead of vacuously passing on
# an empty list, so both parsers are required to return a plausible number of
# entries.
test_extraction_finds_mappings() {
  local bash_count powershell_count
  bash_count="$(parse_bash_mappings | wc -l)"
  powershell_count="$(parse_powershell_mappings | wc -l)"

  [[ "$bash_count" -ge 10 ]] ||
    fail "expected >=10 bootstrap.sh mappings, extraction found $bash_count; pattern may be stale"
  [[ "$powershell_count" -ge 8 ]] ||
    fail "expected >=8 bootstrap.ps1 mappings, extraction found $powershell_count; pattern may be stale"
}

# link_all must actually link every declared destination to its source. Run it
# against a fixture HOME so the real one is never touched.
test_link_all_creates_declared_links() (
  local fixture entry src dst
  fixture="$(mktemp -d)"
  trap 'rm -rf "$fixture"' EXIT

  DOTFILES_DIR="$REPO_DIR" HOME="$fixture" link_all >/dev/null

  while IFS= read -r entry; do
    [[ -n "$entry" ]] || continue
    src="${entry%%:*}"
    dst="${entry#*:}"
    if [[ ! -L "$fixture/$dst" ]]; then
      fail "link_all did not create a symlink at '$dst'"
    fi
    if [[ "$(readlink -f "$fixture/$dst")" != "$(readlink -f "$REPO_DIR/$src")" ]]; then
      fail "'$dst' does not resolve to '$src'"
    fi
  done < <(parse_bash_mappings)
)

main() {
  test_extraction_finds_mappings
  test_sources_exist
  test_link_all_creates_declared_links
  printf 'OK: bootstrap mapping sources verified (%s bash, %s PowerShell)\n' \
    "$(parse_bash_mappings | sort -u | wc -l)" \
    "$(parse_powershell_mappings | sort -u | wc -l)"
}

main "$@"
