# Step 6: LiveView Show (Detail View)

## Overview
Create the diagram detail page showing the rendered diagram, metadata, and actions.

## Context
The show page renders the mermaid diagram visually using the component from Step 4, displays metadata, allows status changes, and shows related diagrams with the same title.

## Implementation

**File:** `lib/pop_stash_web/live/diagram_live/show.ex`

```elixir
defmodule PopStashWeb.DiagramLive.Show do
  use PopStashWeb, :live_view

  import PopStashWeb.DiagramComponents

  alias PopStash.Memory

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(PopStash.PubSub, "memory:events")
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _url, socket) do
    case Memory.get_diagram(id) do
      {:ok, diagram} ->
        socket =
          socket
          |> assign(:page_title, diagram.title)
          |> assign(:diagram, diagram)
          |> load_related_diagrams(diagram)

        {:noreply, socket}

      {:error, :not_found} ->
        socket =
          socket
          |> put_flash(:error, "Diagram not found")
          |> redirect(to: ~p"/diagrams")

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("change_status", %{"status" => status}, socket) do
    case Memory.update_diagram_status(socket.assigns.diagram.id, status) do
      {:ok, updated_diagram} ->
        socket =
          socket
          |> assign(:diagram, updated_diagram)
          |> put_flash(:info, "Status updated to #{status}")

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update status")}
    end
  end

  def handle_event("delete", _params, socket) do
    case Memory.delete_diagram(socket.assigns.diagram.id) do
      :ok ->
        socket =
          socket
          |> put_flash(:info, "Diagram deleted successfully")
          |> redirect(to: ~p"/diagrams")

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete diagram")}
    end
  end

  # PubSub handlers
  @impl true
  def handle_info({:diagram_status_updated, updated_diagram}, socket) do
    if updated_diagram.id == socket.assigns.diagram.id do
      {:noreply, assign(socket, :diagram, updated_diagram)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:diagram_deleted, diagram_id}, socket) do
    if diagram_id == socket.assigns.diagram.id do
      socket =
        socket
        |> put_flash(:info, "This diagram was deleted")
        |> redirect(to: ~p"/diagrams")

      {:noreply, socket}
    else
      # Might be a related diagram
      {:noreply, load_related_diagrams(socket, socket.assigns.diagram)}
    end
  end

  def handle_info({:diagram_created, _diagram}, socket) do
    # Reload related in case a new version was created
    {:noreply, load_related_diagrams(socket, socket.assigns.diagram)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp load_related_diagrams(socket, diagram) do
    project_id = socket.assigns.current_scope.project.id

    related =
      Memory.get_diagrams_by_title(project_id, diagram.title)
      |> Enum.reject(&(&1.id == diagram.id))

    assign(socket, :related_diagrams, related)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mb-4">
        <.link navigate={~p"/diagrams"} class="text-blue-600 hover:underline">
          ← Back to Diagrams
        </.link>
      </div>

      <.page_header title={@diagram.title}>
        <:badge>
          <.badge color={status_color(@diagram.status)}>
            <%= @diagram.status %>
          </.badge>
        </:badge>
        <:actions>
          <form phx-change="change_status" class="inline-block">
            <.input
              type="select"
              name="status"
              value={@diagram.status}
              options={["draft", "active", "deprecated"]}
              label="Status"
            />
          </form>

          <.link
            phx-click="delete"
            data-confirm="Are you sure you want to delete this diagram?"
            class="button-danger"
          >
            Delete
          </.link>
        </:actions>
      </.page_header>

      <div class="space-y-6">
        <%!-- Summary Card --%>
        <.card>
          <:header>Summary</:header>
          <p class="text-gray-700"><%= @diagram.summary %></p>
        </.card>

        <%!-- Rendered Diagram --%>
        <.card>
          <:header>Diagram</:header>
          <.mermaid_diagram content={@diagram.content} class="my-4" />
        </.card>

        <%!-- Raw Content (Collapsible) --%>
        <details class="border rounded-lg">
          <summary class="px-4 py-3 cursor-pointer font-medium hover:bg-gray-50">
            View Mermaid Source
          </summary>
          <div class="px-4 py-3 bg-gray-50">
            <pre class="text-sm overflow-x-auto"><code><%= @diagram.content %></code></pre>
          </div>
        </details>

        <%!-- Metadata Card --%>
        <.card>
          <:header>Metadata</:header>
          <dl class="grid grid-cols-2 gap-4">
            <div>
              <dt class="text-sm font-medium text-gray-500">ID</dt>
              <dd class="mt-1 text-sm text-gray-900 font-mono"><%= @diagram.id %></dd>
            </div>

            <div>
              <dt class="text-sm font-medium text-gray-500">Type</dt>
              <dd class="mt-1 text-sm text-gray-900"><%= @diagram.diagram_type || "Unspecified" %></dd>
            </div>

            <div>
              <dt class="text-sm font-medium text-gray-500">Created</dt>
              <dd class="mt-1 text-sm text-gray-900">
                <.timestamp datetime={@diagram.inserted_at} />
              </dd>
            </div>

            <div>
              <dt class="text-sm font-medium text-gray-500">Updated</dt>
              <dd class="mt-1 text-sm text-gray-900">
                <.timestamp datetime={@diagram.updated_at} />
              </dd>
            </div>

            <%= if @diagram.tags != [] do %>
              <div class="col-span-2">
                <dt class="text-sm font-medium text-gray-500">Tags</dt>
                <dd class="mt-1">
                  <.tag_badges tags={@diagram.tags} />
                </dd>
              </div>
            <% end %>

            <%= if @diagram.files != [] do %>
              <div class="col-span-2">
                <dt class="text-sm font-medium text-gray-500">Related Files</dt>
                <dd class="mt-1 text-sm text-gray-900">
                  <ul class="list-disc list-inside space-y-1">
                    <%= for file <- @diagram.files do %>
                      <li class="font-mono text-sm"><%= file %></li>
                    <% end %>
                  </ul>
                </dd>
              </div>
            <% end %>
          </dl>
        </.card>

        <%!-- Related Diagrams --%>
        <%= if @related_diagrams != [] do %>
          <.card>
            <:header>Other Diagrams with This Title</:header>
            <ul class="divide-y">
              <%= for related <- @related_diagrams do %>
                <li class="py-3">
                  <div class="flex items-center justify-between">
                    <div>
                      <.link
                        navigate={~p"/diagrams/#{related.id}"}
                        class="text-blue-600 hover:underline"
                      >
                        <%= related.title %>
                      </.link>
                      <.badge color={status_color(related.status)} class="ml-2">
                        <%= related.status %>
                      </.badge>
                    </div>
                    <.timestamp datetime={related.inserted_at} />
                  </div>
                  <p class="text-sm text-gray-600 mt-1"><%= related.summary %></p>
                </li>
              <% end %>
            </ul>
          </.card>
        <% end %>
      </div>
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

# Create a test diagram first (via IEx or UI)
alias PopStash.Memory

{:ok, diagram} = Memory.create_diagram(
  "project-id",
  "Test Flow",
  """
  graph TD
    A[Start] --> B[Process]
    B --> C[End]
  """,
  summary: "A simple test flow",
  diagram_type: "flowchart",
  status: "active",
  tags: ["test", "example"],
  files: ["lib/my_app/test.ex"]
)

# Navigate to http://localhost:4000/diagrams/:id

# Test:
1. Diagram renders visually (mermaid SVG)
2. Summary displayed in card
3. Status badge shows correct color
4. Change status dropdown → updates immediately
5. Metadata section shows all fields
6. Tags display as badges
7. Files list shows correctly
8. "View Mermaid Source" details expands/collapses
9. Back link works
10. Delete prompts for confirmation and redirects
11. Real-time: update status in another tab, see update
12. Create another diagram with same title → appears in "Related" section
```

