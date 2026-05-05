# flouz transactions comment

Interactively add or edit free-text comments on transactions. Comments are visible to the AI during categorization — run this before `categorize` to improve accuracy on ambiguous counterparties.

```sh
flouz transactions comment                        # review all
flouz transactions comment 42                     # jump to transaction 42
flouz transactions comment --search virement --limit 10
```

Options: `-f, --from`, `-t, --to`, `-s, --search`, `-l, --limit`, `-d, --db`

Interactive choices: **Add/Update comment**, **Clear comment**, **Skip**, **Quit**
