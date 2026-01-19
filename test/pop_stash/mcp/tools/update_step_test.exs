defmodule PopStash.MCP.Tools.UpdateStepTest do
  use PopStash.DataCase, async: true

  alias PopStash.MCP.Tools.UpdateStep
  alias PopStash.Plans

  import PopStash.Fixtures

  setup do
    project = project_fixture()
    {:ok, plan} = Plans.create_plan(project.id, "Test Plan", "Plan body")
    {:ok, step} = Plans.add_plan_step(plan.id, "Test step")
    context = %{project_id: project.id}
    {:ok, context: context, plan: plan, step: step}
  end

  describe "execute/2" do
    test "updates step status to completed", %{step: step} do
      # First mark in_progress
      {:ok, _} = Plans.update_plan_step(step.id, %{status: "in_progress"})

      args = %{"step_id" => step.id, "status" => "completed"}
      assert {:ok, message} = UpdateStep.execute(args, %{})
      assert message =~ "Updated step"
      assert message =~ "Status: completed"
    end

    test "updates step status to failed", %{step: step} do
      {:ok, _} = Plans.update_plan_step(step.id, %{status: "in_progress"})

      args = %{"step_id" => step.id, "status" => "failed"}
      assert {:ok, message} = UpdateStep.execute(args, %{})
      assert message =~ "Status: failed"
    end

    test "updates step result", %{step: step} do
      {:ok, _} = Plans.update_plan_step(step.id, %{status: "in_progress"})

      args = %{
        "step_id" => step.id,
        "status" => "completed",
        "result" => "Task completed successfully"
      }

      assert {:ok, message} = UpdateStep.execute(args, %{})
      assert message =~ "Result: Task completed successfully"
    end

    test "updates step metadata", %{step: step} do
      args = %{"step_id" => step.id, "metadata" => %{"duration_ms" => 1500}}
      assert {:ok, _message} = UpdateStep.execute(args, %{})

      updated = Plans.get_plan_step_by_id(step.id)
      assert updated.metadata == %{"duration_ms" => 1500}
    end

    test "returns error when no attributes provided", %{step: step} do
      args = %{"step_id" => step.id}
      assert {:error, message} = UpdateStep.execute(args, %{})
      assert message =~ "At least one of status, result, or metadata must be provided"
    end

    test "returns error for invalid status transition", %{step: step} do
      # pending -> completed is invalid (must go through in_progress)
      args = %{"step_id" => step.id, "status" => "completed"}
      assert {:error, message} = UpdateStep.execute(args, %{})
      assert message =~ "Invalid status transition"
    end

    test "returns error for nonexistent step" do
      args = %{"step_id" => Ecto.UUID.generate(), "status" => "completed"}
      assert {:error, "Step not found"} = UpdateStep.execute(args, %{})
    end
  end
end
