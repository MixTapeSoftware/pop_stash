# Add Diagrams as First-Class Memory Primitive

## Overview

Add diagrams (Mermaid-based architectural visualizations) as a first-class primitive alongside insights and decisions. Diagrams will store architectural context in a compact, LLM-friendly format with full lifecycle management (draft → active → deprecated).

## Motivation

Architectural knowledge is currently stored in prose (insights/decisions), but diagrams offer:
- **Compact representation** - Complex flows compressed into structured text
- **LLM-friendly** - Mermaid syntax is easier for agents to parse than prose
- **Rigor** - Diagrams enforce explicitness; eliminate hand-waving
- **Lifecycle management** - Mark outdated diagrams as deprecated rather than deleting
- **Searchability** - Semantic search via summary + keyword search on content

## Design Philosophy

Follow existing patterns from decisions and insights:
- Simple schema with standard fields (title, content, tags, files)
- Immutable by design (like decisions) - new versions create new records
- PubSub broadcasts for real-time UI updates
- Hybrid search via Typesense (semantic + keyword)
- MCP tools for agent integration

**Key Addition:** Status field (`draft`, `active`, `deprecated`) for explicit lifecycle management.

## Schema Design

### Diagram Schema

```elixir
# lib/pop_stash/memory/diagram.ex

defmodule PopStash.Memory.Diagram do
  use PopStash.Schema

  schema "diagrams" do
    field(:title, :string)           # Required: "Authentication Flow", "Data Model"
    field(:summary, :string)         # Required: Brief description for search (embeddings)
    field(:content, :string)         # Required: Mermaid diagram text
    field(:diagram_type, :string)    # Optional: "sequence", "flowchart", "er", etc.
    field(:status, :string)          # Required: "draft", "active", "deprecated"
    field(:files, {:array, :string}, default: [])
    field(:tags, {:array, :string}, default: [])
    field(:embedding, Pgvector.Ecto.Vector)  # 384-dim vector

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

**Field Rationale:**
- `title` - Human-readable name (e.g., "JWT Authentication Flow"); preserves case for readability
- `summary` - Powers embeddings; describes what the diagram shows
- `content` - Raw mermaid text; keyword-searchable but not embedded
- `diagram_type` - Freeform hint for rendering (e.g., "sequence", "flowchart"); no validation to stay flexible as Mermaid.js evolves
- `status` - Explicit lifecycle: draft (WIP), active (current), deprecated (outdated)

### Migration

```elixir
# priv/repo/migrations/[timestamp]_create_diagrams.exs

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

## Context Module

Add diagram functions to `lib/pop_stash/memory.ex` following existing patterns.

### Core CRUD Operations

```elixir
@doc """
Creates a diagram.

## Options
  * `:summary` - Brief description for search (required)
  * `:diagram_type` - Type hint for rendering (optional)
  * `:status` - "draft", "active", or "deprecated" (default: "draft")
  * `:files` - Related file paths
  * `:tags` - Categorization tags
"""
def create_diagram(project_id, title, content, opts \\ [])

@doc "Get diagram by ID"
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
List diagrams for a project.

## Options
  * `:limit` - Max results (default: 50)
  * `:status` - Filter by status
  * `:since` - Only after this datetime
"""
def list_diagrams(project_id, opts \\ [])

@doc """
Update diagram status (draft → active → deprecated).
Immutability means only status can change after creation.
"""
def update_diagram_status(diagram_id, new_status)

@doc "Delete diagram (admin only)"
def delete_diagram(diagram_id)

@doc "List all unique diagram titles for a project"
def list_diagram_titles(project_id)

@doc "Search diagrams by semantic similarity"
def search_diagrams(project_id, query, opts \\ [])
```

**Implementation Notes:**
- Follow decision pattern: inline changesets in context, not in schema
- Validate status against `Diagram.valid_statuses()`
- No validation on diagram_type (freeform string to stay flexible as Mermaid evolves)
- Broadcast PubSub events: `:diagram_created`, `:diagram_status_updated`, `:diagram_deleted`

## Embedding & Indexing

Diagrams follow the same async embedding workflow as insights and decisions via `PopStash.Search.Indexer`.

### Indexer Updates

**File:** `lib/pop_stash/search/indexer.ex`

Add PubSub handlers:

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

Add indexing function:

