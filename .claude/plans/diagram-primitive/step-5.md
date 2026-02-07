# Step 5: LiveView Index (List View)

## Overview
Create the diagram index page for listing, filtering, and searching diagrams.

## Context
Follows the same patterns as insights and decisions index pages: project filter, status filter, search, PubSub subscriptions for real-time updates, and modal for creation.

## Implementation

**File:** `lib/pop_stash_web/live/diagram_live/index.ex`

```elixir
defmodule PopStashWeb.DiagramLive.Index do
  use PopStashWeb, :live_view

  alias PopStash.Memory
  alias PopStashWeb.DiagramLive.FormComponent

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(PopStash.PubSub, "memory:events")
    end

    socket =
      socket
      |> assign(:page_title, "Diagrams")
      |> assign(:selected_project_id, nil)
      |> assign(:status_filter, "active")
      |> assign(:search_query, "")
      |> load_diagrams()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, :diagram, nil)
  end

  defp apply_action(socket, :new, _params) do
    assign(socket, :diagram, %Memory.Diagram{})
  end

  @impl true
  def handle_event("filter_project", %{"project_id" => project_id}, socket) do
    project_id = if project_id == "", do: nil, else: project_id

    socket =
      socket
      |> assign(:selected_project_id, project_id)
      |> load_diagrams()

    {:noreply, socket}
  end

  def handle_event("filter_status", %{"status" => status}, socket) do
    status = if status == "all", do: nil, else: status

    socket =
      socket
      |> assign(:status_filter, status)
      |> load_diagrams()

    {:noreply, socket}
  end

  def handle_event("search", %{"query" => query}, socket) do
    socket =
      socket
      |> assign(:search_query, query)
      |> load_diagrams()

    {:noreply, socket}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    case Memory.delete_diagram(id) do
      :ok ->
        {:noreply, put_flash(socket, :info, "Diagram deleted successfully")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete diagram")}
    end
  end

  def handle_event("change_status", %{"id" => id, "status" => status}, socket) do
    case Memory.get_diagram(id) do
      {:ok, diagram} ->
        case Memory.update_diagram_status(diagram.id, status) do
          {:ok, _} ->
            {:noreply, put_flash(socket, :info, "Status updated to #{status}")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to update status")}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Diagram not found")}
    end
  end

  # PubSub handlers
  @impl true
  def handle_info({:diagram_created, _diagram}, socket) do
    {:noreply, load_diagrams(socket)}
  end

  def handle_info({:diagram_status_updated, _diagram}, socket) do
    {:noreply, load_diagrams(socket)}
  end

  def handle_info({:diagram_deleted, _diagram_id}, socket) do
    {:noreply, load_diagrams(socket)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp load_diagrams(socket) do
    project_id = socket.assigns.current_scope.project.id
    status = socket.assigns.status_filter
    query = socket.assigns.search_query

    diagrams =
      cond do
        query != "" ->
          case Memory.search_diagrams(project_id, query, status: status || "active") do
            {:ok, results} -> results
            {:error, _} -> []
          end

        true ->
          opts = if status, do: [status: status], else: []
          Memory.list_diagrams(project_id, opts)
      end

    assign(socket, :diagrams, diagrams)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.page_header title="Diagrams">
        <:actions>
          <.link patch={~p"/diagrams/new"} class="button-primary">
            New Diagram
          </.link>
        </:actions>
      </.page_header>

      <div class="space-y-4 mb-6">
        <div class="flex gap-4">
          <div class="flex-1">
            <form phx-change="search" phx-submit="search">
              <.input
                type="search"
                name="query"
                value={@search_query}
                placeholder="Search diagrams..."
                phx-debounce="300"
              />
            </form>
          </div>

          <div class="w-48">
            <form phx-change="filter_status">
              <.input
                type="select"
                name="status"
                value={@status_filter || "active"}
                options={[
                  {"All", "all"},
                  {"Draft", "draft"},
                  {"Active", "active"},
                  {"Deprecated", "deprecated"}
                ]}
              />
            </form>
          </div>
        </div>
      </div>

      <%= if @diagrams == [] do %>
        <.empty_state>
          <:icon>📊</:icon>
          <:title>No diagrams yet</:title>
          <:description>
            <%= if @search_query != "" do %>
              No diagrams match your search.
            <% else %>
              Create your first diagram to document your architecture.
            <% end %>
          </:description>
          <:action>
            <.link patch={~p"/diagrams/new"} class="button-primary">
              Create Diagram
            </.link>
          </:action>
        </.empty_state>
      <% else %>
        <.data_table>
          <:col :let={diagram} label="Title">
            <.link navigate={~p"/diagrams/#{diagram.id}"} class="font-medium text-blue-600 hover:underline">
              <%= diagram.title %>
            </.link>
          </:col>

          <:col :let={diagram} label="Summary">
            <span class="text-gray-600"><%= String.slice(diagram.summary, 0..100) %></span>
          </:col>

          <:col :let={diagram} label="Type">
            <%= diagram.diagram_type || "—" %>
          </:col>

          <:col :let={diagram} label="Status">
            <.badge color={status_color(diagram.status)}>
              <%= diagram.status %>
            </.badge>
          </:col>

          <:col :let={diagram} label="Updated">
            <.timestamp datetime={diagram.updated_at} />
          </:col>

          <:col :let={diagram} label="Actions">
            <div class="flex gap-2">
              <form phx-change="change_status">
                <input type="hidden" name="id" value={diagram.id} />
                <.input
                  type="select"
                  name="status"
                  value={diagram.status}
                  options={["draft", "active", "deprecated"]}
                  class="text-sm"
                />
              </form>

              <.link
                phx-click="delete"
                phx-value-id={diagram.id}
                data-confirm="Are you sure?"
                class="text-red-600 hover:text-red-800"
              >
                Delete
              </.link>
            </div>
          </:col>
        </.data_table>
      <% end %>

      <.modal :if={@live_action == :new} id="diagram-modal" show on_cancel={JS.patch(~p"/diagrams")}>
        <.live_component
          module={FormComponent}
          id="new-diagram"
          diagram={@diagram}
          action={@live_action}
          project_id={@current_scope.project.id}
          patch={~p"/diagrams"}
        />
      </.modal>
    </Layouts.app>
    """
  end

  defp status_color("draft"), do: :gray
  defp status_color("active"), do: :green
  defp status_color("deprecated"), do: :red
end
```

