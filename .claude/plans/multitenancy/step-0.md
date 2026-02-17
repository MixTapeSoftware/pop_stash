# Step 0: Database Foundation

## Overview
Create core database tables for multi-tenancy: organizations, users, org_members. Run mix phx.gen.auth and modify for passwordless auth preparation.

## Context
This step establishes the foundational data model without touching application logic. Organizations become the top-level tenant boundary, users can belong to multiple orgs via org_members join table.

## Implementation

### 1. Create Organizations Table

**Migration**: `priv/repo/migrations/TIMESTAMP_create_organizations.exs`

```elixir
defmodule PopStash.Repo.Migrations.CreateOrganizations do
  use Ecto.Migration

  def change do
    create table(:organizations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :slug, :string, null: false
      add :settings, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:organizations, [:slug])
    create index(:organizations, [:name])
  end
end
```

### 2. Run phx.gen.auth

```bash
mix phx.gen.auth Accounts User users
```

This generates:
- `users` table migration
- `users_tokens` table migration
- User schema
- UserToken schema
- Accounts context
- UserAuth plug
- Session controller
- Registration/Login LiveViews

### 3. Modify Users Migration

**Edit**: `priv/repo/migrations/TIMESTAMP_create_users.exs`

Remove `hashed_password` field:

```elixir
defmodule PopStash.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS citext", ""

    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :citext, null: false
      add :confirmed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:users, [:email])
  end
end
```

### 4. Add selected_org_id to Users

**Migration**: `priv/repo/migrations/TIMESTAMP_add_selected_org_to_users.exs`

```elixir
defmodule PopStash.Repo.Migrations.AddSelectedOrgToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :selected_org_id, references(:organizations, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:users, [:selected_org_id])
  end
end
```

### 5. Create OrgMembers Table

**Migration**: `priv/repo/migrations/TIMESTAMP_create_org_members.exs`

```elixir
defmodule PopStash.Repo.Migrations.CreateOrgMembers do
  use Ecto.Migration

  def change do
    create table(:org_members, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :org_id, references(:organizations, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :role, :string, null: false, default: "member"

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:org_members, [:org_id, :user_id])
    create index(:org_members, [:user_id])
    create index(:org_members, [:org_id])
  end
end
```

## Verification

```bash
# Run migrations
mix ecto.migrate

# Verify tables exist
psql pop_stash_dev -c "\dt"

# Should show: organizations, users, users_tokens, org_members

# Verify indexes
psql pop_stash_dev -c "\d organizations"
psql pop_stash_dev -c "\d users"
psql pop_stash_dev -c "\d org_members"
```

## Tests

No tests needed - this is pure database setup. Verification happens via successful migration.

## Dependencies
- PostgreSQL running
- UUID extension enabled (from PopStash.Schema)
- citext extension (created by phx.gen.auth)

## Next Step
Step 1 will add org_id foreign keys to content tables (projects, insights, decisions, search_logs).
