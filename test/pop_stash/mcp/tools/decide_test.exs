defmodule PopStash.MCP.Tools.DecideTest do
  use PopStash.DataCase, async: true

  alias PopStash.MCP.Tools.Decide
  alias PopStash.{Agents, Memory}

  import PopStash.Fixtures

  setup do
    project = project_fixture()
    {:ok, agent} = Agents.connect(project.id, name: "test-agent")
    context = %{project_id: project.id, agent_id: agent.id}
    {:ok, context: context, project: project}
  end

  describe "execute/2" do
    test "records a decision with topic and decision", %{context: context, project: project} do
      args = %{
        "topic" => "Authentication",
        "decision" => "Use Guardian for JWT"
      }

      assert {:ok, message} = Decide.execute(args, context)
      assert message =~ "Decision recorded"
      # normalized
      assert message =~ "authentication"

      # Verify it was saved
      [decision] = Memory.get_decisions_by_topic(project.id, "authentication")
      assert decision.decision == "Use Guardian for JWT"
    end

    test "records a decision with reasoning", %{context: context, project: project} do
      args = %{
        "topic" => "database",
        "decision" => "Use PostgreSQL",
        "reasoning" => "Better JSON support"
      }

      assert {:ok, _} = Decide.execute(args, context)

      [decision] = Memory.get_decisions_by_topic(project.id, "database")
      assert decision.reasoning == "Better JSON support"
    end

    test "returns error for missing required fields", %{context: context} do
      # missing decision
      args = %{"topic" => "auth"}

      assert {:error, message} = Decide.execute(args, context)
      assert message =~ "decision"
    end
  end
end