```elixir
defp index_diagram(diagram) do
  # Embed summary only (not mermaid content)
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

**Key Decision:** Embed `title + summary` (not content) because mermaid syntax is cryptic for semantic search. Content remains keyword-searchable via Typesense.

## Search Integration

### Typesense Collection Schema

Add to `lib/pop_stash/search/typesense.ex`:

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

### Typesense Functions

**File:** `lib/pop_stash/search/typesense.ex`

Add indexing function:

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

Add search function:

```elixir
def search_diagrams(project_id, query, opts \\ []) do
  # 1. Generate embedding from query
  # 2. Hybrid search: vector similarity + keyword on title/summary/content
  # 3. Filter by project_id
  # 4. Optional: filter by status (default to active only)
  # 5. Log search with Memory.log_search/5

  status_filter = Keyword.get(opts, :status, "active")
  limit = Keyword.get(opts, :limit, 10)

  filter_by = "project_id:=#{project_id} && status:=#{status_filter}"

  # Follow same pattern as search_insights/search_decisions
  # ...
end
```

**Key Decision:** Embed the `summary` field (not raw mermaid content) because:
- Summaries are semantic and natural language
- Mermaid syntax is cryptic for embeddings
- Content still keyword-searchable for specific terms (e.g., "UserService")

## LiveView UI

### DiagramLive.Index (List View)

**File:** `lib/pop_stash_web/live/diagram_live/index.ex`

**Features:**
- Project filter dropdown (all projects or specific)
- Status filter dropdown (All, Draft, Active, Deprecated) - default to "Active"
- Search input with debounce (300ms)
- Table columns: Title, Summary, Type, Status, Updated
- Status badge component (color-coded: draft=gray, active=green, deprecated=red)
- Actions: View, Change Status, Delete (with confirmation)
- Empty states per filter combination
- Create button → modal form

**Mount:**
```elixir
def mount(_params, _session, socket) do
  if connected?(socket) do
    Phoenix.PubSub.subscribe(PopStash.PubSub, "memory:events")
  end

  socket
  |> assign(:page_title, "Diagrams")
  |> assign(:selected_project_id, nil)
  |> assign(:status_filter, "active")  # Default to active only
  |> assign(:search_query, "")
  |> load_diagrams()
end
```

**PubSub Handlers:**
```elixir
def handle_info({:diagram_created, _}, socket), do: {:noreply, load_diagrams(socket)}
def handle_info({:diagram_status_updated, _}, socket), do: {:noreply, load_diagrams(socket)}
def handle_info({:diagram_deleted, _}, socket), do: {:noreply, load_diagrams(socket)}
```

### DiagramLive.Show (Detail View)

**File:** `lib/pop_stash_web/live/diagram_live/show.ex`

**Features:**
- Render mermaid diagram using colocated hook component (see Frontend Assets section)
- Status badge with "Change Status" dropdown
- Summary in card
- Metadata section: ID, type, tags, timestamps
- Related diagrams section (same title) - simple list, not emphasized
- Delete action (with confirmation)
- Back to list link

**Mermaid Rendering:**
```heex
<.mermaid_diagram content={@diagram.content} class="my-4 border rounded-lg p-4" />
```

Import the component:
```elixir
import PopStashWeb.DiagramComponents
```

### DiagramLive.FormComponent (Create/Edit Modal)

**File:** `lib/pop_stash_web/live/diagram_live/form_component.ex`

**Fields:**
- Title (required, text input)
- Summary (required, textarea)
- Content (required, textarea with monospace font)
- Diagram Type (optional, select with valid types)
- Status (select: draft, active, deprecated)
- Tags (text input, comma-separated)
- Files (textarea, one path per line)

**Validation:**
- Client-side validation via `phx-change`
- Server-side changeset validation
- Optional: validate mermaid syntax on blur (basic check)

## MCP Tools

### create_diagram

**File:** `lib/pop_stash/mcp/tools/create_diagram.ex`

```elixir
%{
  name: "create_diagram",
  description: """
  Create an architectural diagram using Mermaid syntax.

  Diagrams are compact representations of architecture, flows, and relationships.
  Use this to document system architecture, data flows, state machines, etc.
  """,
  inputSchema: %{
    type: "object",
    properties: %{
      title: %{type: "string", description: "Diagram title"},
      summary: %{type: "string", description: "Brief description for search"},
      content: %{type: "string", description: "Mermaid diagram syntax"},
      diagram_type: %{type: "string", description: "Optional: sequence, flowchart, etc."},
      status: %{type: "string", description: "Optional: draft, active, deprecated (default: draft)"},
      tags: %{type: "array", items: %{type: "string"}},
      files: %{type: "array", items: %{type: "string"}}
    },
    required: ["title", "summary", "content"]
  }
}
```

**Response:**
```
Diagram created: [title]
Status: draft
ID: [diagram_id]
```

### get_diagrams

**File:** `lib/pop_stash/mcp/tools/get_diagrams.ex`

```elixir
%{
  name: "get_diagrams",
  description: """
  Search diagrams by title or semantic query.

  Finds architectural diagrams matching your query. Returns diagram content
  in mermaid format for easy consumption.
  """,
  inputSchema: %{
    type: "object",
    properties: %{
      query: %{type: "string", description: "Title or semantic search query"},
      status: %{type: "string", description: "Filter: draft, active, deprecated (default: active)"},
      limit: %{type: "integer", description: "Max results (default: 5)"}
    },
    required: ["query"]
  }
}
```

**Search Strategy:**
1. Try exact title match first
2. Fall back to semantic search via Typesense
3. Default to `status: "active"` (exclude drafts/deprecated unless requested)
4. Log search

**Search Strategy with Logging:**
```elixir
def execute(args, %{project_id: project_id}) do
  query = args["query"]
  status = args["status"] || "active"
  limit = args["limit"] || 5

  start_time = System.monotonic_time(:millisecond)

  case Memory.search_diagrams(project_id, query, status: status, limit: limit) do
    {:ok, []} ->
      duration = System.monotonic_time(:millisecond) - start_time
      Memory.log_search(project_id, query, :diagrams, :semantic,
        tool: "get_diagrams",
        result_count: 0,
        found: false,
        duration_ms: duration
      )
      {:ok, "No diagrams found matching: #{query}"}

    {:ok, results} ->
      duration = System.monotonic_time(:millisecond) - start_time
      Memory.log_search(project_id, query, :diagrams, :semantic,
        tool: "get_diagrams",
        result_count: length(results),
        found: true,
        duration_ms: duration
      )
      {:ok, format_results(results)}
  end
