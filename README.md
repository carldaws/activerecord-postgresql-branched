# activerecord-postgresql-branched

Database isolation for parallel development. Each git branch (or agent) gets its own Postgres schema. Migrations run in isolation. Nobody steps on anyone else's work.

Built for teams running multiple AI coding agents in parallel, each on its own worktree, all sharing one database.

## The problem

You have three agents working simultaneously in three worktrees:

- `agent-0` adds a `payments` table and alters `users`
- `agent-1` adds a `bio` column to `users`
- `agent-2` drops a legacy table and adds indexes

They share one dev database. Every migration collides. Every agent breaks every other agent. You spend more time untangling the database than reviewing the code.

This adapter makes branching the database as cheap as branching the code.

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

That's it. No Postgres extensions, no environment variables, no initializers.

## How it works

On connection, the adapter reads the current git branch, creates a dedicated Postgres schema for it, and sets `search_path`:

```
git branch: feature/payments
schema:      branch_feature_payments
search_path: branch_feature_payments, public
```

New tables go into the branch schema. Queries against existing tables fall through to `public` via standard Postgres name resolution.

When a migration modifies a table that exists in `public`, the adapter shadows it first -- copies the table and its data into the branch schema, then applies the DDL to the copy. The public table is never touched.

On the primary branch (`main` by default), the adapter stands aside entirely. Migrations land in `public` as normal. When `public` advances, every branch sees the changes immediately via `search_path` fallthrough.

## Agentic workflows

Give each agent its own branch identity:

```yaml
# config/database.yml
development:
  adapter: postgresql_branched
  database: myapp_development
  branch_override: <%= ENV.fetch("AGENT_BRANCH", nil) %>
```

```bash
# Launch agents with isolated schemas
AGENT_BRANCH=agent-0 bundle exec rails ...
AGENT_BRANCH=agent-1 bundle exec rails ...
AGENT_BRANCH=agent-2 bundle exec rails ...
```

Or in a worktree-per-agent setup, each worktree is on its own git branch and the adapter picks it up automatically. No configuration needed beyond the adapter name.

### Cleanup

After agents finish:

```bash
rails db:branch:prune
```

Compares branch schemas against `git branch --list` and drops any that no longer have a corresponding local branch. One command, all stale schemas gone.

For specific branches:

```bash
rails db:branch:discard BRANCH=agent-0
```

## Rake tasks

```bash
rails db:branch:reset    # drop and recreate current branch schema
rails db:branch:discard  # drop current branch schema (or BRANCH=name)
rails db:branch:list     # list all branch schemas and their sizes
rails db:branch:diff     # show objects in this branch vs public
rails db:branch:prune    # drop schemas for branches no longer in git
```

## Configuration

```yaml
development:
  adapter: postgresql_branched
  database: myapp_development
  primary_branch: main        # default, can be 'master', 'trunk', etc.
  branch_override: agent-0    # bypass git, set branch explicitly
```

The `PGBRANCH` or `BRANCH` environment variables also work for explicit branch selection.

## Rebasing

```bash
git fetch && git rebase origin/main
rails db:branch:reset
rails db:migrate
```

`db:branch:reset` drops the branch schema. `search_path` falls through to the updated `public`. Re-running `db:migrate` reapplies your branch's migrations on top of the new baseline.

## The merge story

The adapter does not merge. Git does.

1. Agent writes migrations on its branch
2. Adapter isolates them in a branch schema automatically
3. PR merged into `main`
4. Team pulls `main`, runs `db:migrate`
5. Adapter stands aside (primary branch), migrations land in `public`
6. `schema.rb` updated and committed
7. All active branch schemas see updated `public` via fallthrough

## schema.rb

`db:schema:dump` presents a unified view of the current branch as if everything lived in `public`:

- Branch-local tables appear without the `branch_` prefix
- Shadowed tables show the branch version
- Public tables the branch hasn't touched are included as normal
- No schema references, no branch artifacts

The diff for a schema change looks exactly as it always has.

## Limitations

- **Rails + Postgres only** -- uses Postgres schemas and `search_path`
- **Dev only** -- production and staging should use the standard `postgresql` adapter
- **No `schema_search_path` in database.yml** -- it will conflict with the adapter
- **Non-ActiveRecord DDL** -- raw SQL outside of migrations bypasses the shadow rule
- **Sequences on shadowed tables** -- `rename_table` on a shadowed table with serial columns works, but the sequence keeps its original name
