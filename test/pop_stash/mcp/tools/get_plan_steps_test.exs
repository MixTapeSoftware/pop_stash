defmodule PopStash.MCP.Tools.GetPlanStepsTest do
  use PopStash.DataCase, async: true

  alias PopStash.MCP.Tools.GetPlanSteps
  alias PopStash.Plans

  import PopStash.Fixtures

  setup do
    project = project_fixture()
    {:ok, plan} = Plans.create_plan(project.id, "Test Plan", "Plan body")
    context = %{project_id: project.id}
    {:ok, context: context, plan: plan}
  end

  describe "execute/2" do
    test "lists all steps for a plan", %{plan: plan} do
      {:ok, _} = Plans.add_plan_step(plan.id, "Step 1")
      {:ok, _} = Plans.add_plan_step(plan.id, "Step 2")
      {:ok, _} = Plans.add_plan_step(plan.id, "Step 3")

      args = %{"plan_id" => plan.id}
      assert {:ok, message} = GetPlanSteps.execute(args, %{})
      assert message =~ "Steps (3)"
      assert message =~ "Step 1"
      assert message =~ "Step 2"
      assert message =~ "Step 3"
    end

    test "returns empty message when no steps", %{plan: plan} do
      args = %{"plan_id" => plan.id}
      assert {:ok, message} = GetPlanSteps.execute(args, %{})
      assert message =~ "No steps found"
      assert message =~ "add_step"
    end

    test "filters by status", %{plan: plan} do
      {:ok, step1} = Plans.add_plan_step(plan.id, "Pending step")
      {:ok, _step2} = Plans.add_plan_step(plan.id, "Another pending step")
      {:ok, _} = Plans.update_plan_step(step1.id, %{status: "in_progress"})

      args = %{"plan_id" => plan.id, "status" => "pending"}
      assert {:ok, message} = GetPlanSteps.execute(args, %{})
      assert message =~ "Steps (1)"
      assert message =~ "Another pending step"
      refute message =~ "Pending step\n"
    end

    test "shows status icons", %{plan: plan} do
      {:ok, step1} = Plans.add_plan_step(plan.id, "Pending")
      {:ok, step2} = Plans.add_plan_step(plan.id, "In progress")
      {:ok, _} = Plans.update_plan_step(step1.id, %{status: "in_progress"})
      {:ok, _} = Plans.update_plan_step(step1.id, %{status: "completed"})
      {:ok, _} = Plans.update_plan_step(step2.id, %{status: "in_progress"})

      args = %{"plan_id" => plan.id}
      assert {:ok, message} = GetPlanSteps.execute(args, %{})
      assert message =~ "●"
      assert message =~ "◐"
    end

    test "truncates long descriptions", %{plan: plan} do
      long_desc = String.duplicate("a", 100)
      {:ok, _} = Plans.add_plan_step(plan.id, long_desc)

      args = %{"plan_id" => plan.id}
      assert {:ok, message} = GetPlanSteps.execute(args, %{})
      assert message =~ "..."
    end

    test "includes step_id in output", %{plan: plan} do
      {:ok, step} = Plans.add_plan_step(plan.id, "Test step")

      args = %{"plan_id" => plan.id}
      assert {:ok, message} = GetPlanSteps.execute(args, %{})
      assert message =~ step.id
    end

    test "returns empty message with status filter when no matching steps", %{plan: plan} do
      {:ok, _} = Plans.add_plan_step(plan.id, "Pending step")

      args = %{"plan_id" => plan.id, "status" => "completed"}
      assert {:ok, message} = GetPlanSteps.execute(args, %{})
      assert message =~ "No steps found"
      assert message =~ "status 'completed'"
    end
  end
end
