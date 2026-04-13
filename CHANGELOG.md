# Changelog

## 0.1.0

Initial release.

- PostgreSQL adapter that isolates each git branch in its own Postgres schema
- Shadow rule: automatically copies public tables before branch-local DDL
- Clean `schema.rb` output with no branch schema references
- `schema_migrations` and `ar_internal_metadata` isolated per branch
- Schema names truncated to 63 bytes with collision-safe hashing
- Rake tasks: `db:branch:reset`, `discard`, `list`, `diff`, `prune`
- Branch override via `branch_override` config or `PGBRANCH` env var
