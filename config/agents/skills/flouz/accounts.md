# flouz accounts

Optional. Register named bank accounts so transactions are linked to a specific account on import.

```sh
flouz accounts add <key> <name> <company> [--description <text>] [--iban <iban>]
flouz accounts list
flouz accounts delete <key>   # fails if transactions reference this account
```

- `key` must match the key column in CSV exports
- `--iban` and `--description` are optional metadata
