# Step 7: MCP Multi-Tenancy + Typesense org_id

## Objective

Update the MCP endpoint to derive `org_id` from the project and set it in the process dictionary. Update MCP tool modules to pass `%Scope{}` to context functions. Zero breaking changes to the JSON-RPC 2.0 contract. Additionally, add `org_id` to Typesense collection schemas and filter_by clauses for robust cross-org isolation in search.

## Prerequisites

- Step 1 completed (Repo.put_org_id exists)
- Step 4 completed (contexts accept Scope)

## Current MCP Architecture

The MCP uses JSON-RPC 2.0 via these files:

- **Controller**: `/workspace/lib/pop_stash_web/controllers/mcp_controller.ex` -- validates project_id, delegates to Server
- **Server**: `/workspace/lib/pop_stash/mcp/server.ex` -- routes JSON-RPC methods, dispatches to tool modules
- **Tool modules**: `/workspace/lib/pop_stash/mcp/tools/*.ex` -- each implements `ToolBehaviour`, has `tools/0` and callback functions
- **Tool behaviour**: `/workspace/lib/pop_stash/mcp/tool_behaviour.ex`

Tool callbacks receive `(args, context)` where `context` is `%{project_id: id, project_name: name}`.

## Implementation

### 1. Update MCP Controller

**File**: `/workspace/lib/pop_stash_web/controllers/mcp_controller.ex`

The controller already calls `Projects.get(project_id)`. Change to `Projects.get_by_id(project_id)` (unscoped, since MCP is pre-auth). Then set `Repo.put_org_id` and add `org_id` to context.

```elixir
def handle(conn, %{"project_id" => project_id}) do
  case Projects.get_by_id(project_id) do
    {:ok, project} ->
      # Set org_id for prepare_query enforcement on downstream reads
      Repo.put_org_id(project.org_id)

      context = %{
        project_id: project.id,
        project_name: project.name,
        org_id: project.org_id
      }

      case Server.handle_message(conn.body_params, context) do
        {:ok, :notification} -> send_resp(conn, 204, "")
        {:ok, response} -> json(conn, response)
        {:error, response} -> json(conn, response)
      end

    {:error, :not_found} ->
      # ... existing error handling unchanged ...
  end
end
```

### 2. Update MCP Tool Modules

Each tool module's callback receives `context` which now includes `:org_id`. Build a system-level `%Scope{}` from the context and pass it to Memory functions.

**File**: `/workspace/lib/pop_stash/mcp/tools/insight.ex`

```elixir
def execute(args, %{project_id: project_id, org_id: org_id}) do
  scope = %PopStash.Scope{org_id: org_id, user_id: nil, role: :owner}

  opts =
    []
    |> maybe_add_opt(:title, args["title"])
    |> maybe_add_opt(:tags, args["tags"])
    |> maybe_add_opt(:thread_id, args["thread_id"])

  case Memory.create_insight(scope, project_id, args["body"], opts) do
    {:ok, insight} ->
      title_text = if insight.title, do: " (title: #{insight.title})", else: ""
      {:ok, "Insight saved#{title_text}. Use `recall` to retrieve. (thread_id: #{insight.thread_id})"}

    {:error, changeset} ->
      {:error, format_errors(changeset)}
  end
end
```

**File**: `/workspace/lib/pop_stash/mcp/tools/decide.ex`

Same pattern -- build scope from context, pass to `Memory.create_decision(scope, ...)`.

**File**: `/workspace/lib/pop_stash/mcp/tools/recall.ex`

For read operations, `Repo.put_org_id` is already called in the controller, so `prepare_query` handles scoping automatically. The Recall tool calls `Memory.search_insights` and `Memory.list_insights` which go through Repo. Update the function signatures to pass scope if the Memory functions now require it.

```elixir
def execute(args, %{project_id: project_id, org_id: org_id}) do
  scope = %PopStash.Scope{org_id: org_id, user_id: nil, role: :owner}
  # Use scope for Memory calls that require it
  # ...
end
```

**File**: `/workspace/lib/pop_stash/mcp/tools/get_decisions.ex`

Same pattern as Recall -- build scope, pass to `Memory.list_decisions(scope, ...)` and `Memory.get_decisions_by_title(scope, ...)`.

### 3. Update MCP Server context passing

**File**: `/workspace/lib/pop_stash/mcp/server.ex`

The Server already passes `context` through to tools. Ensure the `initialize` response includes org_id:

```elixir
defp route(%{"method" => "initialize", "id" => id, "params" => params}, context) do
  # ... existing validation ...
  {:ok, success(id, %{
    protocolVersion: version,
    capabilities: %{tools: %{listChanged: false}},
    serverInfo: %{name: "PopStash", version: app_version()},
    projectId: context.project_id,
    projectName: context.project_name,
    orgId: context.org_id,  # NEW: include org_id
    tools: tools()
  })}
end
```

