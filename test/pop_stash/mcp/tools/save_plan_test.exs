defmodule PopStash.MCP.Tools.SavePlanTest do
  use PopStash.DataCase, async: true

  alias PopStash.MCP.Tools.SavePlan
  alias PopStash.Plans

  import PopStash.Fixtures

  setup do
    project = project_fixture()
    context = %{project_id: project.id}
    {:ok, context: context, project: project}
  end

  describe "execute/2" do
    test "saves a plan with title and body", %{context: context, project: project} do
      args = %{
        "title" => "Q1 Roadmap",
        "body" => "Goals for Q1"
      }

      assert {:ok, message} = SavePlan.execute(args, context)
      assert message =~ "Saved plan"
      assert message =~ "Q1 Roadmap"

      assert {:ok, plan} = Plans.get_plan(project.id, "Q1 Roadmap")
      assert plan.body == "Goals for Q1"
    end

    test "saves a plan with tags", %{context: context, project: project} do
      args = %{
        "title" => "Architecture",
        "body" => "System design",
        "tags" => ["architecture", "design"]
      }

      assert {:ok, _} = SavePlan.execute(args, context)

      assert {:ok, plan} = Plans.get_plan(project.id, "Architecture")
      assert plan.tags == ["architecture", "design"]
    end

    test "saves a plan with files", %{context: context, project: project} do
      args = %{
        "title" => "API Design",
        "body" => "API specification",
        "files" => ["docs/api.md", "lib/api/router.ex"]
      }

      assert {:ok, _} = SavePlan.execute(args, context)

      assert {:ok, plan} = Plans.get_plan(project.id, "API Design")
      assert plan.files == ["docs/api.md", "lib/api/router.ex"]
    end

    test "returns error for missing title", %{context: context} do
      args = %{"body" => "Content without title"}

      assert {:error, message} = SavePlan.execute(args, context)
      assert message =~ "title"
    end

    test "returns error for missing body", %{context: context} do
      args = %{"title" => "Title without body"}

      assert {:error, message} = SavePlan.execute(args, context)
      assert message =~ "body"
    end
  end
end
