# Step 0: Database Foundation + Schema Modules

## Objective

Create all new database tables (organizations, users, users_tokens, org_members) and add org_id columns to existing content tables (projects, insights, decisions, search_logs). Create corresponding Ecto schema modules. Migrate existing data to a default organization.

This step is pure data layer -- no application logic, no context functions, no auth flows.

## Prerequisites

- PostgreSQL running with pgvector extension
- Existing tables: projects, insights, decisions, search_logs

## Implementation

### 1. Run phx.gen.auth (then modify output)

```bash
mix phx.gen.auth Accounts User users --binary-id --no-live
```

This generates users table, users_tokens table, User schema, UserToken schema, Accounts context, UserAuth plug, and session controller. We will modify the output in Step 2 to remove passwords.

**Important**: Run the generator first, then modify the generated migration to remove `hashed_password`. The `--no-live` flag prevents generating LiveViews (we create our own in Step 2).

### 2. Create organizations table

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

### 3. Modify generated users migration

Edit the phx.gen.auth-generated migration to remove `hashed_password`:

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

### 4. Add selected_org_id to users

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

### 5. Create org_members table

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

### 6. Add org_id to content tables + data migration

**Migration**: `priv/repo/migrations/TIMESTAMP_add_org_id_to_content_tables.exs`

Single migration that adds nullable org_id, creates default org, migrates data, then adds NOT NULL:

```elixir
defmodule PopStash.Repo.Migrations.AddOrgIdToContentTables do
  use Ecto.Migration

  def up do
    # Add nullable org_id to all content tables
    for table <- [:projects, :insights, :decisions, :search_logs] do
      alter table(table) do
        add :org_id, references(:organizations, type: :binary_id, on_delete: :delete_all)
      end

      create index(table, [:org_id])
    end

    # Composite indexes for common query patterns
    create index(:insights, [:org_id, :project_id])
    create index(:decisions, [:org_id, :project_id])
    create index(:search_logs, [:org_id, :project_id])

    flush()

    # Create default organization for existing data
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

    # Assign all content to default org
    for table <- [:projects, :insights, :decisions, :search_logs] do
      execute """
      UPDATE #{table}
      SET org_id = (SELECT id FROM organizations WHERE slug = 'default')
      WHERE org_id IS NULL
      """
    end

    # Add NOT NULL constraints
    for table <- [:projects, :insights, :decisions, :search_logs] do
      alter table(table) do
        modify :org_id, :binary_id, null: false
      end
    end
  end

  def down do
    for table <- [:projects, :insights, :decisions, :search_logs] do
      alter table(table) do
        remove :org_id
      end
    end

    execute "DELETE FROM organizations WHERE slug = 'default'"
  end
end
```

### 7. Create schema modules

**File**: `/workspace/lib/pop_stash/organizations/organization.ex`

```elixir
defmodule PopStash.Organizations.Organization do
  use PopStash.Schema

  schema "organizations" do
    field :name, :string
    field :slug, :string
    field :settings, :map, default: %{}

    timestamps()
  end

  @doc "Generates a URL-safe slug from an organization name."
  def generate_slug(name) when is_binary(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/\s+/, "-")
    |> String.trim("-")
    |> String.slice(0, 100)
  end
end
```

**File**: `/workspace/lib/pop_stash/organizations/org_member.ex`

```elixir
defmodule PopStash.Organizations.OrgMember do
  use PopStash.Schema

  alias PopStash.Accounts.User
  alias PopStash.Organizations.Organization

  @roles ~w(owner member)

  schema "org_members" do
    field :role, :string, default: "member"

    belongs_to :organization, Organization, foreign_key: :org_id
    belongs_to :user, User

    timestamps()
  end

  def roles, do: @roles
end
```

### 8. Update existing schema files

Add `belongs_to :organization` to each content schema. Do NOT remove any existing fields or associations.

**File**: `/workspace/lib/pop_stash/projects/project.ex` -- add after `field :tags`:

```elixir
belongs_to :organization, PopStash.Organizations.Organization, foreign_key: :org_id
```

**File**: `/workspace/lib/pop_stash/memory/insight.ex` -- add after `field :embedding`:

