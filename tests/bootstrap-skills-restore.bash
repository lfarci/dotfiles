#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TEST_DIR/.." && pwd)"
# shellcheck source=../bootstrap.sh
source "$REPO_DIR/bootstrap.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT
export HOME="$temp_dir/home"
mkdir -p "$HOME/.agents/skills" "$temp_dir/bin"
printf '{"version":3,"skills":{"sample":{"source":"fixture"}}}\n' > "$HOME/.agents/.skill-lock.json"
cp "$HOME/.agents/.skill-lock.json" "$temp_dir/expected-lock.json"

# The system mktemp path is discoverable by the fake CLI through PWD; assert its
# generated staging directory is removed immediately after Restore returns.
cat > "$temp_dir/bin/npx" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" > "$DOTFILES_NPX_ARGS"
printf '%s\n' "$PWD" > "$DOTFILES_STAGE_SEEN_FILE"
[[ -L .agents && "$(readlink -f .agents)" == "$DOTFILES_EXPECTED_AGENTS" ]] || exit 33
cmp -s skills-lock.json "$DOTFILES_EXPECTED_LOCK" || exit 34
[[ "$*" == 'skills experimental_install -y' ]] || exit 35
mkdir -p .agents/skills/restored-fixture
STUB
chmod +x "$temp_dir/bin/npx"
export PATH="$temp_dir/bin:$PATH"
export DOTFILES_NPX_ARGS="$temp_dir/args"
export DOTFILES_STAGE_SEEN_FILE="$temp_dir/stage-path"
export DOTFILES_EXPECTED_AGENTS="$HOME/.agents"
export DOTFILES_EXPECTED_LOCK="$temp_dir/expected-lock.json"

install_skills
[[ "$(cat "$DOTFILES_NPX_ARGS")" == 'skills experimental_install -y' ]] || fail 'wrong npx invocation'
[[ -d "$HOME/.agents/skills/restored-fixture" ]] || fail 'restore output did not reach tracked skills store'
stage_seen="$(cat "$DOTFILES_STAGE_SEEN_FILE")"
[[ ! -e "$stage_seen" ]] || fail 'staging directory was not removed'
printf 'PASS: bootstrap-skills-restore.bash\n'