### Key Features to Verify

- ✓ Mermaid diagram renders correctly
- ✓ Status badge color-coded
- ✓ Status can be changed inline
- ✓ All metadata displays correctly
- ✓ Tags and files conditionally shown
- ✓ Related diagrams section (if any exist)
- ✓ Delete confirmation
- ✓ Real-time updates via PubSub
- ✓ Navigation back to index works
- ✓ Collapsible raw content

## Tests

**File:** `test/pop_stash_web/live/diagram_live/show_test.exs`

```elixir
defmodule PopStashWeb.DiagramLive.ShowTest do
  use PopStashWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias PopStash.Memory

  setup do
    user = insert(:user)
    project = insert(:project)
    conn = log_in_user(build_conn(), user, project.id)

    {:ok, diagram} =
      Memory.create_diagram(
        project.id,
        "Test Diagram",
        "graph TD\n  A --> B",
        summary: "Test summary",
        status: "active",
        diagram_type: "flowchart",
        tags: ["test", "example"],
        files: ["lib/test.ex"]
      )

    %{conn: conn, project: project, diagram: diagram}
  end

  describe "show page" do
    test "displays diagram details", %{conn: conn, diagram: diagram} do
      {:ok, view, _html} = live(conn, ~p"/diagrams/#{diagram.id}")

      assert render(view) =~ "Test Diagram"
      assert render(view) =~ "Test summary"
      assert render(view) =~ "flowchart"
      assert has_element?(view, "[phx-hook='.MermaidDiagram']")
    end

    test "displays status badge", %{conn: conn, diagram: diagram} do
      {:ok, view, _html} = live(conn, ~p"/diagrams/#{diagram.id}")

      html = render(view)
      assert html =~ "active"
      assert html =~ ~r/badge.*green|green.*badge/i
    end

    test "displays metadata fields", %{conn: conn, diagram: diagram} do
      {:ok, view, _html} = live(conn, ~p"/diagrams/#{diagram.id}")

      html = render(view)
      assert html =~ diagram.id
      assert html =~ "flowchart"
      assert html =~ "Created"
      assert html =~ "Updated"
    end

    test "displays tags when present", %{conn: conn, diagram: diagram} do
      {:ok, view, _html} = live(conn, ~p"/diagrams/#{diagram.id}")

      html = render(view)
      assert html =~ "test"
      assert html =~ "example"
    end

    test "displays files when present", %{conn: conn, diagram: diagram} do
      {:ok, view, _html} = live(conn, ~p"/diagrams/#{diagram.id}")

      assert render(view) =~ "lib/test.ex"
    end

    test "shows mermaid source in collapsible section", %{conn: conn, diagram: diagram} do
      {:ok, view, _html} = live(conn, ~p"/diagrams/#{diagram.id}")

      html = render(view)
      assert html =~ "View Mermaid Source"
      assert html =~ "graph TD"
      assert html =~ "A --> B"
    end

    test "redirects when diagram not found", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/diagrams/#{Ecto.UUID.generate()}")

      assert_redirect(view, ~p"/diagrams")
      assert Phoenix.Flash.get(view.assigns.flash, :error) =~ "not found"
    end
  end

  describe "status change" do
    test "updates diagram status", %{conn: conn, diagram: diagram} do
      {:ok, view, _html} = live(conn, ~p"/diagrams/#{diagram.id}")

      # Change status to deprecated
      view
      |> element("form[phx-change='change_status']")
      |> render_change(%{"status" => "deprecated"})

      assert render(view) =~ "Status updated to deprecated"

      # Verify in database
      {:ok, updated} = Memory.get_diagram(diagram.id)
      assert updated.status == "deprecated"
    end

    test "shows error on failed status update", %{conn: conn, diagram: diagram} do
      {:ok, view, _html} = live(conn, ~p"/diagrams/#{diagram.id}")

      # Try invalid status (this should be caught by validation)
      view
      |> element("form[phx-change='change_status']")
      |> render_change(%{"status" => "invalid"})

      assert render(view) =~ "Failed to update status"
    end
  end

  describe "delete" do
    test "deletes diagram and redirects", %{conn: conn, diagram: diagram} do
      {:ok, view, _html} = live(conn, ~p"/diagrams/#{diagram.id}")

      view
      |> element("a[phx-click='delete']")
      |> render_click()

      assert_redirect(view, ~p"/diagrams")
      assert {:error, :not_found} = Memory.get_diagram(diagram.id)
    end
  end

  describe "navigation" do
    test "back link navigates to index", %{conn: conn, diagram: diagram} do
      {:ok, view, _html} = live(conn, ~p"/diagrams/#{diagram.id}")

      assert has_element?(view, "a[href='/diagrams']")
    end
  end

  describe "related diagrams" do
    test "shows other diagrams with same title", %{conn: conn, project: project, diagram: diagram} do
      # Create another diagram with same title
      {:ok, version2} =
        Memory.create_diagram(
          project.id,
          "Test Diagram",
          "graph TD\n  X --> Y",
          summary: "Version 2",
          status: "draft"
        )

      {:ok, view, _html} = live(conn, ~p"/diagrams/#{diagram.id}")

      html = render(view)
      assert html =~ "Other Diagrams with This Title"
      assert html =~ "Version 2"
      assert html =~ "draft"

      # Original diagram should not be in related list
      refute html =~ ~r/#{diagram.id}/
    end

    test "hides related section when no other diagrams", %{conn: conn, diagram: diagram} do
      {:ok, view, _html} = live(conn, ~p"/diagrams/#{diagram.id}")

      refute render(view) =~ "Other Diagrams with This Title"
    end
  end

  describe "real-time updates" do
    test "updates when diagram status changes externally", %{conn: conn, diagram: diagram} do
      {:ok, view, _html} = live(conn, ~p"/diagrams/#{diagram.id}")

      assert render(view) =~ "active"

      # Update status externally
      {:ok, _updated} = Memory.update_diagram_status(diagram.id, "draft")

      :timer.sleep(100)

      assert render(view) =~ "draft"
    end

    test "redirects when diagram deleted externally", %{conn: conn, diagram: diagram} do
      {:ok, view, _html} = live(conn, ~p"/diagrams/#{diagram.id}")

      # Delete externally
      :ok = Memory.delete_diagram(diagram.id)

      :timer.sleep(100)

      assert_redirect(view, ~p"/diagrams")
      assert Phoenix.Flash.get(view.assigns.flash, :info) =~ "deleted"
    end

    test "reloads related diagrams when new diagram created", %{
      conn: conn,
      project: project,
      diagram: diagram
    } do
      {:ok, view, _html} = live(conn, ~p"/diagrams/#{diagram.id}")

      # Initially no related diagrams
      refute render(view) =~ "Other Diagrams with This Title"

      # Create another with same title
      {:ok, _version2} =
        Memory.create_diagram(
          project.id,
          "Test Diagram",
          "content",
          summary: "New version"
        )

      :timer.sleep(100)

      assert render(view) =~ "Other Diagrams with This Title"
      assert render(view) =~ "New version"
    end

    test "ignores updates for different diagrams", %{conn: conn, project: project, diagram: diagram} do
      {:ok, view, _html} = live(conn, ~p"/diagrams/#{diagram.id}")

      # Create a different diagram
      {:ok, other} =
        Memory.create_diagram(
          project.id,
          "Other Diagram",
          "content",
          summary: "different"
        )

      # Update the other diagram
      {:ok, _updated} = Memory.update_diagram_status(other.id, "deprecated")

      :timer.sleep(100)

      # Our diagram should still show active
      assert render(view) =~ "active"
      refute render(view) =~ "deprecated"
    end
  end
end
```

**Run tests:**
```bash
mix test test/pop_stash_web/live/diagram_live/show_test.exs
```

**Note:** These tests assume:
- A `log_in_user/3` helper exists
- Factory with `:user` and `:project` fixtures
- Existing components like `.card`, `.badge`, `.timestamp`
- The mermaid component from Step 4 is available

## Dependencies
- Step 0-1 completed (schema and context exist)
- Step 4 completed (Mermaid component exists)
- Existing LiveView components (`.card`, `.badge`, `.timestamp`, etc.)
