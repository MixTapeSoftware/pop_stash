# Step 6: Update LiveViews

## Overview
Update all dashboard LiveViews to use Scope-aware context calls, using current_scope from assigns.

## Context
With Scope-aware contexts (Step 4) and OrgPlug (Step 5) in place, LiveViews now have current_scope available in assigns. Update all LiveViews to pass scope to context functions.

## Implementation

### Pattern for All LiveViews

**Before**:
```elixir
def mount(_params, _session, socket) do
  projects = PopStash.Projects.list()
  {:ok, assign(socket, projects: projects)}
end

def handle_event("create", %{"name" => name}, socket) do
  case PopStash.Projects.create(name) do
    {:ok, project} -> ...
  end
end
```

**After**:
```elixir
def mount(_params, _session, socket) do
  scope = socket.assigns.current_scope
  projects = PopStash.Projects.list(scope)
  {:ok, assign(socket, projects: projects)}
end

def handle_event("create", %{"name" => name}, socket) do
  scope = socket.assigns.current_scope
  case PopStash.Projects.create(scope, name) do
    {:ok, project} -> ...
  end
end
```

### Files to Update

#### 1. Dashboard Projects LiveView

**File**: `lib/pop_stash_web/live/dashboard/projects_live.ex`

Update all calls:
- `Projects.list()` → `Projects.list(scope)`
- `Projects.create(name)` → `Projects.create(scope, name)`
- `Projects.get(id)` → `Projects.get(scope, id)`
- `Projects.update(id, attrs)` → `Projects.update(scope, id, attrs)`
- `Projects.delete(id)` → `Projects.delete(scope, id)`

Add scope extraction at top of each function:
```elixir
scope = socket.assigns.current_scope
```

#### 2. Dashboard Insights LiveView

**File**: `lib/pop_stash_web/live/dashboard/insights_live.ex`

Update all calls:
- `Memory.list_insights(project_id)` → `Memory.list_insights(scope, project_id)`
- `Memory.create_insight(...)` → `Memory.create_insight(scope, ...)`
- `Memory.get_insight(id)` → `Memory.get_insight(scope, id)`

#### 3. Dashboard Decisions LiveView

**File**: `lib/pop_stash_web/live/dashboard/decisions_live.ex`

Update all calls:
- `Memory.list_decisions(project_id)` → `Memory.list_decisions(scope, project_id)`
- `Memory.create_decision(...)` → `Memory.create_decision(scope, ...)`

#### 4. Dashboard Activity LiveView

**File**: `lib/pop_stash_web/live/dashboard/activity_live.ex`

Update all calls:
- `Activity.list_recent()` → `Activity.list_recent(scope)`

#### 5. All Other Dashboard LiveViews

Apply the same pattern to any other dashboard LiveViews.

### Example: Complete Projects LiveView Update

**File**: `lib/pop_stash_web/live/dashboard/projects_live.ex`

```elixir
defmodule PopStashWeb.Dashboard.ProjectsLive do
  use PopStashWeb, :live_view

  alias PopStash.Projects

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if connected?(socket) do
      # Subscribe to org-specific events only
      Phoenix.PubSub.subscribe(PopStash.PubSub, "org:#{scope.org_id}:projects:events")
    end

    socket =
      socket
      |> assign(:page_title, "Projects")
      |> load_projects()

    {:ok, socket}
  end

  defp load_projects(socket) do
    scope = socket.assigns.current_scope
    projects = Projects.list(scope)
    assign(socket, :projects, projects)
  end

  def handle_event("create", %{"name" => name}, socket) do
    scope = socket.assigns.current_scope

    case Projects.create(scope, name) do
      {:ok, _project} ->
        {:noreply,
         socket
         |> put_flash(:info, "Project created")
         |> load_projects()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to create project")}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope

    case Projects.delete(scope, id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Project deleted")
         |> load_projects()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete project")}
    end
  end

  # PubSub handlers
  def handle_info({:project_created, _}, socket) do
    {:noreply, load_projects(socket)}
  end

  def handle_info({:project_updated, _}, socket) do
    {:noreply, load_projects(socket)}
  end

  def handle_info({:project_deleted, _}, socket) do
    {:noreply, load_projects(socket)}
  end
end
```

## Verification

```bash
# Start server
mix phx.server

# Login and select org
# Visit dashboard pages and verify:
# - Projects page loads
# - Can create project
# - Can edit project
# - Can delete project
# - Same for insights, decisions, activity

# Test org isolation:
# - Create second org
# - Switch between orgs
# - Verify different data shown for each org
```

## Tests

Update all LiveView tests to include scope:

**File**: `test/pop_stash_web/live/dashboard/projects_live_test.exs`

```elixir
defmodule PopStashWeb.Dashboard.ProjectsLiveTest do
  use PopStashWeb.ConnCase
  import Phoenix.LiveViewTest

  setup do
    org = insert(:organization)
    user = insert(:user, selected_org_id: org.id)
    insert(:org_member, org_id: org.id, user_id: user.id, role: "member")

    conn = log_in_user(build_conn(), user)

    {:ok, conn: conn, org: org, user: user}
  end

  test "lists projects for current org only", %{conn: conn, org: org} do
    project1 = insert(:project, org_id: org.id, name: "My Project")

    # Create project in different org (should not appear)
    other_org = insert(:organization)
    insert(:project, org_id: other_org.id, name: "Other Project")

    {:ok, _view, html} = live(conn, ~p"/projects")

    assert html =~ "My Project"
    refute html =~ "Other Project"
  end

  test "can create project in current org", %{conn: conn, org: org} do
    {:ok, view, _html} = live(conn, ~p"/projects")

    view
    |> form("#project-form", name: "New Project")
    |> render_submit()

    # Verify project created in correct org
    project = PopStash.Repo.get_by(PopStash.Projects.Project, name: "New Project")
    assert project.org_id == org.id
  end
end
```

## Dependencies
- Step 4 completed (Contexts accept Scope parameter)
- Step 5 completed (OrgPlug assigns current_scope)

## Next Step
Step 7 will add comprehensive testing and polish.

## Notes
- **Scope in function heads**: Contexts accept `%Scope{}` directly — no indirection layer
- **PubSub topics org-scoped**: All PubSub subscriptions/broadcasts include org_id (handled in Step 4 contexts)
- **Update PubSub subscriptions**: Change LiveView subscriptions from `"projects:events"` to `"org:#{org_id}:projects:events"`