end
```

**Response Format:**
```markdown
## [Diagram Title]
**Status:** active | **Type:** sequence | **Updated:** 2025-01-15

### Summary
[Brief description]

### Diagram
```mermaid
[mermaid content]
```

**Files:** path/to/file.ex
**Tags:** auth, security
```

### update_diagram_status (optional)

Allow agents to deprecate diagrams when they're outdated:

```elixir
%{
  name: "update_diagram_status",
  description: "Change diagram status (draft → active → deprecated)",
  inputSchema: %{
    type: "object",
    properties: %{
      diagram_id: %{type: "string"},
      status: %{type: "string", enum: ["draft", "active", "deprecated"]}
    },
    required: ["diagram_id", "status"]
  }
}
```

## Frontend Assets - Mermaid.js Rendering

Diagrams use [Mermaid.js](https://mermaid.js.org/) for client-side rendering. Users see visual diagrams on the web, not raw text.

### Colocated Mermaid Hook

Use Phoenix LiveView's colocated hooks feature to define the JavaScript hook inline within the component that renders diagrams.

**Create a reusable component:** `lib/pop_stash_web/components/diagram_components.ex`

```elixir
defmodule PopStashWeb.DiagramComponents do
  use Phoenix.Component

  @doc """
  Renders a Mermaid diagram with client-side rendering.

  ## Attributes
    * `content` - The mermaid diagram syntax (required)
    * `class` - Additional CSS classes (optional)
  """
  attr :content, :string, required: true
  attr :class, :string, default: ""

  def mermaid_diagram(assigns) do
    ~H"""
    <div
      id={"diagram-#{:erlang.phash2(@content)}"}
      phx-hook=".MermaidDiagram"
      phx-update="ignore"
      data-diagram={@content}
      class={@class}
    >
      <!-- Mermaid will render here -->
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".MermaidDiagram">
      import mermaid from "mermaid";

      mermaid.initialize({
        startOnLoad: false,
        theme: "default",
        securityLevel: "strict"
      });

      export default {
        mounted() {
          this.render();
        },

        updated() {
          this.render();
        },

        render() {
          const diagram = this.el.dataset.diagram;
          const id = `mermaid-${Math.random().toString(36).substr(2, 9)}`;

          mermaid.render(id, diagram).then(({ svg }) => {
            this.el.innerHTML = svg;
          }).catch(error => {
            this.el.innerHTML = `<pre class="text-red-600">Invalid diagram syntax:\n${error.message}</pre>`;
          });
        }
      }
    </script>
    """
  end
