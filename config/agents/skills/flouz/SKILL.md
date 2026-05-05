---
name: flouz
description: |
  Use this skill when the user wants to manage personal finances with the flouz CLI.
  Covers importing Belgian bank CSV exports, AI-assisted transaction categorization,
  and querying spending data. Trigger on: "import my bank CSV", "categorize transactions",
  "show my spending", "review AI suggestions", "add a comment to a transaction",
  "list uncategorized transactions", or any mention of flouz commands.
  See the subcommand files in this directory for detailed usage per command.
license: MIT
---

# flouz

Personal finance CLI — imports Belgian bank CSVs into SQLite and uses AI to categorize transactions.

## Core workflow

```
import → comment → categorize → review suggestions → apply → list
```

1. **import** — load bank CSVs (duplicates ignored automatically)
2. **comment** — annotate ambiguous transactions before AI sees them
3. **categorize** — AI generates pending suggestions, never touches `category_id`
4. **review** — approve, fix, or reject suggestions
5. **apply** — write approved suggestions to `category_id`
6. **list** — query transactions with filters and output formats

## Key concepts

- `category_id` is user-controlled — only written by `suggestions apply`
- `ai_category_id` is the AI proposal — never silently overwrites user choices
- Suggestions lifecycle: `pending → approved → applied` (or deleted on reject)
- Categories are a 3-level hierarchy; filtering by a parent slug includes all descendants
- All commands accept `--db <path>` to override the default database path

## Subcommand reference

| File                          | Commands covered                     |
| ----------------------------- | ------------------------------------ |
| `config.md`                   | `flouz config get/set`               |
| `accounts.md`                 | `flouz accounts add/list/delete`     |
| `transactions-import.md`      | `flouz transactions import`          |
| `transactions-list.md`        | `flouz transactions list`            |
| `transactions-comment.md`     | `flouz transactions comment`         |
| `transactions-categorize.md`  | `flouz transactions categorize`      |
| `transactions-suggestions.md` | `flouz transactions suggestions *`   |
| `transactions-categories.md`  | `flouz transactions categories list` |
