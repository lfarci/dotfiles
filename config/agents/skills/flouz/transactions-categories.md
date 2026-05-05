# flouz transactions categories

Discover category slugs used in `--category` filters and `suggestions fix --category`.

```sh
flouz transactions categories list           # flat table: slug, name, UUID
flouz transactions categories list --tree    # hierarchy tree
```

Categories are a 3-level hierarchy: `root → subcategory → leaf` (e.g. `necessities → necessities.housing → necessities.housing.rent`). Filtering by a parent slug includes all descendants.
