# Step 6: Update Dashboard LiveViews

## Objective

Update all dashboard LiveViews to use scoped context calls (`scope` from `socket.assigns.current_scope`) and org-scoped PubSub topics.

## Prerequisites

- Step 4 completed (contexts accept Scope)
- Step 5 completed (OrgPlug assigns `current_scope` to socket)

## Implementation

### Pattern

Every dashboard LiveView follows this transformation:

**Before** (current code):
```elixir
def mount(_params, _session, socket) do
  projects = Projects.list()
  {:ok, assign(socket, projects: projects)}
end

def handle_event("delete", %{"id" => id}, socket) do
  Projects.delete(id)
end
```

**After**:
```elixir
def mount(_params, _session, socket) do
  scope = socket.assigns.current_scope
  projects = Projects.list(scope)
  {:ok, assign(socket, projects: projects)}
end

def handle_event("delete", %{"id" => id}, socket) do
  scope = socket.assigns.current_scope
  Projects.delete(scope, id)
end
```

### Files to Update

#### 1. HomeLive

**File**: `/workspace/lib/pop_stash_web/dashboard/live/home_live.ex`

Changes:
- `Projects.list()` -> `Projects.list(scope)`
- `Memory.list_insights(project_id)` -> `Memory.list_insights(scope, project_id)`
- `Memory.list_decisions(project_id)` -> `Memory.list_decisions(scope, project_id)`
- `Activity.list_recent(opts)` -> `Activity.list_recent(scope, opts)`
- PubSub subscribe: `"memory:events"` -> `"org:#{scope.org_id}:memory:events"`
- Extract `scope` from `socket.assigns.current_scope` in mount and event handlers

The `load_stats/1` function has an N+1 problem (iterating projects and calling `list_insights` for each). This is a pre-existing issue, not introduced by this step. Flag it but do not fix it here.

#### 2. ProjectLive.Index

**File**: `/workspace/lib/pop_stash_web/dashboard/live/project_live/index.ex`

Changes:
- `Projects.list()` -> `Projects.list(scope)`
- `Projects.delete(id)` -> `Projects.delete(scope, id)`
- `Memory.list_insights(project.id)` -> `Memory.list_insights(scope, project.id)` (in `enrich_project_with_stats`)
- `Memory.list_decisions(project.id)` -> `Memory.list_decisions(scope, project.id)`

#### 3. ProjectLive.Show

**File**: `/workspace/lib/pop_stash_web/dashboard/live/project_live/show.ex`

Changes:
- `Projects.get(id)` -> `Projects.get(scope, id)`
- All Memory calls to include scope as first arg

#### 4. ProjectLive.FormComponent

**File**: `/workspace/lib/pop_stash_web/dashboard/live/project_live/form_component.ex`

Changes:
- `Projects.create(name, opts)` -> `Projects.create(scope, name, opts)`
- The FormComponent needs `current_scope` passed as an assign from the parent LiveView

#### 5. InsightLive.Index, InsightLive.Show, InsightLive.FormComponent

**Files**:
- `/workspace/lib/pop_stash_web/dashboard/live/insight_live/index.ex`
- `/workspace/lib/pop_stash_web/dashboard/live/insight_live/show.ex`
- `/workspace/lib/pop_stash_web/dashboard/live/insight_live/form_component.ex`

Changes:
- All `Memory.create_insight(project_id, ...)` -> `Memory.create_insight(scope, project_id, ...)`
- All `Memory.list_insights(project_id, ...)` -> `Memory.list_insights(scope, project_id, ...)`
- All `Memory.update_insight(id, ...)` -> `Memory.update_insight(scope, id, ...)`
- All `Memory.get_insight_by_title(project_id, title)` -> `Memory.get_insight_by_title(scope, project_id, title)`

#### 6. DecisionLive.Index, DecisionLive.Show, DecisionLive.FormComponent

**Files**:
- `/workspace/lib/pop_stash_web/dashboard/live/decision_live/index.ex`
- `/workspace/lib/pop_stash_web/dashboard/live/decision_live/show.ex`
- `/workspace/lib/pop_stash_web/dashboard/live/decision_live/form_component.ex`

Changes:
- All `Memory.create_decision(project_id, ...)` -> `Memory.create_decision(scope, project_id, ...)`
- All `Memory.list_decisions(project_id, ...)` -> `Memory.list_decisions(scope, project_id, ...)`
- All `Memory.get_decision(id)` -> `Memory.get_decision(scope, id)`

