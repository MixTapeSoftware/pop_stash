# Step 2: Search Integration

## Overview
Add diagram indexing to the async indexer and create Typesense search infrastructure for semantic and keyword search.

## Context
Diagrams follow the same async embedding pattern as insights/decisions. Title + summary are embedded for semantic search; content remains keyword-searchable.

## Implementation

### 1. Update Search Indexer

**File:** `lib/pop_stash/search/indexer.ex`

Add PubSub handlers after existing decision handlers:

```elixir
def handle_info({:diagram_created, diagram}, state) do
  index_async(diagram, &index_diagram/1)
  {:noreply, state}
end

def handle_info({:diagram_status_updated, diagram}, state) do
  # Re-index when status changes (affects search filtering)
  index_async(diagram, &index_diagram/1)
  {:noreply, state}
end

def handle_info({:diagram_deleted, diagram_id}, state) do
  Typesense.delete_document("diagrams", diagram_id)
  {:noreply, state}
end
```

Add indexing function after `index_decision/1`:

```elixir
defp index_diagram(diagram) do
  # Embed title + summary only (not mermaid content)
  # Content is still keyword-searchable but not semantically embedded
  text = "#{diagram.title} #{diagram.summary}"

  with {:ok, embedding} <- Embeddings.embed(text),
       :ok <- update_embedding(diagram, embedding),
       :ok <- Typesense.index_diagram(diagram, embedding) do
    :ok
  else
    {:error, reason} ->
      Logger.warning("Failed to index diagram #{diagram.id}: #{inspect(reason)}")
      :error
  end
end
```

### 2. Add Typesense Collection Schema

**File:** `lib/pop_stash/search/typesense.ex`

Add collection schema constant after existing schemas:

```elixir
@diagrams_schema %{
  name: "diagrams",
  fields: [
    %{name: "id", type: "string"},
    %{name: "project_id", type: "string", facet: true},
    %{name: "title", type: "string"},
    %{name: "summary", type: "string"},
    %{name: "content", type: "string"},  # Keyword-searchable
    %{name: "status", type: "string", facet: true},
    %{name: "diagram_type", type: "string", optional: true, facet: true},
    %{name: "embedding", type: "float[]", num_dim: 384},
    %{name: "created_at", type: "int64"}
  ]
}
```

Update `ensure_collections/0` to include diagrams:

```elixir
def ensure_collections do
  with :ok <- ensure_collection(@insights_schema),
       :ok <- ensure_collection(@decisions_schema),
       :ok <- ensure_collection(@diagrams_schema) do
    :ok
  else
    error -> error
  end
end
```

### 3. Add Indexing Function

Add after `index_decision/2`:

```elixir
def index_diagram(diagram, embedding) do
  document = %{
    id: diagram.id,
    project_id: diagram.project_id,
    title: diagram.title,
    summary: diagram.summary,
    content: diagram.content,
    status: diagram.status,
    diagram_type: diagram.diagram_type,
    embedding: embedding,
    created_at: DateTime.to_unix(diagram.inserted_at)
  }

  upsert_document("diagrams", document)
end
```

### 4. Add Search Function

Add after `search_decisions/3`:

```elixir
@doc """
Search diagrams by semantic similarity and keyword matching.

## Options
  * `:status` - Filter by status (default: "active")
  * `:limit` - Maximum results (default: 10)
"""
def search_diagrams(project_id, query, opts \\ []) do
  status_filter = Keyword.get(opts, :status, "active")
  limit = Keyword.get(opts, :limit, 10)

  filter_by = "project_id:=#{project_id} && status:=#{status_filter}"

  # Try embedding-based search
  case Embeddings.embed(query) do
    {:ok, query_embedding} when is_list(query_embedding) ->
      search_params = %{
        collection: "diagrams",
        q: query,
        query_by: "title,summary,content",
        filter_by: filter_by,
        vector_query: "embedding:(#{Enum.join(query_embedding, ",")})",
        limit: limit,
        per_page: limit
      }

      case search(search_params) do
        {:ok, %{"hits" => hits}} ->
          results =
            Enum.map(hits, fn hit ->
              doc = hit["document"]

              %{
                id: doc["id"],
                title: doc["title"],
                summary: doc["summary"],
                content: doc["content"],
                status: doc["status"],
                diagram_type: doc["diagram_type"]
              }
            end)

          {:ok, results}

        error ->
          error
      end

    _error ->
      # Fallback to keyword-only search if embedding fails
      search_params = %{
        collection: "diagrams",
        q: query,
        query_by: "title,summary,content",
        filter_by: filter_by,
        limit: limit,
        per_page: limit
      }

      case search(search_params) do
        {:ok, %{"hits" => hits}} ->
          results =
            Enum.map(hits, fn hit ->
              doc = hit["document"]

              %{
                id: doc["id"],
                title: doc["title"],
                summary: doc["summary"],
                content: doc["content"],
                status: doc["status"],
                diagram_type: doc["diagram_type"]
              }
            end)

          {:ok, results}

        error ->
          error
      end
  end
end
```

