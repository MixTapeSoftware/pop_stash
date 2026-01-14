defmodule PopStash.MCP.Tools.DecideTest do
  use PopStash.DataCase, async: true

  alias PopStash.MCP.Tools.Decide
  alias PopStash.Memory

  import PopStash.Fixtures

  setup do
    project = project_fixture()
    context = %{project_id: project.id}
    {:ok, context: context, project: project}
  end

  describe "execute/2" do
    test "records a decision with topic and decision", %{context: context, project: project} do
      args = %{
        "title" => "Authentication",
        "body" => "Use Guardian for JWT"
      }

      assert {:ok, message} = Decide.execute(args, context)
      assert message =~ "Decision recorded"
      # normalized
      assert message =~ "authentication"

      # Verify it was saved
      [decision] = Memory.get_decisions_by_title(project.id, "authentication")
      assert decision.body == "Use Guardian for JWT"
    end

    test "records a decision with reasoning", %{context: context, project: project} do
      args = %{
        "title" => "database",
        "body" => "Use PostgreSQL",
        "reasoning" => "Better JSON support"
      }

      assert {:ok, _} = Decide.execute(args, context)

      [decision] = Memory.get_decisions_by_title(project.id, "database")
      assert decision.reasoning == "Better JSON support"
    end

    test "returns error for missing required fields", %{context: context} do
      # missing decision
      args = %{"title" => "auth"}

      assert {:error, message} = Decide.execute(args, context)
      assert message =~ "body"
    end
  end
end
