defmodule PopStash.MCP.Tools.GetPlanTest do
  use PopStash.DataCase, async: true

  alias PopStash.MCP.Tools.GetPlan
  alias PopStash.Memory

  import PopStash.Fixtures

  setup do
    project = project_fixture()
    context = %{project_id: project.id}
    {:ok, context: context, project: project}
  end

  describe "execute/2" do
    test "retrieves a plan by title", %{context: context, project: project} do
      {:ok, _} = Memory.create_plan(project.id, "Q1 Roadmap", "Goals for Q1")

      args = %{"title" => "Q1 Roadmap"}
      assert {:ok, message} = GetPlan.execute(args, context)
      assert message =~ "Q1 Roadmap"
      assert message =~ "Goals for Q1"
    end

    test "returns not found message for nonexistent plan", %{context: context} do
      args = %{"title" => "Nonexistent"}
      assert {:ok, message} = GetPlan.execute(args, context)
      assert message =~ "No plan found"
    end

    test "lists all plan titles with list_titles option", %{context: context, project: project} do
      {:ok, _} = Memory.create_plan(project.id, "Roadmap", "Content 1")
      {:ok, _} = Memory.create_plan(project.id, "Architecture", "Content 2")

      args = %{"list_titles" => true}
      assert {:ok, message} = GetPlan.execute(args, context)
      assert message =~ "Plan titles"
      assert message =~ "Roadmap"
      assert message =~ "Architecture"
    end

    test "returns empty message when no plans exist for list_titles", %{context: context} do
      args = %{"list_titles" => true}
      assert {:ok, message} = GetPlan.execute(args, context)
      assert message =~ "No plans saved yet"
    end

    test "lists recent plans when no arguments provided", %{context: context, project: project} do
      {:ok, _} = Memory.create_plan(project.id, "Plan 1", "First plan")
      {:ok, _} = Memory.create_plan(project.id, "Plan 2", "Second plan")

      args = %{}
      assert {:ok, message} = GetPlan.execute(args, context)
      assert message =~ "Recent plans"
      assert message =~ "Plan 1"
      assert message =~ "Plan 2"
    end

    test "respects limit option", %{context: context, project: project} do
      for i <- 1..5 do
        Memory.create_plan(project.id, "Plan #{i}", "Content #{i}")
      end

      args = %{"limit" => 2}
      assert {:ok, message} = GetPlan.execute(args, context)
      assert message =~ "Recent plans (2)"
    end

    test "returns empty message when no plans exist", %{context: context} do
      args = %{}
      assert {:ok, message} = GetPlan.execute(args, context)
      assert message =~ "No plans saved yet"
    end
  end
end