## Verification

### Manual Testing

```bash
# Start server
iex -S mix phx.server

# Navigate to http://localhost:4000/diagrams

# Test:
1. Page loads with empty state (if no diagrams)
2. Click "New Diagram" → modal opens
3. Create a diagram (continue in Step 7 for form)
4. Diagram appears in list
5. Change status dropdown → updates immediately
6. Search for diagram by title/summary
7. Filter by status
8. Delete diagram → prompts for confirmation
9. Real-time updates: open in two tabs, create in one, see in other
```

### Key Features to Verify

- ✓ Project filtering works
- ✓ Status filtering (All/Draft/Active/Deprecated)
- ✓ Search with debounce (300ms)
- ✓ Status badge colors (gray/green/red)
- ✓ Delete confirmation prompt
- ✓ Real-time updates via PubSub
- ✓ Empty states for no results
- ✓ Modal opens for new diagram

## Tests

**File:** `test/pop_stash_web/live/diagram_live/index_test.exs`

```elixir
defmodule PopStashWeb.DiagramLive.IndexTest do
  use PopStashWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias PopStash.Memory

  setup do
    user = insert(:user)
    project = insert(:project)
    conn = log_in_user(build_conn(), user, project.id)

    %{conn: conn, project: project, user: user}
  end

  describe "index page" do
    test "renders diagram list", %{conn: conn, project: project} do
      {:ok, diagram} =
        Memory.create_diagram(
          project.id,
          "Test Diagram",
          "graph TD\n  A --> B",
          summary: "Test summary",
          status: "active"
        )

      {:ok, view, _html} = live(conn, ~p"/diagrams")

      assert has_element?(view, "#diagram-list")
      assert render(view) =~ "Test Diagram"
      assert render(view) =~ "Test summary"
    end

    test "shows empty state when no diagrams", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/diagrams")

      assert render(view) =~ "No diagrams yet"
      assert render(view) =~ "Create your first diagram"
    end

    test "filters diagrams by status", %{conn: conn, project: project} do
      {:ok, _draft} =
        Memory.create_diagram(project.id, "Draft", "content", summary: "draft", status: "draft")

      {:ok, _active} =
        Memory.create_diagram(project.id, "Active", "content",
          summary: "active",
          status: "active"
        )

      {:ok, view, _html} = live(conn, ~p"/diagrams")

      # Default filter is "active"
      assert render(view) =~ "Active"
      refute render(view) =~ "Draft"

      # Change to "draft"
      view
      |> element("form[phx-change='filter_status']")
      |> render_change(%{"status" => "draft"})

      assert render(view) =~ "Draft"
      refute render(view) =~ "Active"

      # Change to "all"
      view
      |> element("form[phx-change='filter_status']")
      |> render_change(%{"status" => "all"})

      assert render(view) =~ "Draft"
      assert render(view) =~ "Active"
    end

    test "searches diagrams", %{conn: conn, project: project} do
      {:ok, _auth} =
        Memory.create_diagram(project.id, "Auth Flow", "content",
          summary: "authentication",
          status: "active"
        )

      {:ok, _data} =
        Memory.create_diagram(project.id, "Data Pipeline", "content",
          summary: "ETL pipeline",
          status: "active"
        )

      # Wait for indexing
      Process.sleep(200)

      {:ok, view, _html} = live(conn, ~p"/diagrams")

      # Search for "auth"
      view
      |> element("form[phx-change='search']")
      |> render_change(%{"query" => "auth"})

      assert render(view) =~ "Auth Flow"
      refute render(view) =~ "Data Pipeline"
    end

    test "deletes diagram with confirmation", %{conn: conn, project: project} do
      {:ok, diagram} =
        Memory.create_diagram(project.id, "To Delete", "content",
          summary: "will be deleted",
          status: "active"
        )

      {:ok, view, _html} = live(conn, ~p"/diagrams")

      assert render(view) =~ "To Delete"

      # Delete the diagram
      view
      |> element("a[phx-click='delete'][phx-value-id='#{diagram.id}']")
      |> render_click()

      refute render(view) =~ "To Delete"
      assert render(view) =~ "Diagram deleted successfully"
    end

    test "changes diagram status", %{conn: conn, project: project} do
      {:ok, diagram} =
        Memory.create_diagram(project.id, "Status Test", "content",
          summary: "status change test",
          status: "draft"
        )

      {:ok, view, _html} = live(conn, ~p"/diagrams")

      # Change status to active
      view
      |> element("form[phx-change='change_status']")
      |> render_change(%{"id" => diagram.id, "status" => "active"})

      assert render(view) =~ "Status updated to active"

      # Verify diagram status was updated
      {:ok, updated} = Memory.get_diagram(diagram.id)
      assert updated.status == "active"
    end

    test "opens modal for new diagram", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/diagrams")

      # Click "New Diagram" button
      view
      |> element("a[href='/diagrams/new']")
      |> render_click()

      assert_patch(view, ~p"/diagrams/new")
      assert has_element?(view, "#diagram-modal")
    end
  end

  describe "real-time updates" do
    test "receives diagram_created event", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/diagrams")

      # Create diagram (which broadcasts event)
      {:ok, _diagram} =
        Memory.create_diagram(project.id, "New Diagram", "content",
          summary: "created in real-time",
          status: "active"
        )

      # Give it a moment to process
      :timer.sleep(100)

      assert render(view) =~ "New Diagram"
    end

    test "receives diagram_status_updated event", %{conn: conn, project: project} do
      {:ok, diagram} =
        Memory.create_diagram(project.id, "Update Test", "content",
          summary: "status update",
          status: "draft"
        )

      {:ok, view, _html} = live(conn, ~p"/diagrams")

      # Ensure we're filtering by "all" to see drafts
      view
      |> element("form[phx-change='filter_status']")
      |> render_change(%{"status" => "all"})

      # Update status externally
      {:ok, _updated} = Memory.update_diagram_status(diagram.id, "active")

      :timer.sleep(100)

      # The list should refresh
      assert render(view) =~ "Update Test"
    end

    test "receives diagram_deleted event", %{conn: conn, project: project} do
      {:ok, diagram} =
        Memory.create_diagram(project.id, "Delete Test", "content",
          summary: "delete test",
          status: "active"
        )

      {:ok, view, _html} = live(conn, ~p"/diagrams")

      assert render(view) =~ "Delete Test"

      # Delete externally
      :ok = Memory.delete_diagram(diagram.id)

      :timer.sleep(100)

      refute render(view) =~ "Delete Test"
    end
  end

  describe "status badge colors" do
    test "draft diagrams show gray badge", %{conn: conn, project: project} do
      {:ok, _diagram} =
        Memory.create_diagram(project.id, "Draft", "content", summary: "draft", status: "draft")

      {:ok, view, _html} = live(conn, ~p"/diagrams")

      # Filter to show all
      view
      |> element("form[phx-change='filter_status']")
      |> render_change(%{"status" => "all"})

      html = render(view)
      assert html =~ "Draft"
      # Check for gray badge (implementation depends on your .badge component)
      assert html =~ ~r/badge.*gray|gray.*badge/i
    end

    test "active diagrams show green badge", %{conn: conn, project: project} do
      {:ok, _diagram} =
        Memory.create_diagram(project.id, "Active", "content",
          summary: "active",
          status: "active"
        )

      {:ok, view, _html} = live(conn, ~p"/diagrams")

      html = render(view)
      assert html =~ "Active"
      assert html =~ ~r/badge.*green|green.*badge/i
    end

    test "deprecated diagrams show red badge", %{conn: conn, project: project} do
      {:ok, _diagram} =
        Memory.create_diagram(project.id, "Deprecated", "content",
          summary: "deprecated",
          status: "deprecated"
        )

      {:ok, view, _html} = live(conn, ~p"/diagrams")

      # Filter to show all
      view
      |> element("form[phx-change='filter_status']")
      |> render_change(%{"status" => "all"})

      html = render(view)
      assert html =~ "Deprecated"
      assert html =~ ~r/badge.*red|red.*badge/i
    end
  end
end
```

**Run tests:**
```bash
mix test test/pop_stash_web/live/diagram_live/index_test.exs
```

**Note:** These tests assume:
- A `log_in_user/3` helper exists (from UserAuth)
- Factory with `:user` and `:project` fixtures
- Existing components like `.page_header`, `.data_table`, `.badge`
- Search indexing is fast or you may need to increase sleep times

## Dependencies
- Step 0-1 completed (schema and context exist)
- Existing LiveView components (`.page_header`, `.data_table`, `.badge`, etc.)
- Step 7 not yet done (FormComponent will be created)
