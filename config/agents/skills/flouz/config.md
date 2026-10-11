# flouz config

Manages persistent configuration at `~/.config/flouz/config.json`.

```sh
flouz config get                                 # print all values
flouz config get db-path                         # print one value
flouz config set db-path ~/finance.db
flouz config set github-token <github_token>    # required for AI categorization
flouz config set ai-model openai/gpt-4o
flouz config set ai-base-url https://models.github.ai/inference
```

| Key            | Default                              |
| -------------- | ------------------------------------ |
| `db-path`      | `~/.config/flouz/flouz.db`           |
| `github-token` | _(not set)_                          |
| `ai-model`     | `openai/gpt-4o-mini`                 |
| `ai-base-url`  | `https://models.github.ai/inference` |

`github-token` is masked as `***` in `config get` output.
