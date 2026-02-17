# Step 7: MCP Multi-Tenancy

## Overview
Update the MCP (Model Context Protocol) endpoint to handle org_id for data isolation. The MCP endpoint is used by AI tools to create insights and decisions.

## Context
The MCP endpoint at `/mcp/:project_id` is currently IP-protected (localhost only) and bypasses all org scoping. After multi-tenancy, we must ensure that MCP-created records have the correct org_id.

## Implementation Strategy

Since the MCP endpoint is localhost-only (enforced by `CheckLocalhost` plug), we trust the local environment. The MCP context will automatically include the project's org_id when creating records.

### 1. Update MCP Controller

**File**: `lib/pop_stash_web/controllers/mcp_controller.ex`

Update to pass org_id through context:

```elixir
defmodule PopStashWeb.MCPController do
  use PopStashWeb, :controller

  alias PopStash.MCP
  alias PopStash.Projects

  def index(conn, _params) do
    projects = Projects.list_all()  # MCP needs all projects for tool selection
    json(conn, %{projects: projects})
  end

  def show(conn, %{"project_id" => project_id}) do
    case Projects.get_by_id(project_id) do
      {:ok, project} ->
        json(conn, %{
          project_id: project.id,
          name: project.name,
          org_id: project.org_id  # Include org_id in response
        })

      {:error, _} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Project not found"})
    end
  end

  def handle(conn, %{"project_id" => project_id} = params) do
    case Projects.get_by_id(project_id) do
      {:ok, project} ->
        # Set org_id in process dictionary for prepare_query enforcement
        PopStash.Repo.put_org_id(project.org_id)

        # Pass org_id to MCP handler
        context = %{
          project_id: project.id,
          org_id: project.org_id,
          request_params: params
        }

        case MCP.handle_request(context) do
          {:ok, result} ->
            json(conn, result)

          {:error, reason} ->
            conn
            |> put_status(:bad_request)
            |> json(%{error: reason})
        end

      {:error, _} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Project not found"})
    end
  end
end
```

### 2. Update MCP Context

**File**: `lib/pop_stash/mcp.ex`

Update to accept org_id and pass it to Memory functions:

```elixir
defmodule PopStash.MCP do
  @moduledoc """
  Handles Model Context Protocol requests for AI tools.
  """

  alias PopStash.Memory
  alias PopStash.Scope

  def handle_request(%{project_id: project_id, org_id: org_id} = context) do
    # Create a system-level scope for MCP operations
    # MCP is trusted (localhost only), so we create a scope with owner permissions
    scope = %Scope{
      org_id: org_id,
      user_id: nil,  # System operation, no specific user
      role: :owner
    }

    tool = context.request_params["tool"]
    params = context.request_params["params"] || %{}

    case tool do
      "create_insight" ->
        create_insight(scope, project_id, params)

      "create_decision" ->
        create_decision(scope, project_id, params)

      "search_insights" ->
        search_insights(scope, project_id, params)

      _ ->
        {:error, "Unknown tool: #{tool}"}
    end
  end

  defp create_insight(scope, project_id, %{"body" => body} = params) do
    opts = [
      tags: params["tags"] || [],
      embedding: params["embedding"]
    ]

    case Memory.create_insight(scope, project_id, body, opts) do
      {:ok, insight} ->
        {:ok, %{
          id: insight.id,
          body: insight.body,
          project_id: insight.project_id,
          org_id: insight.org_id
        }}

      error -> error
    end
  end

  defp create_decision(scope, project_id, %{"title" => title, "body" => body} = params) do
    opts = [
      tags: params["tags"] || [],
      status: params["status"] || "active"
    ]

    case Memory.create_decision(scope, project_id, title, body, opts) do
      {:ok, decision} ->
        {:ok, %{
          id: decision.id,
          title: decision.title,
          body: decision.body,
          project_id: decision.project_id,
          org_id: decision.org_id
        }}

      error -> error
    end
  end

  defp search_insights(scope, project_id, %{"query" => query}) do
    # TODO: Update when Typesense org isolation is implemented (Step 8)
    insights = Memory.list_insights(scope, project_id, limit: 10)

    {:ok, %{
      results: Enum.map(insights, fn insight ->
        %{
          id: insight.id,
          body: insight.body,
          project_id: insight.project_id
        }
      end)
    }}
  end
end
```

### 3. Add Projects.get_by_id helper