## Security Considerations

- MCP endpoint is protected by `CheckLocalhost` plug -- only localhost can access
- `org_id` is always derived from the project record (trusted data), never from user input
- The `Scope` created for MCP has `user_id: nil` and `role: :owner` -- this is a system-level scope
- `Repo.put_org_id` is called before any reads, so `prepare_query` enforces isolation

## Verification

```bash
mix phx.server

# Test MCP still works
curl -X POST http://localhost:4000/mcp/PROJECT_ID \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'

# Create insight via MCP
curl -X POST http://localhost:4000/mcp/PROJECT_ID \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 2,
    "method": "tools/call",
    "params": {
      "name": "insight",
      "arguments": {"body": "Test insight from MCP"}
    }
  }'

# Verify insight has correct org_id
iex -S mix
insight = PopStash.Repo.one(PopStash.Memory.Insight, skip_org_id: true)
project = PopStash.Repo.get!(PopStash.Projects.Project, insight.project_id, skip_org_id: true)
assert insight.org_id == project.org_id
```

## Tests

Update existing MCP tests to set up org context.

**File**: `test/pop_stash/mcp/server_test.exs`

Add org context to setup:

```elixir
setup do
  %{scope: scope, org: org} = setup_org_context()
  {:ok, project} = PopStash.Projects.create(scope, "Test Project")

  context = %{
    project_id: project.id,
    project_name: project.name,
    org_id: org.id
  }

  %{context: context, project: project, org: org, scope: scope}
end
```

**File**: `test/pop_stash/mcp/tools/insight_test.exs` (and other tool tests)

Update setup to include org context and verify org_id is set on created records:

```elixir
setup do
  %{scope: scope, org: org} = setup_org_context()
  {:ok, project} = PopStash.Projects.create(scope, "Test Project")

  context = %{project_id: project.id, project_name: project.name, org_id: org.id}
  %{context: context, project: project, org: org}
end

test "creates insight with correct org_id", %{context: context, org: org} do
  args = %{"body" => "Test insight"}
  assert {:ok, _} = PopStash.MCP.Tools.Insight.execute(args, context)

  insight = Repo.one!(PopStash.Memory.Insight)
  assert insight.org_id == org.id
end
```

## Dependencies

- Step 1 completed (Repo.put_org_id, Scope struct)
- Step 4 completed (contexts accept Scope)

### 4. Add org_id to Typesense Collection Schemas

**File**: `/workspace/lib/pop_stash/search/typesense.ex`

Add `org_id` field to both `@insights_schema` and `@decisions_schema`:

```elixir
# Add to the fields list in @insights_schema
%{name: "org_id", type: "string", facet: false}

# Add to the fields list in @decisions_schema
%{name: "org_id", type: "string", facet: false}
```

Update `index_insight/2` and `index_decision/2` to include `org_id` in the document:

```elixir
# In index_insight/2, add to the document map:
"org_id" => insight.org_id

# In index_decision/2, add to the document map:
"org_id" => decision.org_id
```

Update `search_insights/3` and `search_decisions/3` to include `org_id` in filter_by:

```elixir
# Before
filter_by: "project_id:#{project_id}"

# After
filter_by: "project_id:#{project_id} && org_id:#{org_id}"
```

The search functions will need to accept `org_id` (from the Scope) to build the filter. Update the Memory context's search functions to pass `scope.org_id` through to Typesense.

**Migration**: Existing Typesense collections must be re-created or updated to include the new field. Add a mix task or migration note:

```bash
# Drop and recreate collections (dev/staging only)
# In production, use Typesense collection update API to add the field
```

### 5. Update Typesense Tests

Add tests verifying org_id filtering in Typesense search:

```elixir
test "search_insights filters by org_id" do
  # Index insight with org1
  # Index insight with org2
  # Search with org1 scope -- only org1 results returned
end
```

## Important Notes

- **JSON-RPC contract unchanged**: The MCP API accepts the same requests and returns the same responses. The only addition is `orgId` in the `initialize` response (additive, non-breaking).
- **MCP reads are auto-scoped**: Because `Repo.put_org_id` is called in the controller before delegating to Server, all downstream Repo reads are automatically scoped.
- **MCP writes use system scope**: The `%Scope{user_id: nil, role: :owner}` is a system-level scope. No user attribution for MCP-created content.
- **Typesense org_id**: Both collection schemas now include `org_id` and all search queries filter by it. This provides defense-in-depth alongside the Repo-level `prepare_query` enforcement.