```elixir
belongs_to :organization, PopStash.Organizations.Organization, foreign_key: :org_id
```

**File**: `/workspace/lib/pop_stash/memory/decision.ex` -- add after `field :embedding`:

```elixir
belongs_to :organization, PopStash.Organizations.Organization, foreign_key: :org_id
```

**File**: `/workspace/lib/pop_stash/memory/search_log.ex` -- add after `belongs_to :project`:

```elixir
belongs_to :organization, PopStash.Organizations.Organization, foreign_key: :org_id
```

## Verification

```bash
mix ecto.migrate

# Verify tables exist
psql pop_stash_dev -c "\dt"
# Should show: organizations, users, users_tokens, org_members (plus existing tables)

# Verify org_id columns
psql pop_stash_dev -c "SELECT COUNT(*) FROM projects WHERE org_id IS NULL;"
# Should be 0

# Verify default org
psql pop_stash_dev -c "SELECT * FROM organizations WHERE slug = 'default';"

# Compile check
mix compile --warnings-as-errors
```

## Tests

At this stage, tests verify schema definitions only. No context tests yet.

**File**: `test/pop_stash/organizations/organization_test.exs`

```elixir
defmodule PopStash.Organizations.OrganizationTest do
  use PopStash.DataCase, async: true

  alias PopStash.Organizations.Organization

  describe "schema" do
    test "has expected fields" do
      fields = Organization.__schema__(:fields)
      assert :name in fields
      assert :slug in fields
      assert :settings in fields
    end
  end

  describe "generate_slug/1" do
    test "converts name to lowercase hyphenated slug" do
      assert Organization.generate_slug("My Org Name") == "my-org-name"
    end

    test "removes special characters" do
      assert Organization.generate_slug("Acme Corp!") == "acme-corp"
    end

    test "trims leading/trailing hyphens" do
      assert Organization.generate_slug("  spaces  ") == "spaces"
    end

    test "truncates to 100 characters" do
      long_name = String.duplicate("a", 200)
      assert String.length(Organization.generate_slug(long_name)) <= 100
    end
  end
end
```

**File**: `test/pop_stash/schema_org_id_test.exs`

```elixir
defmodule PopStash.SchemaOrgIdTest do
  use PopStash.DataCase, async: true

  alias PopStash.Memory.Decision
  alias PopStash.Memory.Insight
  alias PopStash.Memory.SearchLog
  alias PopStash.Projects.Project

  test "Project schema has org_id field and organization association" do
    assert :org_id in Project.__schema__(:fields)
    assert %Ecto.Association.BelongsTo{} = Project.__schema__(:association, :organization)
  end

  test "Insight schema has org_id field and organization association" do
    assert :org_id in Insight.__schema__(:fields)
    assert %Ecto.Association.BelongsTo{} = Insight.__schema__(:association, :organization)
  end

  test "Decision schema has org_id field and organization association" do
    assert :org_id in Decision.__schema__(:fields)
    assert %Ecto.Association.BelongsTo{} = Decision.__schema__(:association, :organization)
  end

  test "SearchLog schema has org_id field and organization association" do
    assert :org_id in SearchLog.__schema__(:fields)
    assert %Ecto.Association.BelongsTo{} = SearchLog.__schema__(:association, :organization)
  end
end
```

## Incremental Test Fixes

After adding org_id columns and the organization association to content schemas, existing tests that insert content records directly may fail due to NOT NULL constraints on org_id. Fix these in this step by:

1. Creating a minimal test helper that inserts a default org and returns its ID
2. Updating any existing test setup blocks that directly insert into content tables to include `org_id`
3. Ensuring `mix test` passes at the end of this step (before moving to Step 1)

Note: `Repo.prepare_query` does not exist yet in this step, so read queries won't enforce org_id. The NOT NULL constraints on org_id columns ARE enforced though, so any test that inserts content without org_id will fail.

## Important Notes

- The phx.gen.auth output needs to compile for this step. The generated Accounts context, User schema, UserToken schema, and UserAuth plug should all compile, even though we will modify them heavily in Step 2.
- All tests must pass at the end of this step.

## Dependencies

None -- this is the first step.
