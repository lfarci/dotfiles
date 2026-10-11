# flouz transactions import

Parses Belgian bank CSV exports and inserts into the database. Duplicate rows are silently ignored.

```sh
flouz transactions import ~/downloads/bank-2024-03.csv
flouz transactions import ~/downloads/exports/        # all *.csv in directory
```

Options: `-d, --db <path>`

- Database is created automatically if it does not exist
- Deduplication key: `(date, amount, counterparty, bankCommunication)`
- Import is transactional per file — a mid-file failure rolls back only that file
- Parse errors are reported as warnings; valid rows in the same file are still imported
