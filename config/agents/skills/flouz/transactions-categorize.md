# flouz transactions categorize

Runs AI categorization and stores results as pending suggestions. Never modifies `category_id` directly.

```sh
flouz transactions categorize                     # all eligible transactions
flouz transactions categorize --from 2024-03-01
flouz transactions categorize --limit 50          # useful for API quota management
flouz transactions categorize --override          # re-categorize already-categorized ones
```

Options: `-f, --from`, `-t, --to`, `-s, --search`, `-l, --limit`, `--override`, `-d, --db`

Eligible by default: transactions with no `category_id` and no existing pending suggestion. `--override` lifts this restriction.

Requires `github-token` — run `flouz config set github-token <token>` first. If interrupted, already-created suggestions are preserved; re-run to continue.
