defmodule PopStash.MCP.Tools.GetStepTest do
  use PopStash.DataCase, async: true

  alias PopStash.MCP.Tools.GetStep
  alias PopStash.Plans

  import PopStash.Fixtures

  setup do
    project = project_fixture()
    {:ok, plan} = Plans.create_plan(project.id, "Test Plan", "Plan body")
    {:ok, step} = Plans.add_plan_step(plan.id, "Test step description")
    context = %{project_id: project.id}
    {:ok, context: context, plan: plan, step: step}
  end

  describe "execute/2" do
    test "returns full step details", %{step: step, plan: plan} do
      args = %{"step_id" => step.id}
      assert {:ok, message} = GetStep.execute(args, %{})
      assert message =~ "Step 1.0"
      assert message =~ step.id
      assert message =~ plan.id
      assert message =~ "**Status:** pending"
      assert message =~ "**Created by:** user"
      assert message =~ "Test step description"
    end

    test "includes result when present", %{step: step} do
      {:ok, _} = Plans.update_plan_step(step.id, %{status: "in_progress"})
      {:ok, _} = Plans.update_plan_step(step.id, %{status: "completed", result: "Task completed"})

      args = %{"step_id" => step.id}
      assert {:ok, message} = GetStep.execute(args, %{})
      assert message =~ "**Result:** Task completed"
    end

    test "includes metadata when present", %{plan: plan} do
      {:ok, step} =
        Plans.add_plan_step(plan.id, "Step with metadata", metadata: %{"key" => "value"})

      args = %{"step_id" => step.id}
      assert {:ok, message} = GetStep.execute(args, %{})
      assert message =~ "Metadata:"
      assert message =~ "key"
      assert message =~ "value"
    end

    test "returns error for nonexistent step" do
      args = %{"step_id" => Ecto.UUID.generate()}
      assert {:error, "Step not found"} = GetStep.execute(args, %{})
    end
  end
end
