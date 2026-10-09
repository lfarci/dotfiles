# agents

Universal skills store managed by the [skills CLI](https://skills.sh).

`~/.agents/skills/` is the canonical location for installed skills. Each AI agent tool (Claude Code, GitHub Copilot, etc.) has its own vendor-specific skills directory (e.g. `~/.claude/skills/`) that only knows to look there — not at `~/.agents`. The skills CLI bridges this by symlinking each installed skill into every relevant vendor directory. The dotfiles bootstrap also links `~/.copilot/skills/` directly to this tracked store so skills installed with `gh skills install` are captured by the repository.

## Vendoring policy

Skills are **vendored**: the skill content and its lock file are committed to
this repository rather than installed from the network on demand. This is the
current approach and it is intentional — do not remove vendored skills to reduce
the tracked file count, and do not convert them to an install-on-bootstrap step.

Why vendored:

- **Offline and reproducible.** A fresh machine gets working skills from a `git
  clone` with no network fetch and no upstream breakage. Bootstrap stays a
  symlink step, not a package install.
- **Pinned upstream revisions.** The lock file records the exact upstream tree
  each skill was taken from, so a review can always tell what a skill is versus
  what it used to be.
- **Reviewable changes.** Skills are part of the dotfiles diff, so an upstream
  refresh or a deliberate local edit shows up in a pull request instead of
  changing silently on someone's machine.

### Provenance

`.skill-lock.json` is the source of truth for where each skill came from:

| Field | Meaning |
| --- | --- |
| `source` / `sourceUrl` | Upstream repository (`owner/repo` and clone URL) |
| `skillPath` | Path of `SKILL.md` inside that repository |
| `skillFolderHash` | Git tree SHA of the upstream skill folder at install time |
| `pluginName` | Upstream plugin/marketplace the skill was published under, when applicable |
| `installedAt` / `updatedAt` | When the skill was added and last refreshed |

`skillFolderHash` is a git tree hash, so it is reproducible: hashing the
upstream folder at that revision reproduces the recorded value. Recorded hashes
keep resolving upstream even after the source repository moves forward, which is
what makes the pinned revision usable as a review baseline.

The skills CLI also stamps provenance into each vendored `SKILL.md` as
frontmatter (`metadata.github-repo`, `github-path`, `github-ref`,
`github-tree-sha`). `github-tree-sha` matches the lock entry's
`skillFolderHash`.

### Upstream-managed content vs. local modifications

Everything under `skills/<name>/` is upstream-managed unless it is deliberately
changed here. To tell the two apart, compare a skill folder against the upstream
tree recorded in its lock entry:

```bash
# Resolve the pinned upstream tree (skillFolderHash = <tree-sha>)
gh api "repos/<source>/git/trees/<skillFolderHash>?recursive=1"
```

A folder that matches the pinned tree has no local modifications. Any diff is a
local modification and must be treated as intentional, reviewable content.

Two normal, non-modification differences are worth knowing about:

- **Injected frontmatter.** The CLI adds a `metadata:` block to the frontmatter
  of each vendored `SKILL.md`. This is expected and is not a local edit.
- **Materialized symlinks.** Some upstream trees store subdirectories as
  symlinks. Locally they are checked out as real directories, so a byte
  comparison differs even though the content matches the pinned revision.

If a local modification is intentional, keep it minimal and record why in the
pull request that introduces it. Never hand-edit a vendored file to `fix` it
silently — either upstream the change or note the deviation in review, so the
next `npx skills update` does not quietly discard it.

### Updating skills

```
npx skills update
```

The lock file and the content move together. Always commit `skills/` and
`.skill-lock.json` in the same commit — the lock file is what restores skills on
a fresh machine (`npx skills experimental_install`), and committing content
without its lock change means the skill will not be restored.

After any update, confirm the lock file and the vendored directories still agree.
This check needs nothing beyond Node, which the skills CLI already requires:

```bash
node -e '
const fs = require("fs");
const read = (p) => JSON.parse(fs.readFileSync(p, "utf8"));
const locked = Object.keys(read("config/agents/.skill-lock.json").skills).sort();
const vendored = fs.readdirSync("config/agents/skills").sort();
const diff = (a, b) => a.filter((x) => !b.includes(x));
console.log("locked but not vendored:", diff(locked, vendored));
console.log("vendored but not locked:", diff(vendored, locked));
'
```

Both lists should be empty. A skill in the lock file with no vendored directory,
or a vendored skill with no lock entry, is drift and should be resolved in the
same commit.

> Known drift (documented, not fixed here): `brainstorming` is in the lock file
> with no vendored directory, and `xlsx` is vendored with no lock entry.

When comparing vendored content on Windows, normalize line endings before
hashing — this repository checks out CRLF (`core.autocrlf=true`) while the
stored blobs are LF, so a raw byte comparison reports every file as changed.

### Reviewing skill refreshes

Keep a skill refresh in its own commit or pull request, separate from bootstrap
logic changes (`bootstrap/`, symlink mappings, `os/*`, package lists). A refresh
should be reviewable on its own terms: which upstream revisions moved, what
changed in the content, and whether any local modification survived or was lost.

- One refresh per PR, with the lock diff and the content diff together.
- Bootstrap or symlink changes never ride along in a refresh PR, and a refresh
  never rides along in a bootstrap PR.
- Re-running the bootstrap is only needed when *what* gets installed or linked
  changes — not when skill contents change, because the paths are already
  symlinked.

## Adding skills

```
npx skills add <source> --skill <name> --yes --global
```

Then commit `skills/` and `.skill-lock.json` together (see above). New skills
are subject to the same provenance and review rules as refreshed ones.

## Files

- `skills/` — installed skill packages (vendored, upstream-managed unless noted)
- `.skill-lock.json` — lock file tracking installed skills, their sources, and
  the pinned upstream tree for each
