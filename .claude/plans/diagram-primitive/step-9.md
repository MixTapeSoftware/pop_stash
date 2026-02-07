# Step 9: Tests

## Overview
Add comprehensive test coverage for diagrams: unit tests for context, schema tests, LiveView integration tests, and MCP tool tests.

## Context
Follow existing test patterns from insights and decisions. Use factories for fixtures, test both happy and error paths, and verify PubSub broadcasts.

## Implementation

### 1. Add to Factory (if using)

**File:** `test/support/factory.ex` (or similar)

```elixir
def diagram_factory do
  %PopStash.Memory.Diagram{
    title: sequence(:title, &"Test Diagram #{&1}"),
    summary: "A test diagram for testing purposes",
    content: """
    graph TD
      A[Start] --> B[Process]
      B --> C[End]
    """,
    diagram_type: "flowchart",
    status: "draft",
    tags: ["test"],
    files: ["lib/test.ex"],
    project: build(:project)
  }
end
```

### 2. Context Tests

**File:** `test/pop_stash/memory_test.exs` (extend existing)

```elixir
describe "diagrams" do
  setup do
    project = insert(:project)
    %{project_id: project.id}
  end

  test "create_diagram/3 creates a diagram with required fields", %{project_id: project_id} do
    assert {:ok, diagram} =
             Memory.create_diagram(
               project_id,
               "Auth Flow",
               "graph TD\n  A --> B",
               summary: "Shows authentication"
             )

    assert diagram.title == "Auth Flow"
    assert diagram.summary == "Shows authentication"
    assert diagram.status == "draft"
    assert diagram.project_id == project_id
  end

  test "create_diagram/3 validates required fields", %{project_id: project_id} do
    assert {:error, changeset} =
             Memory.create_diagram(project_id, "", "content", summary: "test")

    assert %{title: ["can't be blank"]} = errors_on(changeset)
  end

  test "create_diagram/3 validates status", %{project_id: project_id} do
    assert {:error, changeset} =
             Memory.create_diagram(
               project_id,
               "Test",
               "content",
               summary: "test",
               status: "invalid"
             )

    assert %{status: ["is invalid"]} = errors_on(changeset)
  end

  test "create_diagram/3 broadcasts event", %{project_id: project_id} do
    Phoenix.PubSub.subscribe(PopStash.PubSub, "memory:events")

    {:ok, diagram} =
      Memory.create_diagram(project_id, "Test", "content", summary: "test")

    assert_received {:diagram_created, ^diagram}
  end

  test "get_diagram/1 returns diagram by id", %{project_id: project_id} do
    {:ok, diagram} =
      Memory.create_diagram(project_id, "Test", "content", summary: "test")

    assert {:ok, fetched} = Memory.get_diagram(diagram.id)
    assert fetched.id == diagram.id
  end

  test "get_diagram/1 returns error for invalid id" do
    assert {:error, :not_found} = Memory.get_diagram(Ecto.UUID.generate())
  end

  test "get_diagrams_by_title/2 returns all diagrams with title", %{
    project_id: project_id
  } do
    {:ok, d1} = Memory.create_diagram(project_id, "Test", "v1", summary: "v1")
    {:ok, d2} = Memory.create_diagram(project_id, "Test", "v2", summary: "v2")
    {:ok, _d3} = Memory.create_diagram(project_id, "Other", "v1", summary: "v1")

    diagrams = Memory.get_diagrams_by_title(project_id, "Test")

    assert length(diagrams) == 2
    assert d1.id in Enum.map(diagrams, & &1.id)
    assert d2.id in Enum.map(diagrams, & &1.id)
  end

  test "get_active_diagram_by_title/2 returns only active diagram", %{
    project_id: project_id
  } do
    {:ok, _draft} =
      Memory.create_diagram(project_id, "Test", "draft", summary: "draft")

    {:ok, active} =
      Memory.create_diagram(project_id, "Test", "active", summary: "active", status: "active")

    assert {:ok, found} = Memory.get_active_diagram_by_title(project_id, "Test")
    assert found.id == active.id
  end

  test "list_diagrams/2 returns diagrams for project", %{project_id: project_id} do
    {:ok, d1} = Memory.create_diagram(project_id, "D1", "c1", summary: "s1")
    {:ok, d2} = Memory.create_diagram(project_id, "D2", "c2", summary: "s2")

    diagrams = Memory.list_diagrams(project_id)

    assert length(diagrams) == 2
    assert d1.id in Enum.map(diagrams, & &1.id)
    assert d2.id in Enum.map(diagrams, & &1.id)
  end

  test "list_diagrams/2 filters by status", %{project_id: project_id} do
    {:ok, _draft} =
      Memory.create_diagram(project_id, "Draft", "c", summary: "s", status: "draft")

    {:ok, active} =
      Memory.create_diagram(project_id, "Active", "c", summary: "s", status: "active")

    diagrams = Memory.list_diagrams(project_id, status: "active")

    assert length(diagrams) == 1
    assert hd(diagrams).id == active.id
  end

  test "list_diagrams/2 respects limit", %{project_id: project_id} do
    for i <- 1..10 do
      Memory.create_diagram(project_id, "D#{i}", "c", summary: "s")
    end

    diagrams = Memory.list_diagrams(project_id, limit: 5)

    assert length(diagrams) == 5
  end

  test "list_diagram_titles/1 returns unique titles", %{project_id: project_id} do
    Memory.create_diagram(project_id, "Auth", "v1", summary: "s1")
    Memory.create_diagram(project_id, "Auth", "v2", summary: "s2")
    Memory.create_diagram(project_id, "Data", "v1", summary: "s3")

    titles = Memory.list_diagram_titles(project_id)

    assert "Auth" in titles
    assert "Data" in titles
    assert length(titles) == 2
  end

  test "update_diagram_status/2 updates status", %{project_id: project_id} do
    {:ok, diagram} =
      Memory.create_diagram(project_id, "Test", "c", summary: "s", status: "draft")

    assert {:ok, updated} = Memory.update_diagram_status(diagram.id, "active")
    assert updated.status == "active"
  end

  test "update_diagram_status/2 validates status", %{project_id: project_id} do
    {:ok, diagram} =
      Memory.create_diagram(project_id, "Test", "c", summary: "s")

    assert {:error, changeset} = Memory.update_diagram_status(diagram.id, "invalid")
    assert %{status: ["is invalid"]} = errors_on(changeset)
  end

  test "update_diagram_status/2 broadcasts event", %{project_id: project_id} do
    {:ok, diagram} =
      Memory.create_diagram(project_id, "Test", "c", summary: "s")

    Phoenix.PubSub.subscribe(PopStash.PubSub, "memory:events")

    {:ok, updated} = Memory.update_diagram_status(diagram.id, "active")

    assert_received {:diagram_status_updated, ^updated}
  end

  test "delete_diagram/1 deletes diagram", %{project_id: project_id} do
    {:ok, diagram} =
      Memory.create_diagram(project_id, "Test", "c", summary: "s")

    assert :ok = Memory.delete_diagram(diagram.id)
    assert {:error, :not_found} = Memory.get_diagram(diagram.id)
  end

  test "delete_diagram/1 broadcasts event", %{project_id: project_id} do
    {:ok, diagram} =
      Memory.create_diagram(project_id, "Test", "c", summary: "s")

    Phoenix.PubSub.subscribe(PopStash.PubSub, "memory:events")

    Memory.delete_diagram(diagram.id)

    assert_received {:diagram_deleted, diagram_id}
    assert diagram_id == diagram.id
  end

  test "delete_diagram/1 returns error for invalid id" do
    assert {:error, :not_found} = Memory.delete_diagram(Ecto.UUID.generate())
  end
end
```

