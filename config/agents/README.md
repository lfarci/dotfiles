# agents

Universal skills store managed by the [skills CLI](https://skills.sh).

`~/.agents/skills/` is the canonical location for installed skills. Each AI agent tool (Claude Code, GitHub Copilot, etc.) has its own vendor-specific skills directory (e.g. `~/.claude/skills/`) that only knows to look there — not at `~/.agents`. The skills CLI bridges this by symlinking each installed skill into every relevant vendor directory. The dotfiles bootstrap also links `~/.copilot/skills/` directly to this tracked store so skills installed with `gh skills install` are captured by the repository.

## Adding skills

```
npx skills add <source> --skill <name> --yes --global
```

Always commit `skills/` and `.skill-lock.json` together — the lock file is what
restores skills on a fresh machine. Use `npx skills update` to refresh installed
skills so the lock stays current.

## Inventory consistency

`skills/` and `.skill-lock.json` must describe the same set of skill *names*.
Equal entry counts are not sufficient — an orphaned lock entry and an unlocked
skill directory cancel out. `tests/skills-inventory-consistency.mjs` compares the
two inventories bidirectionally and reports any skill that is locked but missing
on disk, or present on disk but missing from the lock:

```
node tests/skills-inventory-consistency.mjs
```

It runs offline (no CLI download, no network) and exits non-zero on drift. The
wrappers `tests/skills-inventory-consistency.bash` and
`tests/skills-inventory-consistency.Tests.ps1` add fixture coverage and run in CI.

Reconcile drift through the supported CLI workflow rather than editing the lock
by hand — never invent a `skillFolderHash`. To restore on a fresh machine, run
the bootstrap, which stages the tracked lock so `npx skills experimental_install`
installs into this store (`~/.agents/skills/`).

## Files

- `skills/` — installed skill packages
- `.skill-lock.json` — lock file tracking installed skills and their sources
