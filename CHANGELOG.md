# Changelog

## 0.4.0

- Restore primary branch — the primary branch (default: `main`) writes to `public` so feature branches see shared state via `search_path` fallthrough
- Comprehensive test suite: workflow tests, full DDL coverage (69 tests, 163 assertions)
- Rewrite README from first principles

## 0.3.0

- Add `db:branch:console` rake task — opens psql with the branch `search_path`

## 0.2.0

- Add shadow interception for `add_foreign_key`, `remove_foreign_key`, `add_check_constraint`, `remove_check_constraint`, `validate_foreign_key`, `validate_check_constraint`
- Simplify branch resolution to `PGBRANCH` env var with git fallback
- Remove `branch_override` config option and `BRANCH` env var
- `db:branch:prune` accepts `KEEP=branch1,branch2` for explicit control
- Fix railtie to reuse the adapter's existing BranchManager
- Pass shadow to `activate` instead of creating a redundant instance
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
