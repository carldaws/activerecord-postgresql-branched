# activerecord-postgresql-branched

A Rails database adapter that gives each branch its own PostgreSQL schema. Your database structure follows your branch, just like your code does.

## The problem

You're working on a feature branch. You write a migration that adds a column to `users`. You run it. Then you need to switch branches — a review, a hotfix, something urgent.

The other branch knows nothing about that column. But your development database does. `schema.rb` is dirty. Migrations are out of sync. If the other branch has its own migration, you now have two branches' worth of structural changes in one database with no way to tell which change belongs where.

You either undo your migration before switching (and redo it when you come back), maintain multiple databases by hand, or just live with the mess. None of these are good.

Git solved this problem for code decades ago. This adapter solves it for your database.

## Installation

```ruby
# Gemfile
gem 'activerecord-postgresql-branched'
```

```yaml
# config/database.yml
development:
  adapter: postgresql_branched
  database: myapp_development
```

Set the `PGBRANCH` environment variable to name your branch, or let the adapter detect it from git automatically:

```bash
export PGBRANCH=feature/payments
```

That's it. No PostgreSQL extensions, no initializers, no extra configuration.

## How it works

On connection, the adapter creates a dedicated PostgreSQL schema for the current branch and sets `search_path`:

```
PGBRANCH=feature/payments

schema:      branch_feature_payments
search_path: branch_feature_payments, public
```

New tables go into the branch schema. Queries against tables that don't exist in the branch schema fall through to `public` via standard PostgreSQL name resolution. No data copying for reads.

### The shadow rule

When a migration modifies a table that exists in `public` but not yet in the branch schema, the adapter **shadows** it first — copies the table structure and data into the branch schema, then applies the DDL to the copy:

```
add_column :users, :bio, :string

1. CREATE TABLE branch_feature_payments.users (LIKE public.users INCLUDING ALL)
2. INSERT INTO branch_feature_payments.users SELECT * FROM public.users
3. ALTER TABLE users ADD COLUMN bio VARCHAR
```

The public table is never touched. Step 3 operates on the shadow because `search_path` resolves `users` to the branch schema first.

This applies to any DDL that modifies an existing table: `add_column`, `remove_column`, `add_index`, `add_foreign_key`, `drop_table`, and so on.

### schema.rb stays clean

`db:schema:dump` presents a unified view as if everything lived in `public`:

- Branch-local tables appear without schema prefixes
- Shadowed tables show the branch version (with new columns, dropped indexes, etc.)
- Public tables the branch hasn't touched are included as normal

The diff for a schema change looks exactly as it always has. Switch branches, and `schema.rb` reflects that branch's database state — not the accumulated mess of every migration you've run lately.

## Switching branches

This is the whole point. When you switch git branches:

- The new branch gets its own schema (created on first connection if needed)
- Its migrations are tracked independently
- Tables it hasn't touched fall through to `public`
- Tables it has modified are isolated in its own schema

Switch back, and your previous branch's state is exactly where you left it.

## Deploying

The adapter is for development and test only. Production and staging use the standard `postgresql` adapter — migrations land directly in the database as they always have. The canonical schema advances through your normal deployment process.

## Rebasing

```bash
git fetch && git rebase origin/main
rails db:branch:reset
rails db:migrate
```

`db:branch:reset` drops the branch schema. Queries fall through to `public`. Re-running `db:migrate` reapplies your branch's migrations on top of the current baseline.

## Parallel agents

The same isolation that helps you switch branches also helps when running multiple AI agents in parallel, each on its own worktree:

```bash
PGBRANCH=agent-0 bundle exec rails ...
PGBRANCH=agent-1 bundle exec rails ...
PGBRANCH=agent-2 bundle exec rails ...
```

Each agent gets full isolation. No locks, no coordination. When an agent's work is done:

```bash
rails db:branch:discard BRANCH=agent-0
```

## Rake tasks

```bash
rails db:branch:reset              # drop and recreate current branch schema
rails db:branch:discard             # drop current branch schema (or BRANCH=name)
rails db:branch:list                # list all branch schemas and their sizes
rails db:branch:diff                # show tables in the current branch schema
rails db:branch:prune               # drop stale schemas (KEEP=main,feature/x or auto-detect from git)
```

## Configuration

The adapter needs one thing: a branch name. Resolution order:

1. `PGBRANCH` environment variable
2. `git branch --show-current` (automatic fallback)

If neither is available, the adapter raises an error.

All standard PostgreSQL connection parameters work as normal (`host`, `port`, `username`, `password`, etc.).

**Do not set `schema_search_path` in database.yml** — it conflicts with the adapter's `search_path` management.

## Limitations

- **Rails + PostgreSQL only** — uses PostgreSQL schemas and `search_path`
- **Development and test only** — production should use the standard `postgresql` adapter
- **Non-ActiveRecord DDL** — raw SQL outside of migrations bypasses the shadow rule
- **Sequences on shadowed tables** — `rename_table` on a shadowed table with serial columns works, but the sequence keeps its original name
