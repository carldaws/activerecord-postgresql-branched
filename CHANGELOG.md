# Changelog

## 0.2.0

- Remove primary branch concept — every branch gets its own schema equally
- Add shadow interception for `add_foreign_key`, `remove_foreign_key`, `add_check_constraint`, `remove_check_constraint`, `validate_foreign_key`, `validate_check_constraint`
- Simplify branch resolution to `PGBRANCH` env var with git fallback
- Remove `branch_override` config option and `BRANCH` env var
- `db:branch:prune` accepts `KEEP=branch1,branch2` for explicit control
- Fix railtie to reuse the adapter's existing BranchManager
- Fix redundant Shadow instantiation in migration table shadowing
- Quote schema identifiers consistently in shadow SQL

## 0.1.0

Initial release.

- PostgreSQL adapter that isolates each git branch in its own Postgres schema
- Shadow rule: automatically copies public tables before branch-local DDL
- Clean `schema.rb` output with no branch schema references
- `schema_migrations` and `ar_internal_metadata` isolated per branch
- Schema names truncated to 63 bytes with collision-safe hashing
- Rake tasks: `db:branch:reset`, `discard`, `list`, `diff`, `prune`
- Branch override via `branch_override` config or `PGBRANCH` env var
