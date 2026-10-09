#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TEST_DIR/.." && pwd)"
SETTINGS="$REPO_DIR/config/windows-terminal/settings.json"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

find_python() {
  local candidate
  for candidate in python3 python py; do
    if command -v "$candidate" >/dev/null 2>&1 &&
      "$candidate" -c 'import sys' >/dev/null 2>&1; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  return 1
}

PYTHON="$(find_python)" || fail "a working python interpreter is required to validate Windows Terminal settings"

# Guards the invariants fixed in #14: the default profile must resolve without
# assuming a particular WSL distro, shared fonts must live in profile defaults,
# and no machine-specific WSL profile may be hardcoded.
"$PYTHON" - "$SETTINGS" <<'PY' || fail "Windows Terminal settings validation failed"
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    settings = json.load(handle)

default_profile = settings["defaultProfile"]
profiles = settings["profiles"]
listed = {profile["guid"].lower() for profile in profiles["list"] if "guid" in profile}

if default_profile.lower() not in listed:
    raise SystemExit(
        f"defaultProfile {default_profile} does not resolve to an explicit profile"
    )

font_face = profiles.get("defaults", {}).get("font", {}).get("face")
if font_face != "JetBrainsMono Nerd Font":
    raise SystemExit(
        "profiles.defaults.font.face must be 'JetBrainsMono Nerd Font' so shared "
        "font settings apply to Command Prompt and dynamically discovered profiles"
    )

for profile in profiles["list"]:
    name = profile.get("name", "")
    if name.lower().startswith("ubuntu"):
        raise SystemExit(
            f"machine-specific WSL profile '{name}' must not be hardcoded"
        )
PY

printf 'PASS: windows-terminal-settings.bash\n'
