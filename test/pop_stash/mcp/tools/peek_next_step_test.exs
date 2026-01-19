defmodule PopStash.MCP.Tools.PeekNextStepTest do
  use PopStash.DataCase, async: true

  alias PopStash.MCP.Tools.PeekNextStep
  alias PopStash.Plans

  import PopStash.Fixtures

  setup do
    project = project_fixture()
    {:ok, plan} = Plans.create_plan(project.id, "Test Plan", "Plan body")
    context = %{project_id: project.id}
    {:ok, context: context, plan: plan}
  end

  describe "execute/2" do
    test "returns next pending step", %{plan: plan} do
      {:ok, step} = Plans.add_plan_step(plan.id, "First step")
      {:ok, _} = Plans.add_plan_step(plan.id, "Second step")

      args = %{"plan_id" => plan.id}
      assert {:ok, message} = PeekNextStep.execute(args, %{})
      assert message =~ "Next pending step"
      assert message =~ step.id
      assert message =~ "First step"
      assert message =~ "Step number: 1.0"
    end

    test "returns message when no pending steps", %{plan: plan} do
      args = %{"plan_id" => plan.id}
      assert {:ok, message} = PeekNextStep.execute(args, %{})
      assert message =~ "No pending steps"
    end

    test "skips non-pending steps", %{plan: plan} do
      {:ok, step1} = Plans.add_plan_step(plan.id, "Step 1")
      {:ok, step2} = Plans.add_plan_step(plan.id, "Step 2")

      # Mark step1 as in_progress
      {:ok, _} = Plans.update_plan_step(step1.id, %{status: "in_progress"})

      args = %{"plan_id" => plan.id}
      assert {:ok, message} = PeekNextStep.execute(args, %{})
      assert message =~ step2.id
      assert message =~ "Step 2"
    end

    test "does not change step status (read-only)", %{plan: plan} do
      {:ok, step} = Plans.add_plan_step(plan.id, "Test step")

      args = %{"plan_id" => plan.id}
      {:ok, _} = PeekNextStep.execute(args, %{})

      # Step should still be pending
      updated = Plans.get_plan_step_by_id(step.id)
      assert updated.status == "pending"
    end
  end
end
