# Step 3: MCP Tools

## Overview
Create MCP tools to allow AI agents to create and search diagrams.

## Context
MCP tools follow the existing patterns from insights/decisions. The `create_diagram` tool allows agents to document architecture, and `get_diagrams` enables discovery with search logging for analytics.

## Implementation

### 1. Create Diagram Tool

**File:** `lib/pop_stash/mcp/tools/create_diagram.ex`

```elixir
defmodule PopStash.MCP.Tools.CreateDiagram do
  @moduledoc """
  MCP tool for creating architectural diagrams using Mermaid syntax.
  """

  alias PopStash.Memory

  def definition do
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
          diagram_type: %{
            type: "string",
            description: "Optional: sequence, flowchart, etc."
          },
          status: %{
            type: "string",
            description: "Optional: draft, active, deprecated (default: draft)"
          },
          tags: %{type: "array", items: %{type: "string"}},
          files: %{type: "array", items: %{type: "string"}}
        },
        required: ["title", "summary", "content"]
      }
    }
  end

  def execute(args, %{project_id: project_id}) do
    opts = []
      |> maybe_add_opt(:summary, args["summary"])
      |> maybe_add_opt(:diagram_type, args["diagram_type"])
      |> maybe_add_opt(:status, args["status"])
      |> maybe_add_opt(:tags, args["tags"])
      |> maybe_add_opt(:files, args["files"])

    case Memory.create_diagram(project_id, args["title"], args["content"], opts) do
      {:ok, diagram} ->
        {:ok, format_response(diagram)}

      {:error, changeset} ->
        errors = format_errors(changeset)
        {:error, "Failed to create diagram: #{errors}"}
    end
  end

  defp format_response(diagram) do
    """
    Diagram created: #{diagram.title}
    Status: #{diagram.status}
    ID: #{diagram.id}

    The diagram has been saved and will be searchable shortly.
    """
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
    |> Enum.join("; ")
  end

  defp maybe_add_opt(opts, _key, nil), do: opts
  defp maybe_add_opt(opts, key, value), do: Keyword.put(opts, key, value)
end
```

### 2. Get Diagrams Tool

**File:** `lib/pop_stash/mcp/tools/get_diagrams.ex`

```elixir
defmodule PopStash.MCP.Tools.GetDiagrams do
  @moduledoc """
  MCP tool for searching diagrams by title or semantic query.
  """

  alias PopStash.Memory

  def definition do
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
          status: %{
            type: "string",
            description: "Filter: draft, active, deprecated (default: active)"
          },
          limit: %{type: "integer", description: "Max results (default: 5)"}
        },
        required: ["query"]
      }
    }
  end

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

      {:error, reason} ->
        {:error, "Search failed: #{inspect(reason)}"}
    end
  end

  defp format_results(diagrams) do
    diagrams
    |> Enum.map(&format_diagram/1)
    |> Enum.join("\n\n---\n\n")
  end

  defp format_diagram(diagram) do
    """
    ## #{diagram.title}
    **Status:** #{diagram.status} | **Type:** #{diagram.diagram_type || "unspecified"}

    ### Summary
    #{diagram.summary}

    ### Diagram
    ```mermaid
    #{diagram.content}
    ```
    """
    |> maybe_add_tags(diagram)
    |> maybe_add_files(diagram)
  end

  defp maybe_add_tags(text, %{tags: []}), do: text
  defp maybe_add_tags(text, %{tags: tags}) when is_list(tags) do
    text <> "\n**Tags:** #{Enum.join(tags, ", ")}"
  end

  defp maybe_add_files(text, %{files: []}), do: text
  defp maybe_add_files(text, %{files: files}) when is_list(files) do
    text <> "\n**Files:** #{Enum.join(files, ", ")}"
  end
end
```

### 3. Register Tools

**File:** `lib/pop_stash/mcp/server.ex`

Add to the tools list in `handle_call({:tools_list}, _from, state)`:

```elixir
PopStash.MCP.Tools.CreateDiagram.definition(),
PopStash.MCP.Tools.GetDiagrams.definition(),
```

Add to the tool execution handler in `handle_call({:tools_call, name, args}, _from, state)`:

```elixir
"create_diagram" ->
  PopStash.MCP.Tools.CreateDiagram.execute(args, state)

"get_diagrams" ->
  PopStash.MCP.Tools.GetDiagrams.execute(args, state)
```

## Verification

### Manual Testing via Claude Code