## Verification

```elixir
# In IEx
alias PopStash.Memory
alias PopStash.Search.Typesense

# Create a diagram and wait for indexing
{:ok, diagram} = Memory.create_diagram(
  "project-id",
  "Auth Flow",
  "graph TD\n  A[Login] --> B[Token]",
  summary: "Shows how users authenticate with JWT tokens"
)

# Wait a moment for async indexing
Process.sleep(1000)

# Search for it
{:ok, results} = Memory.search_diagrams("project-id", "authentication")
assert length(results) > 0
assert Enum.any?(results, fn d -> d.id == diagram.id end)

# Verify status filtering works
{:ok, active_only} = Memory.search_diagrams("project-id", "auth", status: "active")
# Should be empty since diagram is draft by default
assert active_only == []

# Update to active and search again
Memory.update_diagram_status(diagram.id, "active")
Process.sleep(500)
{:ok, active_results} = Memory.search_diagrams("project-id", "auth", status: "active")
assert length(active_results) > 0
```

## Tests

**File:** `test/pop_stash/search/indexer_test.exs` (extend existing)

Add diagram indexing tests:

```elixir
describe "diagram indexing" do
  test "indexes diagram on create" do
    project = insert(:project)

    # Subscribe to verify indexing happens
    {:ok, diagram} =
      Memory.create_diagram(
        project.id,
        "Test Diagram",
        "graph TD\n  A --> B",
        summary: "A test diagram for indexing"
      )

    # Give indexer time to process
    Process.sleep(100)

    # Verify it can be found via search
    {:ok, results} = Memory.search_diagrams(project.id, "test diagram")

    assert length(results) > 0
  end

  test "re-indexes diagram on status update" do
    project = insert(:project)

    {:ok, diagram} =
      Memory.create_diagram(project.id, "Test", "content", summary: "test", status: "draft")

    Process.sleep(100)

    # Update status
    {:ok, _updated} = Memory.update_diagram_status(diagram.id, "active")

    Process.sleep(100)

    # Should be findable with active status
    {:ok, results} = Memory.search_diagrams(project.id, "test", status: "active")

    assert length(results) > 0
  end

  test "removes diagram from index on delete" do
    project = insert(:project)

    {:ok, diagram} =
      Memory.create_diagram(project.id, "Test", "content", summary: "test")

    Process.sleep(100)

    # Delete it
    :ok = Memory.delete_diagram(diagram.id)

    Process.sleep(100)

    # Should not be found
    {:ok, results} = Memory.search_diagrams(project.id, "test")

    assert results == [] or not Enum.any?(results, &(&1.id == diagram.id))
  end
end
```

**File:** `test/pop_stash/search/typesense_test.exs` (extend existing)

```elixir
describe "diagram search" do
  setup do
    project = insert(:project)

    {:ok, diagram} =
      Memory.create_diagram(
        project.id,
        "Authentication Flow",
        "graph TD\n  A --> B",
        summary: "Shows JWT authentication flow",
        status: "active"
      )

    # Wait for indexing
    Process.sleep(200)

    %{project_id: project.id, diagram: diagram}
  end

  test "searches diagrams by title", %{project_id: project_id} do
    {:ok, results} = Typesense.search_diagrams(project_id, "authentication")

    assert length(results) > 0
    assert Enum.any?(results, &(&1.title =~ "Authentication"))
  end

  test "searches diagrams by summary", %{project_id: project_id} do
    {:ok, results} = Typesense.search_diagrams(project_id, "JWT")

    assert length(results) > 0
  end

  test "filters by status", %{project_id: project_id} do
    # Should find active diagram
    {:ok, active_results} = Typesense.search_diagrams(project_id, "auth", status: "active")

    assert length(active_results) > 0

    # Should not find draft diagrams when filtering for active
    {:ok, draft_results} = Typesense.search_diagrams(project_id, "auth", status: "draft")

    assert draft_results == [] or not Enum.any?(draft_results, &(&1.status == "active"))
  end

  test "respects limit option", %{project_id: project_id} do
    # Create multiple diagrams
    for i <- 1..5 do
      Memory.create_diagram(
        project_id,
        "Diagram #{i}",
        "content",
        summary: "test diagram",
        status: "active"
      )
    end

    Process.sleep(500)

    {:ok, results} = Typesense.search_diagrams(project_id, "diagram", limit: 3)

    assert length(results) <= 3
  end
end
```

**Run tests:**
```bash
# These tests require Typesense to be running
mix test test/pop_stash/search/indexer_test.exs
mix test test/pop_stash/search/typesense_test.exs
```

**Note:** These are integration tests that require Typesense. Consider tagging them with `@tag :integration` and running separately if needed.

## Dependencies
- Step 0 completed (schema exists)
- Step 1 completed (context functions exist)
- Existing Typesense infrastructure
- Existing Embeddings module
