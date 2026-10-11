# AGENTS.md — vendored skills

`config/agents/` is the tracked skills store managed by the
[skills CLI](https://skills.sh). Everything under `skills/<name>/` is
**upstream-vendored** unless it was deliberately modified here. Read
[`README.md`](README.md) in this directory for the full policy; this file is the
short list of rules to follow while working.

## Rules

- **Do not hand-edit a vendored file to "fix" it.** Either upstream the change
  or record the deviation (reason + which skill) in the PR. The next
  `npx skills update` will silently discard undocumented local edits.
- **Do not remove vendored skills** to shrink the tracked file count, and do not
  convert the store to a dynamic install-on-bootstrap step. Vendoring is
  intentional (offline, pinned, reviewable).
- **Commit `skills/` and `.skill-lock.json` together, in the same commit.** The
  lock file is what restores skills on a fresh machine; content without its lock
  change will not be restored. Never invent or hand-edit a `skillFolderHash`.
- **Use the supported CLI workflow** to add or refresh skills, so provenance
  stays current:
  ```bash
  npx skills add <source> --skill <name> --yes --global
  npx skills update
  ```
- **Keep refreshes isolated.** One refresh per PR with its lock + content diffs;
  bootstrap/symlink/`os/`/package changes must not ride along, and vice versa.
- **Do not touch `.gitattributes` for this tree.** `config/agents/**` is left to
  `text=auto` on purpose; marking it `-text`/`eol=lf` reports every vendored file
  as modified on a CRLF worktree and rewrites blobs owned upstream. This tree is
  also excluded from ShellCheck and PSScriptAnalyzer by scope, not by attributes.
- **Do not lint or reformat vendored content.** CI lint file lists deliberately
  exclude `config/agents/`.

## Verify

The lock and the on-disk skill directories must describe the same set of names
(equal counts are not enough):

```bash
node tests/skills-inventory-consistency.mjs
# or, with fixture coverage: bash tests/skills-inventory-consistency.bash
```

## Known state

As of this writing the two inventories agree (22 locked, 22 vendored) and the
consistency check passes. If it ever reports drift, resolve it through the CLI
workflow in a dedicated refresh commit — do not fix it silently here.
