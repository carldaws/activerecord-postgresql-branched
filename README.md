# activerecord-postgresql-branched

A Rails database adapter that gives each git branch its own Postgres schema. Migrations run in isolation. Nobody steps on anyone else's work.

## The problem

Two developers working simultaneously:

- `feature/payments` adds a `payments` table, alters `users`, adds indexes
- `feature/user-profiles` adds a `bio` column to `users`, a different migration

They share one dev database. Migrations fight. Everyone breaks everyone else.

This adapter makes branching the database as cheap as branching code.

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

test:
  adapter: postgresql_branched
  database: myapp_test
```

```bash
bundle install
```

## How it works

Every git branch gets a dedicated Postgres schema. On connection, the adapter reads the current branch, creates the schema if needed, and sets `search_path`:

```
git branch: feature/payments
schema:      branch_feature_payments
search_path: branch_feature_payments, public
```

Migrations land in the branch schema. Queries against untouched tables fall through to `public`. Nothing in `public` is ever modified except on the primary branch.

### The shadow rule

When a migration modifies a table that exists in `public` but not yet in the branch schema, the adapter copies it first:

```
migration: add_column :users, :bio, :string

1. CREATE TABLE branch_feature_payments.users (LIKE public.users INCLUDING ALL)
2. INSERT INTO branch_feature_payments.users SELECT * FROM public.users
3. ALTER TABLE users ADD COLUMN bio VARCHAR
```

Step 3 hits the branch copy via `search_path`. The public table is untouched.

### The primary branch

On the primary branch (default: `main`), the adapter stands aside entirely. Migrations land directly in `public`. This is how the canonical schema advances.

When `public` advances, all feature branches see the changes immediately via `search_path` fallthrough.

## Configuration

```yaml
development:
  adapter: postgresql_branched
  database: myapp_development
  primary_branch: main        # default, can be 'master', 'trunk', etc.
```

`primary_branch` is the only configuration option beyond standard Postgres connection parameters.

### Explicit branch override

For agents or CI, bypass git detection:

```yaml
development:
  adapter: postgresql_branched
  database: myapp_development
  branch_override: agent-0
```

Or via environment variable:

```bash
PGBRANCH=agent-0 rails db:migrate
```

## Rake tasks

```bash
rails db:branch:reset    # drop and recreate current branch schema
rails db:branch:discard  # drop current branch schema entirely
rails db:branch:list     # list all branch schemas and their sizes
rails db:branch:diff     # show objects in this branch vs public
rails db:branch:prune    # drop schemas for branches that no longer exist in git
```

### Rebasing

```bash
git fetch && git rebase origin/main
rails db:branch:reset
rails db:migrate
```

`db:branch:reset` drops the branch schema. `search_path` falls through to the updated `public`. Re-running `db:migrate` reapplies your branch's migrations on top of the new baseline.

### Discarding a branch

```bash
rails db:branch:discard
# or for a specific branch:
rails db:branch:discard BRANCH=feature/abandoned
```

### Pruning stale schemas

After agents finish or branches are deleted:

```bash
rails db:branch:prune
```

Compares branch schemas against `git branch --list` and drops any that no longer have a corresponding local branch.

## The merge story

The adapter does not merge. Git does.

1. Developer writes migrations on a feature branch
2. Adapter isolates them automatically
3. PR merged into `main`
4. Team pulls `main`, runs `db:migrate`
5. Adapter stands aside (primary branch), migrations land in `public`
6. `schema.rb` updated and committed
7. All active branch schemas see updated `public` via fallthrough

## schema.rb

`db:schema:dump` presents a unified view of the current branch:

- Branch-local tables are included without `branch_` prefix
- Shadowed tables show the branch version
- Public tables that the branch has not touched are included as normal
- No other branches' tables appear

The diff for a schema change looks exactly as it always has.

## Multiple databases

Rails multi-database setups work naturally:

```yaml
primary:
  adapter: postgresql_branched
  database: myapp_development

analytics:
  adapter: postgresql_branched
  database: myapp_analytics_development
```

## Limitations

- **Rails + Postgres only** -- the mechanism is Postgres schemas and `search_path`
- **Dev only** -- production and staging should use the standard `postgresql` adapter
- **No `schema_search_path` in database.yml** -- remove it when using this adapter, it will conflict
- **Non-ActiveRecord DDL** -- raw SQL executed outside of migrations bypasses the shadow rule