```bash
# In Claude Code MCP console or via agent interaction

# Create a diagram
create_diagram(
  title: "User Authentication Flow",
  summary: "Shows JWT-based authentication from login to protected routes",
  content: """
  sequenceDiagram
    User->>+API: POST /login
    API->>+DB: Verify credentials
    DB-->>-API: User found
    API->>API: Generate JWT
    API-->>-User: Return token
    User->>+API: GET /protected (with token)
    API->>API: Verify JWT
    API-->>-User: Protected data
  """,
  diagram_type: "sequence",
  status: "active"
)

# Search for it
get_diagrams(query: "authentication", status: "active")

# Should return the diagram with mermaid content
```

## Tests

**File:** `test/pop_stash/mcp/tools/create_diagram_test.exs`

```elixir
defmodule PopStash.MCP.Tools.CreateDiagramTest do
  use PopStash.DataCase

  alias PopStash.MCP.Tools.CreateDiagram
  alias PopStash.Memory

  setup do
    project = insert(:project)
    %{project_id: project.id}
  end

  describe "execute/2" do
    test "creates diagram with required fields only", %{project_id: project_id} do
      args = %{
        "title" => "Test Diagram",
        "summary" => "A test diagram",
        "content" => "graph TD\n  A --> B"
      }

      assert {:ok, response} = CreateDiagram.execute(args, %{project_id: project_id})
      assert response =~ "Test Diagram"
      assert response =~ "draft"
      assert response =~ "Diagram created"
    end

    test "creates diagram with all optional fields", %{project_id: project_id} do
      args = %{
        "title" => "Full Diagram",
        "summary" => "Complete diagram",
        "content" => "sequenceDiagram\n  A->>B: Message",
        "diagram_type" => "sequence",
        "status" => "active",
        "tags" => ["auth", "api"],
        "files" => ["lib/auth.ex", "lib/api.ex"]
      }

      assert {:ok, response} = CreateDiagram.execute(args, %{project_id: project_id})
      assert response =~ "Full Diagram"
      assert response =~ "active"

      # Verify diagram was created with all fields
      {:ok, diagrams} = Memory.list_diagrams(project_id) |> then(&{:ok, &1})
      diagram = Enum.find(diagrams, &(&1.title == "Full Diagram"))

      assert diagram.diagram_type == "sequence"
      assert diagram.status == "active"
      assert diagram.tags == ["auth", "api"]
      assert diagram.files == ["lib/auth.ex", "lib/api.ex"]
    end

    test "validates required title field", %{project_id: project_id} do
      args = %{
        "summary" => "Missing title",
        "content" => "graph TD\n  A --> B"
      }

      assert {:error, message} = CreateDiagram.execute(args, %{project_id: project_id})
      assert message =~ "title"
    end

    test "validates required summary field", %{project_id: project_id} do
      args = %{
        "title" => "Test",
        "content" => "graph TD\n  A --> B"
      }

      assert {:error, message} = CreateDiagram.execute(args, %{project_id: project_id})
      assert message =~ "summary"
    end

    test "validates required content field", %{project_id: project_id} do
      args = %{
        "title" => "Test",
        "summary" => "Test summary"
      }

      assert {:error, message} = CreateDiagram.execute(args, %{project_id: project_id})
      assert message =~ "content"
    end

    test "validates status field", %{project_id: project_id} do
      args = %{
        "title" => "Test",
        "summary" => "Test summary",
        "content" => "graph TD\n  A --> B",
        "status" => "invalid_status"
      }

      assert {:error, message} = CreateDiagram.execute(args, %{project_id: project_id})
      assert message =~ "status"
    end

    test "returns formatted response with diagram ID", %{project_id: project_id} do
      args = %{
        "title" => "Response Test",
        "summary" => "Testing response format",
        "content" => "graph TD\n  A --> B"
      }

      assert {:ok, response} = CreateDiagram.execute(args, %{project_id: project_id})
      assert response =~ "Diagram created: Response Test"
      assert response =~ "Status: draft"
      assert response =~ "ID:"
      assert response =~ "will be searchable shortly"
    end
  end

  describe "definition/0" do
    test "returns valid MCP tool definition" do
      definition = CreateDiagram.definition()

      assert definition.name == "create_diagram"
      assert definition.description =~ "Mermaid"
      assert definition.inputSchema.required == ["title", "summary", "content"]
      assert definition.inputSchema.properties.title
      assert definition.inputSchema.properties.summary
      assert definition.inputSchema.properties.content
      assert definition.inputSchema.properties.diagram_type
      assert definition.inputSchema.properties.status
    end
  end
end
```

**File:** `test/pop_stash/mcp/tools/get_diagrams_test.exs`

