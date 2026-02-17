# Step 7: Form Component (Create/Edit Modal)

## Overview
Create the form component for creating and editing diagrams in a modal.

## Context
The form follows LiveView patterns with client-side validation via `phx-change`, proper error handling, and broadcasts on success. It's used as a modal from the index page.

## Implementation

**File:** `lib/pop_stash_web/live/diagram_live/form_component.ex`

```elixir
defmodule PopStashWeb.DiagramLive.FormComponent do
  use PopStashWeb, :live_component

  alias PopStash.Memory

  @impl true
  def update(%{diagram: diagram} = assigns, socket) do
    changeset = change_diagram(diagram)

    socket =
      socket
      |> assign(assigns)
      |> assign(:changeset, changeset)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"diagram" => diagram_params}, socket) do
    changeset =
      socket.assigns.diagram
      |> change_diagram(diagram_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  def handle_event("save", %{"diagram" => diagram_params}, socket) do
    save_diagram(socket, socket.assigns.action, diagram_params)
  end

  defp save_diagram(socket, :new, params) do
    # Parse arrays from textarea (one per line)
    params =
      params
      |> parse_array_field("tags")
      |> parse_array_field("files")

    opts = [
      summary: params["summary"],
      diagram_type: params["diagram_type"],
      status: params["status"] || "draft",
      tags: params["tags"] || [],
      files: params["files"] || []
    ]

    case Memory.create_diagram(
           socket.assigns.project_id,
           params["title"],
           params["content"],
           opts
         ) do
      {:ok, diagram} ->
        socket =
          socket
          |> put_flash(:info, "Diagram created successfully")
          |> push_navigate(to: socket.assigns.patch)

        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  defp change_diagram(diagram, attrs \\ %{}) do
    # Create a virtual changeset for form validation
    types = %{
      title: :string,
      summary: :string,
      content: :string,
      diagram_type: :string,
      status: :string,
      tags: :string,
      files: :string
    }

    {diagram, types}
    |> Ecto.Changeset.cast(attrs, Map.keys(types))
    |> Ecto.Changeset.validate_required([:title, :summary, :content])
    |> Ecto.Changeset.validate_length(:title, min: 1, max: 255)
  end

  defp parse_array_field(params, field) do
    case params[field] do
      nil ->
        params

      "" ->
        Map.put(params, field, [])

      value when is_binary(value) ->
        list =
          value
          |> String.split("\n")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        Map.put(params, field, list)

      list when is_list(list) ->
        params
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        <%= if @action == :new, do: "New Diagram", else: "Edit Diagram" %>
      </.header>

      <.simple_form
        for={@changeset}
        id="diagram-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@changeset[:title]} type="text" label="Title" required />

        <.input
          field={@changeset[:summary]}
          type="textarea"
          label="Summary"
          placeholder="Brief description for search..."
          rows="2"
          required
        />

        <.input
          field={@changeset[:content]}
          type="textarea"
          label="Mermaid Content"
          placeholder="graph TD&#10;  A[Start] --> B[End]"
          rows="10"
          phx-hook="MonospaceTextarea"
          class="font-mono text-sm"
          required
        />

        <.input
          field={@changeset[:diagram_type]}
          type="text"
          label="Diagram Type"
          placeholder="e.g., sequence, flowchart, classDiagram"
        />

        <.input
          field={@changeset[:status]}
          type="select"
          label="Status"
          options={[
            {"Draft", "draft"},
            {"Active", "active"},
            {"Deprecated", "deprecated"}
          ]}
        />

        <.input
          field={@changeset[:tags]}
          type="textarea"
          label="Tags (one per line)"
          placeholder="authentication&#10;security"
          rows="3"
        />

        <.input
          field={@changeset[:files]}
          type="textarea"
          label="Related Files (one per line)"
          placeholder="lib/my_app/auth.ex&#10;lib/my_app/user.ex"
          rows="3"
        />

        <:actions>
          <.button phx-disable-with="Saving...">Save Diagram</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end
end
```

## Additional: Mermaid Syntax Helper (Optional)

Add a simple help section or link to Mermaid docs:

```elixir
<div class="mb-4 p-4 bg-blue-50 border border-blue-200 rounded">
  <p class="text-sm text-blue-800">
    <strong>Need help with Mermaid syntax?</strong>
    View the <a href="https://mermaid.js.org/intro/" target="_blank" class="underline">Mermaid documentation</a>.
  </p>
  <details class="mt-2">
    <summary class="text-sm cursor-pointer text-blue-700">Quick Examples</summary>
    <pre class="mt-2 text-xs bg-white p-2 rounded"><code>
# Flowchart
graph TD
  A[Start] --> B[Process]
  B --> C[End]

# Sequence Diagram
sequenceDiagram
  Alice->>John: Hello
  John-->>Alice: Hi!

# Class Diagram
classDiagram
  User <|-- Admin
    </code></pre>
  </details>
</div>
```

## Verification

### Manual Testing