#### 7. ActivityFeedComponent

**File**: `/workspace/lib/pop_stash_web/dashboard/live/activity_feed_component.ex`

This is a LiveComponent that receives items as an assign. It should not need context changes since it only renders data. However, check if it calls any context functions directly.

### PubSub Topic Updates

All LiveViews that subscribe to PubSub must update their topic:

```elixir
# Before
Phoenix.PubSub.subscribe(PopStash.PubSub, "memory:events")

# After
scope = socket.assigns.current_scope
Phoenix.PubSub.subscribe(PopStash.PubSub, "org:#{scope.org_id}:memory:events")
```

### Passing current_scope to LiveComponents

LiveComponents that need to call context functions (FormComponents) must receive `current_scope` as an assign:

```elixir
<.live_component
  module={PopStashWeb.Dashboard.ProjectLive.FormComponent}
  id={:new}
  project={@project}
  action={:new}
  current_scope={@current_scope}
  return_to={~p"/projects"}
/>
```

## Verification

```bash
mix phx.server

# Login, select org, then:
# 1. Visit / (HomeLive) -- verify stats load
# 2. Visit /projects -- verify project list
# 3. Create project -- verify it gets org_id
# 4. Visit /insights -- verify insight list
# 5. Create insight -- verify it gets org_id
# 6. Visit /decisions -- verify decision list
# 7. Create decision -- verify it gets org_id
# 8. Switch org via sidebar -- verify different data shown
# 9. Create content in org A, switch to org B, verify not visible
```

## Tests

Update existing LiveView tests to authenticate and set up org context.

**File**: `test/pop_stash_web/dashboard/home_live_test.exs`

```elixir
defmodule PopStashWeb.Dashboard.HomeLiveTest do
  use PopStashWeb.ConnCase
  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    %{user: user, org: org, scope: scope} = setup_org_context()
    Repo.update!(Ecto.Changeset.change(user, selected_org_id: org.id))
    conn = log_in_user(conn, user)

    {:ok, conn: conn, scope: scope, org: org}
  end

  test "renders dashboard overview", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "Dashboard"
  end

  test "shows only current org projects", %{conn: conn, scope: scope, org: org} do
    PopStash.Projects.create(scope, "My Project")

    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "My Project"
  end
end
```

**File**: `test/pop_stash_web/dashboard/project_live_test.exs`

```elixir
defmodule PopStashWeb.Dashboard.ProjectLiveTest do
  use PopStashWeb.ConnCase
  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    %{user: user, org: org, scope: scope} = setup_org_context()
    Repo.update!(Ecto.Changeset.change(user, selected_org_id: org.id))
    conn = log_in_user(conn, user)

    {:ok, conn: conn, scope: scope, org: org}
  end

  test "lists projects for current org only", %{conn: conn, scope: scope, org: org} do
    PopStash.Projects.create(scope, "Visible Project")

    # Create project in other org (should not appear)
    other_org = organization_fixture()
    Repo.insert_all("projects", [
      %{id: Ecto.UUID.generate(), name: "Hidden Project", org_id: other_org.id,
        tags: [], inserted_at: DateTime.utc_now(), updated_at: DateTime.utc_now()}
    ], skip_org_id: true)

    {:ok, _view, html} = live(conn, ~p"/projects")
    assert html =~ "Visible Project"
    refute html =~ "Hidden Project"
  end

  test "created project belongs to current org", %{conn: conn, org: org} do
    {:ok, view, _html} = live(conn, ~p"/projects/new")

    # Fill and submit the project form
    view
    |> form("#project-form", project: %{name: "New Project"})
    |> render_submit()

    project = Repo.one!(from p in PopStash.Projects.Project, where: p.name == "New Project")
    assert project.org_id == org.id
  end
end
```

## Dependencies

- Step 4 completed (contexts accept Scope)
- Step 5 completed (OrgPlug assigns current_scope)

## Important Notes

- **Do not change template structure or styling.** Only update the Elixir code in LiveViews to pass `scope` to context functions.
- **LiveComponents that call contexts** need `current_scope` passed as an assign from the parent.
- **PubSub topic format**: `"org:#{org_id}:memory:events"` -- matches what contexts broadcast in Step 4.
- **The `current_path` assign** is still set by each LiveView individually (not by OrgPlug). Do not remove these assigns.
- **Avoid changing test structure** -- update existing tests to add auth setup, do not rewrite tests from scratch.
