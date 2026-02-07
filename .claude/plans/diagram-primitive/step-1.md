# Step 1: Context Module (CRUD Operations)

## Overview
Add diagram functions to the `PopStash.Memory` context module, following the same patterns as insights and decisions.

## Context
All changesets are inline in the context (not in schema). Functions broadcast PubSub events for async indexing. Status is the only mutable field on otherwise immutable records.

## Implementation

### Add to Memory Context

**File:** `lib/pop_stash/memory.ex`

Add after the existing decision functions:

```elixir
## Diagrams

@doc """
Creates a diagram.

## Options
  * `:summary` - Brief description for search (required)
  * `:diagram_type` - Type hint for rendering (optional) (provide examples for the options documentation)
  * `:status` - "draft", "active", or "deprecated" (default: "draft")
  * `:files` - Related file paths
  * `:tags` - Categorization tags
"""
def create_diagram(project_id, title, content, opts \\ []) do
  %Diagram{}
  |> cast(
    %{
      project_id: project_id,
      title: title,
      content: content,
      summary: Keyword.fetch!(opts, :summary),
      diagram_type: Keyword.get(opts, :diagram_type),
      status: Keyword.get(opts, :status, "draft"),
      files: Keyword.get(opts, :files, []),
      tags: Keyword.get(opts, :tags, [])
    },
    [:project_id, :title, :content, :summary, :diagram_type, :status, :files, :tags]
  )
  |> validate_required([:project_id, :title, :content, :summary])
  |> validate_length(:title, min: 1, max: 255)
  |> validate_inclusion(:status, Diagram.valid_statuses())
  |> foreign_key_constraint(:project_id)
  |> Repo.insert()
  |> tap_ok(&broadcast(:diagram_created, &1))
end

@doc """
Retrieves a diagram by ID.
"""
def get_diagram(diagram_id) when is_binary(diagram_id) do
  Diagram
  |> Repo.get(diagram_id)
  |> wrap_result()
end

@doc """
Get all diagrams for a title.
Returns most recent first.
"""
def get_diagrams_by_title(project_id, title) when is_binary(project_id) and is_binary(title) do
  Diagram
  |> where([d], d.project_id == ^project_id and d.title == ^title)
  |> order_by(desc: :inserted_at)
  |> Repo.all()
end

@doc """
Get the most recent active diagram for a title.
Useful for finding current version.
"""
def get_active_diagram_by_title(project_id, title) do
  Diagram
  |> where([d], d.project_id == ^project_id)
  |> where([d], d.title == ^title)
  |> where([d], d.status == "active")
  |> order_by(desc: :inserted_at)
  |> limit(1)
  |> Repo.one()
  |> wrap_result()
end

@doc """
Lists diagrams for a project.

## Options
  * `:limit` - Maximum number of diagrams to return (default: 50)
  * `:since` - Only return diagrams after this datetime
  * `:status` - Filter by status
"""
def list_diagrams(project_id, opts \\ []) when is_binary(project_id) do
  limit = Keyword.get(opts, :limit, 50)
  since = Keyword.get(opts, :since)
  status = Keyword.get(opts, :status)

  Diagram
  |> where([d], d.project_id == ^project_id)
  |> maybe_filter_since(since)
  |> maybe_filter_status(status)
  |> order_by(desc: :inserted_at)
  |> limit(^limit)
  |> Repo.all()
end

defp maybe_filter_status(query, nil), do: query

defp maybe_filter_status(query, status) do
  where(query, [d], d.status == ^status)
end

@doc """
Lists all unique diagram titles for a project.
Useful for discovering what diagrams exist.
"""
def list_diagram_titles(project_id) when is_binary(project_id) do
  Diagram
  |> where([d], d.project_id == ^project_id)
  |> select([d], d.title)
  |> distinct(true)
  |> order_by(asc: :title)
  |> Repo.all()
end

@doc """
Updates a diagram's status.
This is the only mutable field on otherwise immutable diagrams.
"""
def update_diagram_status(diagram_id, new_status) when is_binary(diagram_id) do
  case Repo.get(Diagram, diagram_id) do
    nil ->
      {:error, :not_found}

    diagram ->
      diagram
      |> cast(%{status: new_status}, [:status])
      |> validate_required([:status])
      |> validate_inclusion(:status, Diagram.valid_statuses())
      |> Repo.update()
      |> tap_ok(&broadcast(:diagram_status_updated, &1))
  end
end

@doc """
Deletes a diagram by ID.
For admin use only - diagrams are generally immutable.
"""
def delete_diagram(diagram_id) when is_binary(diagram_id) do
  case Repo.get(Diagram, diagram_id) do
    nil ->
      {:error, :not_found}

    diagram ->
      case Repo.delete(diagram) do
        {:ok, _} ->
          broadcast(:diagram_deleted, diagram.id)
          :ok

        error ->
          error
      end
  end
end

@doc """
Search diagrams by semantic similarity.
Returns ranked list of matching diagrams.
"""
def search_diagrams(project_id, query, opts \\ []) do
  Typesense.search_diagrams(project_id, query, opts)
end
```