### 3. LiveView Tests

**File:** `test/pop_stash_web/live/diagram_live_test.exs`

```elixir
defmodule PopStashWeb.DiagramLiveTest do
  use PopStashWeb.ConnCase
  import Phoenix.LiveViewTest

  alias PopStash.Memory

  setup do
    project = insert(:project)
    user = insert(:user)

    conn =
      conn
      |> log_in_user(user)
      |> assign(:current_scope, %{project: project})

    %{conn: conn, project: project}
  end

  describe "Index" do
    test "lists all diagrams", %{conn: conn, project: project} do
      diagram = diagram_fixture(project.id)
      {:ok, _index_live, html} = live(conn, ~p"/diagrams")

      assert html =~ "Diagrams"
      assert html =~ diagram.title
    end

    test "shows empty state when no diagrams", %{conn: conn} do
      {:ok, _index_live, html} = live(conn, ~p"/diagrams")

      assert html =~ "No diagrams yet"
    end

    test "saves new diagram", %{conn: conn, project: project} do
      {:ok, index_live, _html} = live(conn, ~p"/diagrams")

      assert index_live |> element("a", "New Diagram") |> render_click() =~
               "New Diagram"

      assert_patch(index_live, ~p"/diagrams/new")

      assert index_live
             |> form("#diagram-form",
               diagram: %{
                 title: "Test Diagram",
                 summary: "A test diagram",
                 content: "graph TD\n  A --> B"
               }
             )
             |> render_submit()

      assert_patch(index_live, ~p"/diagrams")

      html = render(index_live)
      assert html =~ "Diagram created successfully"
      assert html =~ "Test Diagram"
    end

    test "filters by status", %{conn: conn, project: project} do
      _draft = diagram_fixture(project.id, status: "draft")
      active = diagram_fixture(project.id, status: "active", title: "Active Diagram")

      {:ok, index_live, _html} = live(conn, ~p"/diagrams")

      # Change status filter
      index_live
      |> element("form[phx-change='filter_status']")
      |> render_change(%{status: "active"})

      html = render(index_live)
      assert html =~ "Active Diagram"
      refute html =~ "Draft"
    end

    test "searches diagrams", %{conn: conn, project: project} do
      diagram_fixture(project.id, title: "Auth Flow")
      diagram_fixture(project.id, title: "Data Model")

      {:ok, index_live, _html} = live(conn, ~p"/diagrams")

      index_live
      |> element("form[phx-change='search']")
      |> render_change(%{query: "Auth"})

      html = render(index_live)
      assert html =~ "Auth Flow"
      # Search may or may not return Data Model depending on implementation
    end

    test "deletes diagram", %{conn: conn, project: project} do
      diagram = diagram_fixture(project.id)
      {:ok, index_live, _html} = live(conn, ~p"/diagrams")

      assert index_live |> element("a[phx-click='delete']") |> render_click()
      refute has_element?(index_live, "#diagram-#{diagram.id}")
    end
  end

  describe "Show" do
    test "displays diagram", %{conn: conn, project: project} do
      diagram = diagram_fixture(project.id)

      {:ok, _show_live, html} = live(conn, ~p"/diagrams/#{diagram.id}")

      assert html =~ diagram.title
      assert html =~ diagram.summary
    end

    test "updates diagram status", %{conn: conn, project: project} do
      diagram = diagram_fixture(project.id, status: "draft")

      {:ok, show_live, _html} = live(conn, ~p"/diagrams/#{diagram.id}")

      assert show_live
             |> form("form[phx-change='change_status']", status: "active")
             |> render_change()

      assert render(show_live) =~ "active"
    end

    test "deletes diagram", %{conn: conn, project: project} do
      diagram = diagram_fixture(project.id)

      {:ok, show_live, _html} = live(conn, ~p"/diagrams/#{diagram.id}")

      {:ok, index_live, _html} =
        show_live
        |> element("a[phx-click='delete']")
        |> render_click()
        |> follow_redirect(conn, ~p"/diagrams")

      refute has_element?(index_live, "#diagram-#{diagram.id}")
    end

    test "shows related diagrams", %{conn: conn, project: project} do
      diagram1 = diagram_fixture(project.id, title: "Auth Flow")
      diagram2 = diagram_fixture(project.id, title: "Auth Flow", content: "v2")

      {:ok, _show_live, html} = live(conn, ~p"/diagrams/#{diagram1.id}")

      assert html =~ "Other Diagrams with This Title"
      assert html =~ diagram2.id
    end
  end

  defp diagram_fixture(project_id, attrs \\ %{}) do
    defaults = %{
      title: "Test Diagram #{System.unique_integer()}",
      summary: "A test diagram",
      content: "graph TD\n  A --> B",
      status: "draft"
    }

    attrs = Enum.into(attrs, defaults)

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

### 4. MCP Tool Tests

**File:** `test/pop_stash/mcp/tools/create_diagram_test.exs`

```elixir
defmodule PopStash.MCP.Tools.CreateDiagramTest do
  use PopStash.DataCase

  alias PopStash.MCP.Tools.CreateDiagram

  setup do
    project = insert(:project)
    %{project_id: project.id}
  end

  test "creates diagram with required fields", %{project_id: project_id} do
    args = %{
      "title" => "Test Diagram",
      "summary" => "A test",
      "content" => "graph TD\n  A --> B"
    }

    assert {:ok, response} =
             CreateDiagram.execute(args, %{project_id: project_id})

    assert response =~ "Test Diagram"
    assert response =~ "draft"
  end

  test "validates required fields", %{project_id: project_id} do
    args = %{"title" => "Test"}

    assert {:error, message} =
             CreateDiagram.execute(args, %{project_id: project_id})

    assert message =~ "summary"
  end

  test "accepts optional fields", %{project_id: project_id} do
    args = %{
      "title" => "Test",
      "summary" => "Test",
      "content" => "graph TD\n  A --> B",
      "diagram_type" => "flowchart",
      "status" => "active",
      "tags" => ["test", "example"],
      "files" => ["lib/test.ex"]
    }

    assert {:ok, _response} =
             CreateDiagram.execute(args, %{project_id: project_id})
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

    {:ok, _diagram} =
      Memory.create_diagram(
        project.id,
        "Auth Flow",
        "graph TD\n  A --> B",
        summary: "Authentication flow diagram",
        status: "active"
      )

    %{project_id: project.id}
  end

  test "searches diagrams by query", %{project_id: project_id} do
    args = %{"query" => "authentication"}

    assert {:ok, response} =
             GetDiagrams.execute(args, %{project_id: project_id})

    assert response =~ "Auth Flow"
    assert response =~ "mermaid"
  end

  test "returns no results message when not found", %{project_id: project_id} do
    args = %{"query" => "nonexistent"}

    assert {:ok, response} =
             GetDiagrams.execute(args, %{project_id: project_id})

    assert response =~ "No diagrams found"
  end

  test "filters by status", %{project_id: project_id} do
    # Default is active, so should find it
    args = %{"query" => "auth", "status" => "active"}

    assert {:ok, response} =
             GetDiagrams.execute(args, %{project_id: project_id})

    assert response =~ "Auth Flow"

    # Should not find draft diagrams
    args = %{"query" => "auth", "status" => "draft"}

    assert {:ok, response} =
             GetDiagrams.execute(args, %{project_id: project_id})

    assert response =~ "No diagrams found"
  end

  test "respects limit", %{project_id: project_id} do
    # Create multiple diagrams
    for i <- 1..10 do
      Memory.create_diagram(
        project_id,
        "Diagram #{i}",
        "content",
        summary: "test diagram",
        status: "active"
      )
    end

    args = %{"query" => "diagram", "limit" => 3}

    {:ok, response} = GetDiagrams.execute(args, %{project_id: project_id})

    # Count number of "##" headers (one per diagram)
    diagram_count = response |> String.split("##") |> length() |> Kernel.-(1)

    assert diagram_count <= 3
  end
end
```

## Verification

```bash
# Run all tests
mix test

# Run specific test file
mix test test/pop_stash/memory_test.exs

# Run with coverage
mix test --cover

# Run only diagram tests
mix test --only diagrams

# (Tag tests with @tag :diagrams to use this filter)
```

## Coverage Goals

Aim for:
- **Context functions**: 100% coverage
- **LiveView interactions**: Major paths covered
- **MCP tools**: Happy and error paths
- **Edge cases**: Empty states, validation errors, not found scenarios

## Dependencies
- Steps 0-8 completed (entire feature implemented)
- Test helpers and factories set up
- Phoenix.LiveViewTest available

## Final Notes

After all steps (0-9) are complete:
1. Run full test suite: `mix test`
2. Run type checking: `mix dialyzer` (if using)
3. Run linter: `mix format --check-formatted`
4. Manual smoke test in browser
5. Test MCP tools via Claude Code
6. Verify real-time updates work across tabs
7. Check production build: `MIX_ENV=prod mix compile`

The diagrams feature is now complete and ready for production use!
