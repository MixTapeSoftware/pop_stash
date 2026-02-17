# Step 8: Router and Claude Hooks Configuration

## Overview
Add routes to the router and update Claude Code hooks to include diagrams in agent prompts.

## Context
Routes follow REST conventions. Claude hooks prompt agents to consider diagrams alongside insights and decisions when starting work and after completing tasks.

## Implementation

### 1. Add Routes

**File:** `lib/pop_stash_web/router.ex`

Find the authenticated routes section and add:

```elixir
# Inside the live_session with authentication
scope "/", PopStashWeb do
  pipe_through [:browser, :require_authenticated_user]

  live_session :authenticated,
    on_mount: [{PopStashWeb.UserAuth, :ensure_authenticated}] do

    # ... existing routes ...

    # Diagram routes
    live "/diagrams", DiagramLive.Index, :index
    live "/diagrams/new", DiagramLive.Index, :new
    live "/diagrams/:id", DiagramLive.Show, :show
    live "/diagrams/:id/edit", DiagramLive.Show, :edit
  end
end
```

### 2. Update Navigation (Optional)

If you have a navigation menu, add diagrams:

**File:** `lib/pop_stash_web/components/layouts.ex` (or wherever nav is defined)

```elixir
<nav class="flex gap-4">
  <.link navigate={~p"/insights"} class="nav-link">Insights</.link>
  <.link navigate={~p"/decisions"} class="nav-link">Decisions</.link>
  <.link navigate={~p"/diagrams"} class="nav-link">Diagrams</.link>
</nav>
```

### 3. Update Claude Code Hooks

**File:** `.claude/settings.json` (or `.claude/settings.local.json`)

Update or add the hooks configuration:

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
- **SessionStart** - Reminds agents to check existing knowledge (including diagrams)
- **Stop** - Prompts agents to document architectural changes as diagrams

This ensures diagrams are treated as a first-class knowledge primitive.

## Verification

### Test Routes

```bash
# Start server
iex -S mix phx.server

# Test each route manually:
curl http://localhost:4000/diagrams
# Should show index page (or redirect if not authenticated)

# In browser (authenticated):
http://localhost:4000/diagrams          # Index
http://localhost:4000/diagrams/new      # New modal
http://localhost:4000/diagrams/:id      # Show page
http://localhost:4000/diagrams/:id/edit # Edit modal (if implemented)
```

### Test Navigation

1. Navigate to `/diagrams`
2. Click navigation links (if added)
3. Verify all links work
4. Verify authentication required (logout and try accessing)

### Test Claude Hooks

```bash
# In Claude Code terminal

# Start a new session - should see prompt about checking decisions/insights/diagrams
# (The exact behavior depends on your Claude Code setup)

# Complete some work and stop
# Should see prompt about documenting insights/decisions/diagrams
```

### Verify Hook Configuration

```bash
# Check that hooks are loaded
cat .claude/settings.json

# Should see the SessionStart and Stop hooks with diagram references
```

## Tests

**File:** `test/pop_stash_web/controllers/diagram_routes_test.exs`

```elixir
defmodule PopStashWeb.DiagramRoutesTest do
  use PopStashWeb.ConnCase, async: true

  describe "diagram routes" do
    test "GET /diagrams requires authentication", %{conn: conn} do
      conn = get(conn, ~p"/diagrams")
      assert redirected_to(conn) =~ "/users/log_in"
    end

    test "GET /diagrams/:id requires authentication", %{conn: conn} do
      conn = get(conn, ~p"/diagrams/#{Ecto.UUID.generate()}")
      assert redirected_to(conn) =~ "/users/log_in"
    end

    test "authenticated user can access /diagrams", %{conn: conn} do
      user = insert(:user)
      project = insert(:project)
      conn = log_in_user(conn, user, project.id)

      conn = get(conn, ~p"/diagrams")
      assert html_response(conn, 200) =~ "Diagrams"
    end
  end

  describe "route helpers" do
    test "diagrams index route exists" do
      assert ~p"/diagrams" == "/diagrams"
    end

    test "diagrams show route exists" do
      id = Ecto.UUID.generate()
      assert ~p"/diagrams/#{id}" == "/diagrams/#{id}"
    end

    test "diagrams new route exists" do
      assert ~p"/diagrams/new" == "/diagrams/new"
    end
  end
end
```

**Run tests:**
```bash
mix test test/pop_stash_web/controllers/diagram_routes_test.exs
```

**Note:** These tests verify:
- Routes require authentication (redirect to login when not authenticated)
- Routes are accessible when authenticated
- Route helpers are defined correctly

The detailed functionality of each route is tested in the LiveView tests (steps 5, 6, 7).

## Dependencies
- Steps 0-7 completed (all LiveViews implemented)
- Existing router with authentication setup

## Troubleshooting

**Routes not working:**
- Verify LiveView modules are defined correctly
- Check authentication is set up
- Restart server after adding routes

**Navigation not showing:**
- Verify you added nav links to the correct template
- Check CSS classes are defined

**Claude hooks not triggering:**
- Verify JSON is valid (use a JSON validator)
- Check `.claude/settings.json` or `.claude/settings.local.json` exists
- Restart Claude Code session
- Check Claude Code version supports hooks

**Authentication errors:**
- Verify routes are in correct `live_session` block
- Check `on_mount` is configured
- Ensure `current_scope` assign exists