```bash
# Start server
iex -S mix phx.server

# Navigate to http://localhost:4000/diagrams
# Click "New Diagram"

# Test validation:
1. Try to submit empty form → validation errors show
2. Fill only title → summary required error
3. Fill title and summary → content required error
4. Fill all required fields → form submits successfully

# Test field parsing:
1. Tags textarea with multiple lines → saves as array
2. Files textarea with multiple lines → saves as array
3. Empty tags/files → saves as empty array

# Test mermaid content:
1. Enter valid mermaid syntax
2. Submit and view → should render correctly
3. Enter invalid syntax
4. Submit and view → should show error message

# Test status:
1. Select "draft" → saves as draft
2. Select "active" → saves as active
3. Leave default → saves as draft

# Test close:
1. Click outside modal → closes and returns to index
2. Click X button → closes
3. After save → redirects to index with success flash
```

## Tests

**File:** `test/pop_stash_web/live/diagram_live/form_component_test.exs`

```elixir
defmodule PopStashWeb.DiagramLive.FormComponentTest do
  use PopStashWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias PopStash.Memory

  setup do
    user = insert(:user)
    project = insert(:project)
    conn = log_in_user(build_conn(), user, project.id)

    %{conn: conn, project: project}
  end

  describe "form rendering" do
    test "renders new diagram form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/diagrams/new")

      assert has_element?(view, "#diagram-form")
      assert has_element?(view, "input[name='diagram[title]']")
      assert has_element?(view, "textarea[name='diagram[summary]']")
      assert has_element?(view, "textarea[name='diagram[content]']")
      assert has_element?(view, "input[name='diagram[diagram_type]']")
      assert has_element?(view, "select[name='diagram[status]']")
      assert has_element?(view, "textarea[name='diagram[tags]']")
      assert has_element?(view, "textarea[name='diagram[files]']")
    end

    test "form has submit button", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/diagrams/new")

      assert has_element?(view, "button[type='submit']")
    end
  end

  describe "form validation" do
    test "validates required title field", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/diagrams/new")

      view
      |> form("#diagram-form", diagram: %{
        title: "",
        summary: "Test",
        content: "graph TD\n  A --> B"
      })
      |> render_change()

      assert render(view) =~ "can&#39;t be blank"
    end

    test "validates required summary field", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/diagrams/new")

      view
      |> form("#diagram-form", diagram: %{
        title: "Test",
        summary: "",
        content: "graph TD\n  A --> B"
      })
      |> render_change()

      assert render(view) =~ "can&#39;t be blank"
    end

    test "validates required content field", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/diagrams/new")

      view
      |> form("#diagram-form", diagram: %{
        title: "Test",
        summary: "Test summary",
        content: ""
      })
      |> render_change()

      assert render(view) =~ "can&#39;t be blank"
    end

    test "validates title length", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/diagrams/new")

      long_title = String.duplicate("a", 256)

      view
      |> form("#diagram-form", diagram: %{
        title: long_title,
        summary: "Test",
        content: "graph TD\n  A --> B"
      })
      |> render_change()

      assert render(view) =~ "should be at most 255 character"
    end
  end

  describe "creating diagrams" do
    test "creates diagram with required fields only", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/diagrams/new")

      view
      |> form("#diagram-form", diagram: %{
        title: "Test Diagram",
        summary: "A test diagram",
        content: "graph TD\n  A --> B"
      })
      |> render_submit()

      assert_patch(view, ~p"/diagrams")

      # Verify diagram was created
      diagrams = Memory.list_diagrams(project.id)
      assert length(diagrams) == 1
      diagram = hd(diagrams)
      assert diagram.title == "Test Diagram"
      assert diagram.summary == "A test diagram"
      assert diagram.status == "draft"
    end

    test "creates diagram with all fields", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/diagrams/new")

      view
      |> form("#diagram-form", diagram: %{
        title: "Full Diagram",
        summary: "Complete diagram",
        content: "sequenceDiagram\n  A->>B: Hello",
        diagram_type: "sequence",
        status: "active",
        tags: "auth\nsecurity",
        files: "lib/auth.ex\nlib/user.ex"
      })
      |> render_submit()

      assert_patch(view, ~p"/diagrams")

      # Verify all fields saved
      diagrams = Memory.list_diagrams(project.id)
      diagram = hd(diagrams)
      assert diagram.title == "Full Diagram"
      assert diagram.diagram_type == "sequence"
      assert diagram.status == "active"
      assert diagram.tags == ["auth", "security"]
      assert diagram.files == ["lib/auth.ex", "lib/user.ex"]
    end

    test "shows success flash after creation", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/diagrams/new")

      view
      |> form("#diagram-form", diagram: %{
        title: "Test",
        summary: "Test",
        content: "graph TD\n  A --> B"
      })
      |> render_submit()

      assert Phoenix.Flash.get(view.assigns.flash, :info) =~ "created successfully"
    end
  end

  describe "array field parsing" do
    test "parses tags from newline-separated text", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/diagrams/new")

      view
      |> form("#diagram-form", diagram: %{
        title: "Test",
        summary: "Test",
        content: "content",
        tags: "tag1\ntag2\ntag3"
      })
      |> render_submit()

      diagrams = Memory.list_diagrams(project.id)
      diagram = hd(diagrams)
      assert diagram.tags == ["tag1", "tag2", "tag3"]
    end

    test "handles empty tags", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/diagrams/new")

      view
      |> form("#diagram-form", diagram: %{
        title: "Test",
        summary: "Test",
        content: "content",
        tags: ""
      })
      |> render_submit()

      diagrams = Memory.list_diagrams(project.id)
      diagram = hd(diagrams)
      assert diagram.tags == []
    end

    test "trims whitespace from array items", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/diagrams/new")

      view
      |> form("#diagram-form", diagram: %{
        title: "Test",
        summary: "Test",
        content: "content",
        files: "  lib/auth.ex  \n  lib/user.ex  "
      })
      |> render_submit()

      diagrams = Memory.list_diagrams(project.id)
      diagram = hd(diagrams)
      assert diagram.files == ["lib/auth.ex", "lib/user.ex"]
    end

    test "removes empty lines from arrays", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/diagrams/new")

      view
      |> form("#diagram-form", diagram: %{
        title: "Test",
        summary: "Test",
        content: "content",
        tags: "tag1\n\ntag2\n\n\ntag3"
      })
      |> render_submit()

      diagrams = Memory.list_diagrams(project.id)
      diagram = hd(diagrams)
      assert diagram.tags == ["tag1", "tag2", "tag3"]
    end
  end

  describe "status handling" do
    test "defaults to draft when status not provided", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/diagrams/new")

      view
      |> form("#diagram-form", diagram: %{
        title: "Test",
        summary: "Test",
        content: "content"
      })
      |> render_submit()

      diagrams = Memory.list_diagrams(project.id)
      diagram = hd(diagrams)
      assert diagram.status == "draft"
    end

    test "accepts active status", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/diagrams/new")

      view
      |> form("#diagram-form", diagram: %{
        title: "Test",
        summary: "Test",
        content: "content",
        status: "active"
      })
      |> render_submit()

      diagrams = Memory.list_diagrams(project.id)
      diagram = hd(diagrams)
      assert diagram.status == "active"
    end
  end

  describe "error handling" do
    test "displays changeset errors", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/diagrams/new")

      # Submit empty form
      view
      |> form("#diagram-form", diagram: %{})
      |> render_submit()

      # Should still be on new page (not patched away)
      assert render(view) =~ "New Diagram"

      # Should show validation errors
      assert render(view) =~ "can&#39;t be blank"
    end
  end
end
```