**File**: `lib/pop_stash/projects.ex`

Add a non-scoped getter for system operations like MCP:

```elixir
# Add to existing Projects context

@doc """
Gets a project by ID without scope validation.
ONLY for system operations like MCP (localhost-only).
LiveViews and user-facing code MUST use get/2 with Scope.
"""
def get_by_id(id) do
  case Repo.get(Project, id) do
    nil -> {:error, :not_found}
    project -> {:ok, project}
  end
end

@doc """
Lists all projects across all organizations.
ONLY for system operations like MCP project listing.
LiveViews MUST use list/2 with Scope.
"""
def list_all do
  Project
  |> order_by(desc: :inserted_at)
  |> Repo.all()
end
```

### 4. Add Projects.list_all helper

This is needed for the MCP index endpoint which shows all projects for tool selection. Since MCP is localhost-only, this is safe.

## Security Considerations

**Why this is safe:**
1. MCP endpoint is protected by `CheckLocalhost` plug - only localhost can access
2. Localhost environment is trusted (developer's machine or secure server)
3. MCP creates records with correct org_id from the project relationship
4. No cross-org data leakage because org_id is derived from the project, not user input

**What's NOT safe:**
- Removing `CheckLocalhost` protection
- Exposing MCP endpoint to the internet without authentication
- Allowing user-provided org_id in MCP requests (always derive from project)

## Verification

```bash
# Start server
mix phx.server

# Test MCP endpoint (from localhost)
curl http://localhost:4000/mcp

# Create insight via MCP
curl -X POST http://localhost:4000/mcp/PROJECT_ID \
  -H "Content-Type: application/json" \
  -d '{
    "tool": "create_insight",
    "params": {
      "body": "Test insight from MCP"
    }
  }'

# Verify org_id is set correctly
iex -S mix
insight = PopStash.Repo.get(PopStash.Memory.Insight, "INSIGHT_ID")
project = PopStash.Repo.get(PopStash.Projects.Project, insight.project_id)
assert insight.org_id == project.org_id
```

## Tests

**File**: `test/pop_stash_web/controllers/mcp_controller_test.exs`

```elixir
defmodule PopStashWeb.MCPControllerTest do
  use PopStashWeb.ConnCase

  setup do
    org = insert(:organization)
    project = insert(:project, org_id: org.id)

    {:ok, org: org, project: project}
  end

  describe "POST /mcp/:project_id" do
    test "creates insight with correct org_id", %{conn: conn, org: org, project: project} do
      params = %{
        "tool" => "create_insight",
        "params" => %{
          "body" => "Test insight"
        }
      }

      conn = post(conn, ~p"/mcp/#{project.id}", params)

      assert %{"id" => insight_id, "org_id" => org_id} = json_response(conn, 200)
      assert org_id == org.id

      # Verify in database
      insight = Repo.get!(PopStash.Memory.Insight, insight_id)
      assert insight.org_id == org.id
      assert insight.project_id == project.id
    end

    test "creates decision with correct org_id", %{conn: conn, org: org, project: project} do
      params = %{
        "tool" => "create_decision",
        "params" => %{
          "title" => "Test decision",
          "body" => "Test body"
        }
      }

      conn = post(conn, ~p"/mcp/#{project.id}", params)

      assert %{"id" => decision_id, "org_id" => org_id} = json_response(conn, 200)
      assert org_id == org.id

      # Verify in database
      decision = Repo.get!(PopStash.Memory.Decision, decision_id)
      assert decision.org_id == org.id
      assert decision.project_id == project.id
    end

    test "returns 404 for non-existent project", %{conn: conn} do
      conn = post(conn, ~p"/mcp/#{Ecto.UUID.generate()}", %{"tool" => "create_insight"})

      assert %{"error" => "Project not found"} = json_response(conn, 404)
    end
  end
end
```

## Dependencies
- Step 4 completed (Contexts accept Scope and have org_id in changesets)
- Step 1 completed (org_id columns exist on all tables)

## Next Step
Step 8 will add org_id to Typesense collections and update search queries.

## Notes
- **Localhost-only**: MCP remains IP-protected per original requirement
- **System scope**: MCP uses system-level scope with owner permissions
- **Derived org_id**: Always derived from project, never from user input
- **No breaking changes**: MCP API remains unchanged for tools
- **Future enhancement**: Could add API keys for remote MCP access (not in this plan)