```elixir
defmodule PopStash.MCP.Tools.GetDiagramsTest do
  use PopStash.DataCase

  alias PopStash.MCP.Tools.GetDiagrams
  alias PopStash.Memory

  setup do
    project = insert(:project)

    # Create test diagrams
    {:ok, _} =
      Memory.create_diagram(
        project.id,
        "Authentication Flow",
        "sequenceDiagram\n  User->>API: Login",
        summary: "Shows how users authenticate",
        status: "active",
        diagram_type: "sequence",
        tags: ["auth", "security"],
        files: ["lib/auth.ex"]
      )

    {:ok, _} =
      Memory.create_diagram(
        project.id,
        "Data Pipeline",
        "graph TD\n  A[Input]-->B[Process]",
        summary: "ETL pipeline architecture",
        status: "active",
        diagram_type: "flowchart"
      )

    {:ok, _} =
      Memory.create_diagram(
        project.id,
        "Draft Diagram",
        "graph TD\n  X-->Y",
        summary: "Work in progress",
        status: "draft"
      )

    # Wait for indexing
    Process.sleep(200)

    %{project_id: project.id}
  end

  describe "execute/2" do
    test "searches diagrams by query", %{project_id: project_id} do
      args = %{"query" => "authentication"}

      assert {:ok, response} = GetDiagrams.execute(args, %{project_id: project_id})
      assert response =~ "Authentication Flow"
      assert response =~ "Shows how users authenticate"
      assert response =~ "```mermaid"
    end

    test "filters by status", %{project_id: project_id} do
      # Default is active
      args = %{"query" => "diagram"}

      assert {:ok, response} = GetDiagrams.execute(args, %{project_id: project_id})
      refute response =~ "Draft Diagram"

      # Explicitly search drafts
      args = %{"query" => "diagram", "status" => "draft"}

      assert {:ok, response} = GetDiagrams.execute(args, %{project_id: project_id})
      assert response =~ "Draft Diagram"
    end

    test "respects limit parameter", %{project_id: project_id} do
      args = %{"query" => "diagram", "limit" => 1}

      assert {:ok, response} = GetDiagrams.execute(args, %{project_id: project_id})
      # Should only return one diagram
      refute response =~ "---"
    end

    test "returns message when no results found", %{project_id: project_id} do
      args = %{"query" => "nonexistent_diagram_xyz"}

      assert {:ok, response} = GetDiagrams.execute(args, %{project_id: project_id})
      assert response =~ "No diagrams found matching"
      assert response =~ "nonexistent_diagram_xyz"
    end

    test "formats results with mermaid syntax", %{project_id: project_id} do
      args = %{"query" => "authentication"}

      assert {:ok, response} = GetDiagrams.execute(args, %{project_id: project_id})
      assert response =~ "## Authentication Flow"
      assert response =~ "**Status:** active"
      assert response =~ "**Type:** sequence"
      assert response =~ "### Summary"
      assert response =~ "### Diagram"
      assert response =~ "```mermaid"
      assert response =~ "sequenceDiagram"
    end

    test "includes tags when present", %{project_id: project_id} do
      args = %{"query" => "authentication"}

      assert {:ok, response} = GetDiagrams.execute(args, %{project_id: project_id})
      assert response =~ "**Tags:** auth, security"
    end

    test "includes files when present", %{project_id: project_id} do
      args = %{"query" => "authentication"}

      assert {:ok, response} = GetDiagrams.execute(args, %{project_id: project_id})
      assert response =~ "**Files:** lib/auth.ex"
    end

    test "logs search analytics on success", %{project_id: project_id} do
      args = %{"query" => "authentication"}

      GetDiagrams.execute(args, %{project_id: project_id})

      # Verify search was logged
      searches = Memory.list_searches(project_id)
      search = Enum.find(searches, &(&1.query == "authentication"))

      assert search.entity_type == :diagrams
      assert search.search_type == :semantic
      assert search.metadata["tool"] == "get_diagrams"
      assert search.found == true
      assert search.result_count > 0
    end

    test "logs search analytics on no results", %{project_id: project_id} do
      args = %{"query" => "nonexistent_xyz"}

      GetDiagrams.execute(args, %{project_id: project_id})

      searches = Memory.list_searches(project_id)
      search = Enum.find(searches, &(&1.query == "nonexistent_xyz"))

      assert search.found == false
      assert search.result_count == 0
    end
  end

  describe "definition/0" do
    test "returns valid MCP tool definition" do
      definition = GetDiagrams.definition()

      assert definition.name == "get_diagrams"
      assert definition.description =~ "Search diagrams"
      assert definition.inputSchema.required == ["query"]
      assert definition.inputSchema.properties.query
      assert definition.inputSchema.properties.status
      assert definition.inputSchema.properties.limit
    end
  end
end
```

**Run tests:**
```bash
mix test test/pop_stash/mcp/tools/create_diagram_test.exs
mix test test/pop_stash/mcp/tools/get_diagrams_test.exs
```

## Dependencies
- Step 0 completed (schema exists)
- Step 1 completed (context functions exist)
- Step 2 completed (search works)
- Existing MCP server infrastructure
