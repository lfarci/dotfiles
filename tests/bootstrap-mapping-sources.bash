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

# Symlinks are unavailable on some platforms (e.g. Git for Windows without
# developer mode, where `ln -s` degrades to a copy). Symlink-dependent
# assertions are skipped rather than reported as failures.
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

# Seed entries carry a "seed:" prefix in bootstrap.sh and a Seed key in
# bootstrap.ps1, so the link parsers above cannot mistake them for symlink
# mappings: seeds are copied only when the destination is missing.
parse_bash_seeds() {
  sed -n 's/.*"\(seed:config\/[^"]*:[^"]*\)".*/\1/p' "$REPO_DIR/bootstrap.sh" | sed 's/^seed://'
}

parse_powershell_seeds() {
  sed -n "s/.*@{ Seed = '\(config\\\\[^']*\)'.*/\1/p" "$REPO_DIR/bootstrap.ps1" | tr '\\' '/'
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
  done < <(parse_bash_mappings; parse_bash_seeds; parse_powershell_mappings; parse_powershell_seeds)

  if [[ -n "$missing" ]]; then
    fail "bootstrap mappings reference missing sources:
$missing"
  fi
}

# A stale extraction pattern must fail loudly instead of vacuously passing on
# an empty list, so both parsers are required to return a plausible number of
# entries.
test_extraction_finds_mappings() {
  local bash_count powershell_count bash_seed_count powershell_seed_count
  bash_count="$(parse_bash_mappings | wc -l)"
  powershell_count="$(parse_powershell_mappings | wc -l)"
  bash_seed_count="$(parse_bash_seeds | wc -l)"
  powershell_seed_count="$(parse_powershell_seeds | wc -l)"

  [[ "$bash_count" -ge 10 ]] ||
    fail "expected >=10 bootstrap.sh mappings, extraction found $bash_count; pattern may be stale"
  [[ "$powershell_count" -ge 8 ]] ||
    fail "expected >=8 bootstrap.ps1 mappings, extraction found $powershell_count; pattern may be stale"
  [[ "$bash_seed_count" -ge 1 ]] ||
    fail "expected >=1 bootstrap.sh seed, extraction found $bash_seed_count; pattern may be stale"
  [[ "$powershell_seed_count" -ge 1 ]] ||
    fail "expected >=1 bootstrap.ps1 seed, extraction found $powershell_seed_count; pattern may be stale"
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

# seed_all must copy a seed source into a missing destination and must never
# overwrite an existing one: after the first copy the TUI owns cli.json.
test_seed_copies_missing_and_never_overwrites() (
  local fixture entry src dst
  fixture="$(mktemp -d)"
  trap 'rm -rf "$fixture"' EXIT

  DOTFILES_DIR="$REPO_DIR" HOME="$fixture" seed_all >/dev/null

  while IFS= read -r entry; do
    [[ -n "$entry" ]] || continue
    src="${entry%%:*}"
    dst="${entry#*:}"
    if [[ ! -f "$fixture/$dst" ]]; then
      fail "seed_all did not create '$dst'"
    fi
    if ! cmp -s "$fixture/$dst" "$REPO_DIR/$src"; then
      fail "'$dst' does not match the tracked seed source"
    fi
  done < <(parse_bash_seeds)

  # A later run must leave live (TUI-written) content untouched.
  printf 'live-tui-prefs\n' > "$fixture/.config/opencode/cli.json"
  DOTFILES_DIR="$REPO_DIR" HOME="$fixture" seed_all >/dev/null
  if [[ "$(cat "$fixture/.config/opencode/cli.json")" != "live-tui-prefs" ]]; then
    fail "seed_all overwrote an existing destination"
  fi
)

main() {
  test_extraction_finds_mappings
  test_sources_exist
  if can_symlink; then
    test_link_all_creates_declared_links
  else
    printf 'SKIP: link assertions (symlink creation unavailable)\n'
  fi
  test_seed_copies_missing_and_never_overwrites
  printf 'mapping sources verified: %s bash links, %s PowerShell links, %s bash seeds, %s PowerShell seeds\n' \
    "$(parse_bash_mappings | sort -u | wc -l)" \
    "$(parse_powershell_mappings | sort -u | wc -l)" \
    "$(parse_bash_seeds | sort -u | wc -l)" \
    "$(parse_powershell_seeds | sort -u | wc -l)"
  printf 'PASS: bootstrap-mapping-sources.bash\n'
}

main "$@"
