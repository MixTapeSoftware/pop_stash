defmodule PopStashWeb.Dashboard.InsightLiveTest do
  use PopStashWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias PopStash.Memory
  alias PopStash.Projects

  setup do
    {:ok, project} = Projects.create("Test Project")
    %{project: project}
  end

  describe "Index" do
    test "lists insights with title and body fields", %{conn: conn, project: project} do
      {:ok, _insight} =
        Memory.create_insight(project.id, "Auth uses JWT tokens",
          title: "auth-strategy"
        )

      {:ok, _view, html} = live(conn, ~p"/insights")

      assert html =~ "auth-strategy"
      assert html =~ "Auth uses JWT tokens"
    end

    test "search filters by title and body", %{conn: conn, project: project} do
      {:ok, _} =
        Memory.create_insight(project.id, "Use Guardian for JWT",
          title: "auth-jwt"
        )

      {:ok, _} =
        Memory.create_insight(project.id, "PostgreSQL is preferred",
          title: "database-choice"
        )

      {:ok, view, _html} = live(conn, ~p"/insights")

      html = render_change(view, "search", %{"query" => "guardian"})

      assert html =~ "auth-jwt"
      refute html =~ "database-choice"
    end

    test "new insight form renders with title and body fields", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/insights/new")

      assert html =~ "Title"
      assert html =~ "Body"
      refute html =~ "Key (optional)"
      refute html =~ "Content"
    end
  end

  describe "Show" do
    test "displays insight title and body", %{conn: conn, project: project} do
      {:ok, insight} =
        Memory.create_insight(project.id, "Use ExUnit for testing",
          title: "testing-strategy"
        )

      {:ok, _view, html} = live(conn, ~p"/insights/#{insight.id}")

      assert html =~ "testing-strategy"
      assert html =~ "Use ExUnit for testing"
    end

    test "shows 'Insight' as page title when no title set", %{conn: conn, project: project} do
      {:ok, insight} = Memory.create_insight(project.id, "Body without title")

      {:ok, _view, html} = live(conn, ~p"/insights/#{insight.id}")

      assert html =~ "Insight"
      assert html =~ "Body without title"
    end
  end
end