**Don't forget to add the alias at the top:**

```elixir
alias PopStash.Memory.Diagram
```

## Verification

```elixir
# In IEx
alias PopStash.Memory

# Create a test diagram
{:ok, diagram} = Memory.create_diagram(
  "project-id-here",
  "Test Diagram",
  """
  graph TD
    A[Start] --> B[End]
  """,
  summary: "A simple test diagram"
)

# Verify it was created
{:ok, fetched} = Memory.get_diagram(diagram.id)
assert fetched.title == "Test Diagram"
assert fetched.status == "draft"

# Update status
{:ok, updated} = Memory.update_diagram_status(diagram.id, "active")
assert updated.status == "active"

# List diagrams
diagrams = Memory.list_diagrams("project-id-here")
assert length(diagrams) > 0

# Clean up
Memory.delete_diagram(diagram.id)
```

## Tests

**File:** `test/pop_stash/memory_test.exs` (extend existing file)

Add this section after existing decision/insight tests:

```elixir
describe "diagrams" do
  setup do
    project = insert(:project)
    %{project_id: project.id}
  end

  test "create_diagram/3 creates diagram with required fields", %{project_id: project_id} do
    {:ok, diagram} =
      Memory.create_diagram(
        project_id,
        "Auth Flow",
        "graph TD\n  A --> B",
        summary: "Shows authentication"
      )

    assert diagram.title == "Auth Flow"
    assert diagram.summary == "Shows authentication"
    assert diagram.status == "draft"
    assert diagram.project_id == project_id
  end

  test "create_diagram/3 validates required fields", %{project_id: project_id} do
    {:error, changeset} = Memory.create_diagram(project_id, "", "content", summary: "test")
    assert %{title: ["can't be blank"]} = errors_on(changeset)
  end

  test "create_diagram/3 validates status", %{project_id: project_id} do
    {:error, changeset} =
      Memory.create_diagram(project_id, "Test", "content",
        summary: "test",
        status: "invalid"
      )

    assert %{status: ["is invalid"]} = errors_on(changeset)
  end

  test "create_diagram/3 broadcasts event", %{project_id: project_id} do
    Phoenix.PubSub.subscribe(PopStash.PubSub, "memory:events")

    {:ok, diagram} = Memory.create_diagram(project_id, "Test", "content", summary: "test")

    assert_received {:diagram_created, ^diagram}
  end

  test "get_diagram/1 returns diagram by id", %{project_id: project_id} do
    {:ok, diagram} = Memory.create_diagram(project_id, "Test", "content", summary: "test")

    assert {:ok, fetched} = Memory.get_diagram(diagram.id)
    assert fetched.id == diagram.id
  end

  test "get_diagram/1 returns error for invalid id" do
    assert {:error, :not_found} = Memory.get_diagram(Ecto.UUID.generate())
  end

  test "get_diagrams_by_title/2 returns all diagrams with title", %{project_id: project_id} do
    {:ok, d1} = Memory.create_diagram(project_id, "Test", "v1", summary: "v1")
    {:ok, d2} = Memory.create_diagram(project_id, "Test", "v2", summary: "v2")
    {:ok, _d3} = Memory.create_diagram(project_id, "Other", "v1", summary: "v1")

    diagrams = Memory.get_diagrams_by_title(project_id, "Test")

    assert length(diagrams) == 2
    assert d1.id in Enum.map(diagrams, & &1.id)
    assert d2.id in Enum.map(diagrams, & &1.id)
  end

  test "get_active_diagram_by_title/2 returns only active", %{project_id: project_id} do
    {:ok, _draft} = Memory.create_diagram(project_id, "Test", "draft", summary: "draft")

    {:ok, active} =
      Memory.create_diagram(project_id, "Test", "active",
        summary: "active",
        status: "active"
      )

    assert {:ok, found} = Memory.get_active_diagram_by_title(project_id, "Test")
    assert found.id == active.id
  end

  test "list_diagrams/2 returns diagrams for project", %{project_id: project_id} do
    {:ok, d1} = Memory.create_diagram(project_id, "D1", "c1", summary: "s1")
    {:ok, d2} = Memory.create_diagram(project_id, "D2", "c2", summary: "s2")

    diagrams = Memory.list_diagrams(project_id)

    assert length(diagrams) == 2
  end

  test "list_diagrams/2 filters by status", %{project_id: project_id} do
    {:ok, _draft} = Memory.create_diagram(project_id, "Draft", "c", summary: "s")

    {:ok, active} =
      Memory.create_diagram(project_id, "Active", "c", summary: "s", status: "active")

    diagrams = Memory.list_diagrams(project_id, status: "active")

    assert length(diagrams) == 1
    assert hd(diagrams).id == active.id
  end

  test "update_diagram_status/2 updates status", %{project_id: project_id} do
    {:ok, diagram} = Memory.create_diagram(project_id, "Test", "c", summary: "s")

    assert {:ok, updated} = Memory.update_diagram_status(diagram.id, "active")
    assert updated.status == "active"
  end

  test "update_diagram_status/2 validates status", %{project_id: project_id} do
    {:ok, diagram} = Memory.create_diagram(project_id, "Test", "c", summary: "s")

    assert {:error, changeset} = Memory.update_diagram_status(diagram.id, "invalid")
    assert %{status: ["is invalid"]} = errors_on(changeset)
  end

  test "update_diagram_status/2 broadcasts event", %{project_id: project_id} do
    {:ok, diagram} = Memory.create_diagram(project_id, "Test", "c", summary: "s")

    Phoenix.PubSub.subscribe(PopStash.PubSub, "memory:events")

    {:ok, updated} = Memory.update_diagram_status(diagram.id, "active")

    assert_received {:diagram_status_updated, ^updated}
  end

  test "delete_diagram/1 deletes diagram", %{project_id: project_id} do
    {:ok, diagram} = Memory.create_diagram(project_id, "Test", "c", summary: "s")

    assert :ok = Memory.delete_diagram(diagram.id)
    assert {:error, :not_found} = Memory.get_diagram(diagram.id)
  end

  test "delete_diagram/1 broadcasts event", %{project_id: project_id} do
    {:ok, diagram} = Memory.create_diagram(project_id, "Test", "c", summary: "s")

    Phoenix.PubSub.subscribe(PopStash.PubSub, "memory:events")

    Memory.delete_diagram(diagram.id)

    assert_received {:diagram_deleted, diagram_id}
    assert diagram_id == diagram.id
  end
end
```

**Run tests:**
```bash
mix test test/pop_stash/memory_test.exs
```

## Dependencies
- Step 0 completed (schema exists)
- Existing `maybe_filter_since/2` helper (already in Memory module)
- Existing `wrap_result/1` and `tap_ok/2` helpers