**Run tests:**
```bash
mix test test/pop_stash_web/live/diagram_live/form_component_test.exs
```

### Integration Test Example

**File:** `test/pop_stash_web/live/diagram_live_test.exs`

```elixir
defmodule PopStashWeb.DiagramLiveTest do
  use PopStashWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias PopStash.Memory

  setup do
    user = insert(:user)
    project = insert(:project)
    conn = log_in_user(build_conn(), user, project.id)

    %{conn: conn, project: project}
  end

  describe "Index" do
    test "shows empty state when no diagrams", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/diagrams")

      assert render(view) =~ "No diagrams yet"
    end

    test "creates new diagram", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/diagrams")

      assert index_live |> element("a", "New Diagram") |> render_click() =~
               "New Diagram"

      assert_patch(index_live, ~p"/diagrams/new")

      assert index_live
             |> form("#diagram-form", diagram: %{
               title: "Test Diagram",
               summary: "A test",
               content: "graph TD\n  A --> B"
             })
             |> render_submit()

      assert_patch(index_live, ~p"/diagrams")

      html = render(index_live)
      assert html =~ "Diagram created successfully"
      assert html =~ "Test Diagram"
    end
  end

  describe "Show" do
    test "displays diagram", %{conn: conn, project: project} do
      diagram = diagram_fixture(project.id)

      {:ok, _show_live, html} = live(conn, ~p"/diagrams/#{diagram.id}")

      assert html =~ diagram.title
      assert html =~ diagram.summary
    end

    test "updates status", %{conn: conn, project: project} do
      diagram = diagram_fixture(project.id, status: "draft")

      {:ok, show_live, _html} = live(conn, ~p"/diagrams/#{diagram.id}")

      assert show_live
             |> form("form[phx-change='change_status']", status: "active")
             |> render_change()

      assert render(show_live) =~ "active"
    end
  end

  defp diagram_fixture(project_id, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        title: "Test Diagram",
        summary: "A test diagram",
        content: "graph TD\n  A --> B",
        status: "draft"
      })

    {:ok, diagram} =
      Memory.create_diagram(
        project_id,
        attrs.title,
        attrs.content,
        summary: attrs.summary,
        status: attrs.status
      )

    diagram
  end
end
```

**Run tests:**
```bash
mix test test/pop_stash_web/live/diagram_live_test.exs
```

## Dependencies
- Step 0-1 completed (schema and context exist)
- Existing form components (`.simple_form`, `.input`, `.button`, etc.)
