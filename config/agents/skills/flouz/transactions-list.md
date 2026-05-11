# flouz transactions list

Query transactions with filters. Use `--output json` for agent pipelines.

```sh
flouz transactions list
flouz transactions list --from 2024-01-01 --to 2024-03-31
flouz transactions list --category groceries   # includes all subcategories
flouz transactions list --search delhaize
flouz transactions list --uncategorized
flouz transactions list --output json | jq '[.[] | select(.amount | startswith("-"))]'
flouz transactions list --output csv > export.csv
```

Options:

| Option                    | Description                             |
| ------------------------- | --------------------------------------- |
| `-f, --from` / `-t, --to` | Date range (YYYY-MM-DD)                 |
| `-c, --category <slug>`   | Category filter — includes descendants  |
| `-s, --search <text>`     | Search counterparty                     |
| `-l, --limit <n>`         | Max results                             |
| `--uncategorized`         | Only transactions without `category_id` |
| `-o, --output`            | `table` (default) \| `csv` \| `json`    |

`--category` and `--uncategorized` are mutually exclusive.

JSON fields: `date`, `amount` (string with explicit sign, e.g. `+10.00` or `-42.50`), `counterparty`, `note` (user comment, if any), `category`
