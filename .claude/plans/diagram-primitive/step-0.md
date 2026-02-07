# Step 0: Schema and Migration

## Overview
Create the database schema and migration for the diagrams table.

## Context
Diagrams are immutable records (like decisions) with a mutable status field for lifecycle management. They follow the same patterns as insights/decisions with UUIDs, timestamps, and project association.

## Implementation

### 1. Create Schema Module

**File:** `lib/pop_stash/memory/diagram.ex`

```elixir
defmodule PopStash.Memory.Diagram do
  @moduledoc """
  Schema for architectural diagrams (immutable documentation).

  Diagrams store architectural knowledge in Mermaid format, providing
  compact, LLM-friendly representations of system architecture, flows,
  and relationships.

  ## Status Lifecycle
  - `draft` - Work in progress, not yet finalized
  - `active` - Current, accurate representation
  - `deprecated` - Outdated but preserved for history
  """

  use PopStash.Schema

  schema "diagrams" do
    field(:title, :string)
    field(:summary, :string)
    field(:content, :string)
    field(:diagram_type, :string)
    field(:status, :string)
    field(:files, {:array, :string}, default: [])
    field(:tags, {:array, :string}, default: [])
    field(:embedding, Pgvector.Ecto.Vector)

    belongs_to(:project, PopStash.Projects.Project)

    timestamps()
  end

  def valid_statuses, do: ~w(draft active deprecated)

  # Note: While diagrams are immutable by design (preserving historical
  # accuracy), the status field is an exception. Status represents our
  # current interpretation of the diagram (draft/active/deprecated), not
  # the diagram content itself. This allows lifecycle management without
  # losing history.
end
```

**Field Notes:**
- `title` - Preserves case for readability (no normalization)
- `summary` - Used for embeddings; describes what the diagram shows
- `content` - Raw mermaid syntax; keyword-searchable but not embedded
- `diagram_type` - Freeform hint (no validation to stay flexible as Mermaid evolves)
- `status` - Mutable for lifecycle management

### 2. Create Migration

**File:** `priv/repo/migrations/[timestamp]_create_diagrams.exs`

```elixir
defmodule PopStash.Repo.Migrations.CreateDiagrams do
  use Ecto.Migration

  def change do
    create table(:diagrams, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :summary, :text, null: false
      add :content, :text, null: false
      add :diagram_type, :string
      add :status, :string, null: false, default: "draft"
      add :files, {:array, :string}, default: []
      add :tags, {:array, :string}, default: []
      add :embedding, :vector, size: 384

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps()
    end

    create index(:diagrams, [:project_id])
    create index(:diagrams, [:project_id, :title, :status])
    create index(:diagrams, [:status])
    create index(:diagrams, [:inserted_at])
    create index(:diagrams, [:embedding], using: :ivfflat, opclass: :vector_cosine_ops)
  end
end
```

**Index Strategy:**
- Single column indexes for filtering
- Composite index `(project_id, title, status)` for common query pattern
- Vector index for semantic search

## Verification

```bash
# Run migration
mix ecto.migrate

# Verify in psql
psql pop_stash_dev -c "\d diagrams"

# Should show all columns and indexes
```

## Tests

**File:** `test/pop_stash/memory/diagram_test.exs`

```elixir
defmodule PopStash.Memory.DiagramTest do
  use PopStash.DataCase

  alias PopStash.Memory.Diagram

  describe "schema" do
    test "has correct fields" do
      fields = Diagram.__schema__(:fields)

      assert :id in fields
      assert :title in fields
      assert :summary in fields
      assert :content in fields
      assert :diagram_type in fields
      assert :status in fields
      assert :files in fields
      assert :tags in fields
      assert :embedding in fields
      assert :project_id in fields
      assert :inserted_at in fields
      assert :updated_at in fields
    end

    test "valid_statuses/0 returns expected statuses" do
      assert Diagram.valid_statuses() == ~w(draft active deprecated)
    end

    test "can build a diagram struct" do
      project = insert(:project)

      diagram = %Diagram{
        title: "Test",
        summary: "Test summary",
        content: "graph TD\n  A --> B",
        status: "draft",
        project_id: project.id
      }

      assert diagram.title == "Test"
      assert diagram.status == "draft"
      assert diagram.tags == []
      assert diagram.files == []
    end
  end
end
```

**Run tests:**
```bash
mix test test/pop_stash/memory/diagram_test.exs
```

## Dependencies
- Existing `PopStash.Schema` module
- Existing `projects` table
- pgvector extension already enabled
