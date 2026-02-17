# Step 1: Add org_id to Content Tables

## Overview
Add org_id foreign key to all content tables (projects, insights, decisions, search_logs), migrate existing data to default organization, add NOT NULL constraints.

## Context
With organizations table created, we now add foreign keys to isolate data by org. This step handles both schema changes and data migration for existing records.

## Implementation

### 1. Add org_id to Projects

**Migration**: `priv/repo/migrations/TIMESTAMP_add_org_id_to_projects.exs`

```elixir
defmodule PopStash.Repo.Migrations.AddOrgIdToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :org_id, references(:organizations, type: :binary_id, on_delete: :delete_all)
    end

    create index(:projects, [:org_id])
  end
end
```

### 2. Add org_id to Insights

**Migration**: `priv/repo/migrations/TIMESTAMP_add_org_id_to_insights.exs`

```elixir
defmodule PopStash.Repo.Migrations.AddOrgIdToInsights do
  use Ecto.Migration

  def change do
    alter table(:insights) do
      add :org_id, references(:organizations, type: :binary_id, on_delete: :delete_all)
    end

    create index(:insights, [:org_id])
    create index(:insights, [:org_id, :project_id])
    create index(:insights, [:org_id, :updated_at])
  end
end
```

### 3. Add org_id to Decisions

**Migration**: `priv/repo/migrations/TIMESTAMP_add_org_id_to_decisions.exs`

```elixir
defmodule PopStash.Repo.Migrations.AddOrgIdToDecisions do
  use Ecto.Migration

  def change do
    alter table(:decisions) do
      add :org_id, references(:organizations, type: :binary_id, on_delete: :delete_all)
    end

    create index(:decisions, [:org_id])
    create index(:decisions, [:org_id, :project_id])
    create index(:decisions, [:org_id, :inserted_at])
  end
end
```

### 4. Add org_id to SearchLogs

**Migration**: `priv/repo/migrations/TIMESTAMP_add_org_id_to_search_logs.exs`

```elixir
defmodule PopStash.Repo.Migrations.AddOrgIdToSearchLogs do
  use Ecto.Migration

  def change do
    alter table(:search_logs) do
      add :org_id, references(:organizations, type: :binary_id, on_delete: :delete_all)
    end

    create index(:search_logs, [:org_id])
    create index(:search_logs, [:org_id, :project_id])
  end
end
```

### 5. Migrate Existing Data

**Migration**: `priv/repo/migrations/TIMESTAMP_migrate_to_default_org.exs`

```elixir
defmodule PopStash.Repo.Migrations.MigrateToDefaultOrg do
  use Ecto.Migration

  def up do
    # Create default organization
    execute """
    INSERT INTO organizations (id, name, slug, settings, inserted_at, updated_at)
    VALUES (
      gen_random_uuid(),
      'Default Organization',
      'default',
      '{}',
      NOW(),
      NOW()
    )
    """

    # Assign all projects to default org
    execute """
    UPDATE projects
    SET org_id = (SELECT id FROM organizations WHERE slug = 'default')
    WHERE org_id IS NULL
    """

    # Propagate org_id from projects to insights
    execute """
    UPDATE insights i
    SET org_id = p.org_id
    FROM projects p
    WHERE i.project_id = p.id AND i.org_id IS NULL
    """

    # Propagate org_id from projects to decisions
    execute """
    UPDATE decisions d
    SET org_id = p.org_id
    FROM projects p
    WHERE d.project_id = p.id AND d.org_id IS NULL
    """

    # Propagate org_id from projects to search_logs
    execute """
    UPDATE search_logs s
    SET org_id = p.org_id
    FROM projects p
    WHERE s.project_id = p.id AND s.org_id IS NULL
    """
  end

  def down do
    execute "UPDATE projects SET org_id = NULL"
    execute "UPDATE insights SET org_id = NULL"
    execute "UPDATE decisions SET org_id = NULL"
    execute "UPDATE search_logs SET org_id = NULL"
    execute "DELETE FROM organizations WHERE slug = 'default'"
  end
end
```

### 6. Add NOT NULL Constraints

**Migration**: `priv/repo/migrations/TIMESTAMP_make_org_id_not_null.exs`

```elixir
defmodule PopStash.Repo.Migrations.MakeOrgIdNotNull do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      modify :org_id, :binary_id, null: false
    end

    alter table(:insights) do
      modify :org_id, :binary_id, null: false
    end

    alter table(:decisions) do
      modify :org_id, :binary_id, null: false
    end

    alter table(:search_logs) do
      modify :org_id, :binary_id, null: false
    end
  end
end
```

### 7. Update Schema Files

Update all schema modules to include org_id relationship:

**lib/pop_stash/projects/project.ex**:
```elixir
belongs_to :organization, PopStash.Organizations.Organization, foreign_key: :org_id
```

**lib/pop_stash/memory/insight.ex**:
```elixir
belongs_to :organization, PopStash.Organizations.Organization, foreign_key: :org_id
```

**lib/pop_stash/memory/decision.ex**:
```elixir
belongs_to :organization, PopStash.Organizations.Organization, foreign_key: :org_id
```

**lib/pop_stash/memory/search_log.ex**:
```elixir
belongs_to :organization, PopStash.Organizations.Organization, foreign_key: :org_id
```

## Verification

```bash
# Run all migrations
mix ecto.migrate

# Verify org_id columns exist
psql pop_stash_dev -c "\d projects"
psql pop_stash_dev -c "\d insights"
psql pop_stash_dev -c "\d decisions"
psql pop_stash_dev_c "\d search_logs"

# Verify default org created
psql pop_stash_dev -c "SELECT * FROM organizations WHERE slug = 'default';"

# Verify all existing data has org_id
psql pop_stash_dev -c "SELECT COUNT(*) FROM projects WHERE org_id IS NULL;" # Should be 0
psql pop_stash_dev -c "SELECT COUNT(*) FROM insights WHERE org_id IS NULL;" # Should be 0
```

## Tests

**File**: `test/pop_stash/projects/project_test.exs`

```elixir
test "schema has org_id relationship" do
  assert :org_id in Project.__schema__(:fields)
  assert {:organization, _} = Project.__schema__(:association, :organization)
end
```

Repeat for Insight, Decision, SearchLog schemas.

## Dependencies
- Step 0 completed (organizations table exists)
- Existing projects, insights, decisions, search_logs tables

## Next Step
Step 2 will implement passwordless authentication using the users table created in Step 0.
