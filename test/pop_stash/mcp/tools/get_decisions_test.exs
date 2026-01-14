defmodule PopStash.MCP.Tools.GetDecisionsTest do
  use PopStash.DataCase, async: true

  alias PopStash.MCP.Tools.GetDecisions
  alias PopStash.Memory

  import PopStash.Fixtures

  setup do
    project = project_fixture()
    context = %{project_id: project.id}
    {:ok, context: context, project: project}
  end

  describe "execute/2" do
    test "returns message when no decisions exist", %{context: context} do
      assert {:ok, message} = GetDecisions.execute(%{}, context)
      assert message =~ "No decisions recorded"
    end

    test "lists recent decisions when no topic provided", %{
      context: context,
      project: project
    } do
      {:ok, _} = Memory.create_decision(project.id, "auth", "Use Guardian")
      {:ok, _} = Memory.create_decision(project.id, "db", "Use Postgres")

      assert {:ok, message} = GetDecisions.execute(%{}, context)
      assert message =~ "auth"
      assert message =~ "db"
      assert message =~ "Use Guardian"
    end

    test "filters by title", %{context: context, project: project} do
      {:ok, _} = Memory.create_decision(project.id, "auth", "Auth decision")
      {:ok, _} = Memory.create_decision(project.id, "database", "DB decision")

      assert {:ok, message} = GetDecisions.execute(%{"title" => "auth"}, context)
      assert message =~ "Auth decision"
      refute message =~ "DB decision"
    end

    test "topic matching is case-insensitive", %{context: context, project: project} do
      {:ok, _} = Memory.create_decision(project.id, "Authentication", "Decision")

      assert {:ok, message} = GetDecisions.execute(%{"title" => "AUTHENTICATION"}, context)
      assert message =~ "Decision"
    end

    test "respects limit parameter", %{context: context, project: project} do
      for i <- 1..5 do
        Memory.create_decision(project.id, "topic", "Decision #{i}")
      end

      assert {:ok, message} = GetDecisions.execute(%{"limit" => 2}, context)
      assert message =~ "2"
    end

    test "lists topics when list_titles is true", %{
      context: context,
      project: project
    } do
      {:ok, _} = Memory.create_decision(project.id, "auth", "Decision")
      {:ok, _} = Memory.create_decision(project.id, "database", "Decision")
      {:ok, _} = Memory.create_decision(project.id, "api", "Decision")

      assert {:ok, message} = GetDecisions.execute(%{"list_titles" => true}, context)
      assert message =~ "Decision topics:"
      assert message =~ "auth"
      assert message =~ "database"
      assert message =~ "api"
    end

    test "returns helpful message when topic not found", %{context: context} do
      assert {:ok, message} = GetDecisions.execute(%{"title" => "nonexistent"}, context)
      assert message =~ "No decisions found"
      assert message =~ "list_titles"
    end
  end
end
