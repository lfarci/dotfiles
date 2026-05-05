# flouz transactions suggestions

Manage AI-generated category suggestions. Lifecycle: `pending → approved → applied` (or deleted on reject).

```sh
# Inspect
flouz transactions suggestions list                      # pending (default)
flouz transactions suggestions list --status approved
flouz transactions suggestions list --status applied

# Interactive review (approve / fix / reject / skip / quit per suggestion)
flouz transactions suggestions review
flouz transactions suggestions review --search amazon --limit 20

# Bulk approve
flouz transactions suggestions approve
flouz transactions suggestions approve --search delhaize

# Fix one suggestion by transaction ID
flouz transactions suggestions fix --id 42 --category groceries.supermarkets

# Reject
flouz transactions suggestions reject
flouz transactions suggestions reject --status approved  # reject already-approved

# Apply approved → writes category_id to transactions
flouz transactions suggestions apply
```

Common options on `list`, `review`, `approve`, `reject`, and `apply`: `-f, --from`, `-t, --to`, `-s, --search`, `-l, --limit`, `-d, --db`

`fix` is the exception: it supports `--id <transactionId>`, `--category <slug>`, and `-d, --db` only. Cannot fix an already-applied suggestion.

`reject --status` accepts `pending` (default) or `approved`.

`apply` is the only operation that modifies `category_id` on transactions.