end
```

**Usage in LiveView Show page:**

```elixir
# In DiagramLive.Show
import PopStashWeb.DiagramComponents

def render(assigns) do
  ~H"""
  <.mermaid_diagram content={@diagram.content} class="my-4" />
  """
end
```

**Install mermaid:**
```bash
cd assets && npm install mermaid
```

**Important:** Run `mix compile` before building assets in production, as colocated hooks are only written when the component is compiled.

## Router Updates

**File:** `lib/pop_stash_web/router.ex`

Add to authenticated routes:

```elixir
live "/diagrams", DiagramLive.Index, :index
live "/diagrams/new", DiagramLive.Index, :new
live "/diagrams/:id", DiagramLive.Show, :show
live "/diagrams/:id/edit", DiagramLive.Show, :edit
```

Add to navigation (if applicable).

## Claude Code Hooks Configuration

Update the Claude Code hooks to prompt agents about diagrams alongside insights and decisions.

**File:** `.claude/settings.json` (or `.claude/settings.local.json`)

Add or update the hooks configuration:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "prompt",
            "prompt": "Before starting work, search for previous decisions, insights, or diagrams that might apply to this task."
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "prompt",
            "prompt": "If meaningful work occurred: record insights, document decisions, and create diagrams for architectural changes."
          }
        ]
      }
    ]
  }
}
```

**Purpose:**
- **SessionStart hook** - Reminds agents to check existing architectural knowledge (including diagrams) before starting work
- **Stop hook** - Prompts agents to document architectural changes as diagrams when appropriate

This ensures agents use diagrams as a first-class knowledge primitive alongside insights and decisions.

## Testing Strategy

### Unit Tests

**Context tests** (`test/pop_stash/memory_test.exs`):
- `create_diagram/3` with valid/invalid inputs
- `get_diagram/1` and `get_diagrams_by_title/2`
- `list_diagrams/2` with filters (status, since, limit)
- `update_diagram_status/2` validations
- `delete_diagram/1`
- PubSub broadcasts

**Schema tests** (optional):
- Status enum validation
- Diagram type validation

### Integration Tests

**LiveView tests** (`test/pop_stash_web/live/diagram_live_test.exs`):
- Index: list, filter by status, filter by project, search
- Show: render diagram, view metadata, version history
- Create: form validation, successful creation, modal open/close
- Update status: change from draft → active → deprecated
- Delete: confirmation, success

**MCP tool tests** (`test/pop_stash/mcp/tools/*_test.exs`):
- create_diagram: valid creation, required fields
- get_diagrams: title match, semantic search, status filtering
- update_diagram_status (if implemented)

## Verification Steps

1. **Migration & Seeds**
   ```bash
   mix ecto.migrate
   mix run priv/repo/seeds.exs  # Add sample diagrams
   ```

2. **Create Diagram via UI**
   - Navigate to `/diagrams/new`
   - Fill form with mermaid syntax (e.g., simple flowchart)
   - Verify creation, rendering, and list appearance

3. **Status Lifecycle**
   - Create draft diagram
   - Change to active
   - Verify filtering works (show only active by default)
   - Change to deprecated
   - Verify appears in deprecated filter

4. **Search**
   - Create diagrams with distinct summaries
   - Search by keyword (should match)
   - Search by semantic query (should rank by relevance)

5. **MCP Tool Integration**
   - Test `create_diagram` tool via Claude Code or similar
   - Verify diagram ID returned and can be retrieved
   - Test `get_diagrams` with various queries
   - Verify status filtering (default to active)

6. **Related Diagrams**
   - Create diagram with title "Auth Flow"
   - Create second diagram with same title
   - View in UI - should show other diagrams with same title
   - Verify both diagrams searchable independently

7. **Real-time Updates**
   - Open `/diagrams` in two browser tabs
   - Create diagram in tab 1
   - Verify appears in tab 2 without refresh (PubSub)

## Critical Files

