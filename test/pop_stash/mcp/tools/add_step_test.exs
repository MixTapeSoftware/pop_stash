defmodule PopStash.MCP.Tools.AddStepTest do
  use PopStash.DataCase, async: true

  alias PopStash.MCP.Tools.AddStep
  alias PopStash.Plans

  import PopStash.Fixtures

  setup do
    project = project_fixture()
    {:ok, plan} = Plans.create_plan(project.id, "Test Plan", "Plan body")
    context = %{project_id: project.id}
    {:ok, context: context, plan: plan}
  end

  describe "execute/2" do
    test "adds a step with auto-incremented step_number", %{plan: plan} do
      args = %{"plan_id" => plan.id, "description" => "First step"}

      assert {:ok, message} = AddStep.execute(args, %{})
      assert message =~ "Added step 1.0"
      assert message =~ "First step"
      assert message =~ "Created by: agent"
    end

    test "adds multiple steps with incrementing step_numbers", %{plan: plan} do
      AddStep.execute(%{"plan_id" => plan.id, "description" => "Step 1"}, %{})
      AddStep.execute(%{"plan_id" => plan.id, "description" => "Step 2"}, %{})
      {:ok, message} = AddStep.execute(%{"plan_id" => plan.id, "description" => "Step 3"}, %{})

      assert message =~ "Added step 3.0"
    end

    test "adds step with explicit step_number", %{plan: plan} do
      args = %{"plan_id" => plan.id, "description" => "Step at 5", "step_number" => 5.0}

      assert {:ok, message} = AddStep.execute(args, %{})
      assert message =~ "Added step 5.0"
    end

    test "adds step after another step", %{plan: plan} do
      AddStep.execute(
        %{"plan_id" => plan.id, "description" => "Step 1", "step_number" => 1.0},
        %{}
      )

      AddStep.execute(
        %{"plan_id" => plan.id, "description" => "Step 2", "step_number" => 2.0},
        %{}
      )

      args = %{"plan_id" => plan.id, "description" => "Step 1.5", "after_step" => 1.0}
      {:ok, message} = AddStep.execute(args, %{})

      assert message =~ "Added step 1.5"
    end

    test "defaults created_by to agent", %{plan: plan} do
      args = %{"plan_id" => plan.id, "description" => "Agent step"}

      {:ok, message} = AddStep.execute(args, %{})
      assert message =~ "Created by: agent"
    end

    test "accepts created_by user", %{plan: plan} do
      args = %{"plan_id" => plan.id, "description" => "User step", "created_by" => "user"}

      {:ok, message} = AddStep.execute(args, %{})
      assert message =~ "Created by: user"
    end

    test "accepts metadata", %{plan: plan} do
      args = %{
        "plan_id" => plan.id,
        "description" => "Step with metadata",
        "metadata" => %{"source" => "automation"}
      }

      assert {:ok, _message} = AddStep.execute(args, %{})

      steps = Plans.list_plan_steps(plan.id)
      assert hd(steps).metadata == %{"source" => "automation"}
    end

    test "returns error for nonexistent plan" do
      args = %{"plan_id" => Ecto.UUID.generate(), "description" => "Step"}

      assert {:error, "Plan not found"} = AddStep.execute(args, %{})
    end
  end
end
