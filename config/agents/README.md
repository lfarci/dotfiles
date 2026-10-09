# agents

Universal skills store managed by the [skills CLI](https://skills.sh).

`~/.agents/skills/` is the canonical location for installed skills. Each AI agent tool (Claude Code, GitHub Copilot, etc.) has its own vendor-specific skills directory (e.g. `~/.claude/skills/`) that only knows to look there — not at `~/.agents`. The skills CLI bridges this by symlinking each installed skill into every relevant vendor directory. The dotfiles bootstrap also links `~/.copilot/skills/` directly to this tracked store so skills installed with `gh skills install` are captured by the repository.

## Adding skills

```
npx skills add <source> --skill <name> --yes --global
```

Always commit `skills/` and `.skill-lock.json` together — the lock file is what
restores skills on a fresh machine (`npx skills experimental_install`). Use
`npx skills update` to refresh installed skills so the lock stays current.

## Files

- `skills/` — installed skill packages
- `.skill-lock.json` — lock file tracking installed skills and their sources