### New Files
- `lib/pop_stash/memory/diagram.ex` - Schema
- `priv/repo/migrations/[timestamp]_create_diagrams.exs` - Migration
- `lib/pop_stash_web/live/diagram_live/index.ex` - List view
- `lib/pop_stash_web/live/diagram_live/show.ex` - Detail view
- `lib/pop_stash_web/live/diagram_live/form_component.ex` - Create/edit modal
- `lib/pop_stash_web/components/diagram_components.ex` - Mermaid component with colocated hook
- `lib/pop_stash/mcp/tools/create_diagram.ex` - MCP tool
- `lib/pop_stash/mcp/tools/get_diagrams.ex` - MCP tool
- `test/pop_stash/memory_test.exs` - Context tests (extend existing)
- `test/pop_stash_web/live/diagram_live_test.exs` - LiveView tests

### Modified Files
- `lib/pop_stash/memory.ex` - Add diagram functions
- `lib/pop_stash/search/indexer.ex` - Add diagram event handlers & indexing
- `lib/pop_stash/search/typesense.ex` - Add diagrams schema & search
- `lib/pop_stash_web/router.ex` - Add diagram routes
- `lib/pop_stash/mcp/server.ex` - Register new MCP tools
- `assets/package.json` - Add mermaid dependency
- `.claude/settings.json` (or settings.local.json) - Update hooks to include diagrams

## Open Questions

1. **Status transitions:** Should we enforce draft → active → deprecated flow, or allow arbitrary changes?
   - **Recommendation:** Allow any transition for flexibility (admin can fix mistakes)

2. **Deprecation cascade:** When a decision is deprecated, should related diagrams auto-deprecate?
   - **Recommendation:** No automatic cascade; diagrams may outlive specific decisions

3. **Diagram validation:** Should we validate mermaid syntax on save?
   - **Recommendation:** Optional client-side warning; don't block saves (syntax evolves)

4. **Default status in get_diagrams tool:** Should agents see all statuses or just active?
   - **Decision:** Default to `active` only; require explicit opt-in for drafts/deprecated ✓

5. **Embedding generation:** When is embedding created - on insert or async?
   - **Answer:** Async via PubSub (see implementation details below)

## Implementation Notes

### Design Decisions

**Immutability with Mutable Status**
Diagrams are immutable by design (like decisions), but the status field is an exception. Status represents our current interpretation of the diagram (draft/active/deprecated), not the diagram content itself. This allows lifecycle management without losing history. This tension is documented in the schema module.

**Title Case Preservation**
Unlike decisions (which normalize to lowercase), diagram titles preserve case for better human readability. Typesense handles case-insensitive search automatically.

**Embedding Strategy**
Only `title + summary` are embedded for semantic search. Mermaid content remains keyword-searchable but isn't embedded, as the syntax is structured for machines, not semantic similarity.

**No Type Validation**
The `diagram_type` field is freeform without validation. Mermaid.js evolves quickly, and hardcoding types creates maintenance burden. This field is a hint for rendering, not a constraint.

### Implementation Priority

Recommended build order:
1. **Schema + Migration + Context CRUD** - Core functionality
2. **MCP tools** - Enables agent usage immediately (highest value)
3. **Indexing + Search** - Adds discoverability
4. **LiveView UI** - Human interface
5. **Mermaid rendering** - Visual polish

This lets you test with agents first (where diagrams provide the most value) before investing in UI.

### Potential Issues to Watch

**Mermaid.js Bundle Size**
Mermaid.js is ~1MB minified. Acceptable for an admin tool, but consider lazy-loading if bundle size is a concern.

**Typesense Schema Evolution**
Ensure `Typesense.ensure_collections/0` handles the new diagrams collection gracefully if the app is already running in production.

**Migration Rollback**
If rolling back the migration, remember to also drop the Typesense collection. Consider adding a note in the migration.

**Status Audit Trail**
Arbitrary status transitions are allowed for flexibility. If audit history matters, consider adding a `diagram_status_history` table.

**Files Field Semantics**
The `files` field is inherited from insights/decisions but may not be essential. Consider whether it provides value or just adds conceptual overhead. If keeping it, document when to use it vs. inline file references.

## Future Enhancements (Out of Scope)

- Diagram → Decision/Insight relationships (many-to-many)
- Visual diagram editor (WYSIWYG)
- Diagram diffing (compare versions side-by-side)
- Export to PNG/SVG
- Automatic diagram generation from code (via agent)
- Diagram templates library
