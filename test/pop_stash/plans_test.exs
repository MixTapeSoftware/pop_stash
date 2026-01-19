defmodule PopStash.PlansTest do
  use PopStash.DataCase, async: true

  alias PopStash.Memory.PlanStep
  alias PopStash.Plans
  alias PopStash.Projects

  setup do
    {:ok, project} = Projects.create("Test Project")
    %{project: project}
  end

  describe "plans" do
    test "create_plan/4 creates a plan", %{project: project} do
      assert {:ok, plan} =
               Plans.create_plan(project.id, "Q1 Roadmap", "Goals for Q1")

      assert plan.title == "Q1 Roadmap"
      assert plan.body == "Goals for Q1"
      assert plan.project_id == project.id
    end

    test "create_plan/4 accepts tags and files", %{project: project} do
      assert {:ok, plan} =
               Plans.create_plan(project.id, "Architecture", "System design",
                 tags: ["architecture", "design"],
                 files: ["docs/architecture.md"]
               )

      assert plan.tags == ["architecture", "design"]
      assert plan.files == ["docs/architecture.md"]
    end

    test "create_plan/4 creates plan with idle status", %{project: project} do
      {:ok, plan} = Plans.create_plan(project.id, "New Plan", "Content")
      assert plan.status == "idle"
    end

    test "get_plan/2 retrieves plan by title", %{project: project} do
      {:ok, plan} = Plans.create_plan(project.id, "My Plan", "Plan content")
      assert {:ok, found} = Plans.get_plan(project.id, "My Plan")
      assert found.id == plan.id
    end

    test "get_plan/2 returns error when not found", %{project: project} do
      assert {:error, :not_found} = Plans.get_plan(project.id, "nonexistent")
    end

    test "get_plan_by_id/1 retrieves plan by ID", %{project: project} do
      {:ok, plan} = Plans.create_plan(project.id, "Test", "Content")
      assert {:ok, found} = Plans.get_plan_by_id(plan.id)
      assert found.id == plan.id
      assert found.status == "idle"
    end

    test "get_plan_by_id/1 returns error for nonexistent plan" do
      assert {:error, :not_found} = Plans.get_plan_by_id(Ecto.UUID.generate())
    end

    test "list_plans/2 returns plans for project", %{project: project} do
      {:ok, _} = Plans.create_plan(project.id, "Plan 1", "First")
      {:ok, _} = Plans.create_plan(project.id, "Plan 2", "Second")

      plans = Plans.list_plans(project.id)
      assert length(plans) == 2
    end

    test "list_plans/2 respects limit", %{project: project} do
      for i <- 1..10 do
        Plans.create_plan(project.id, "Plan #{i}", "Content #{i}")
      end

      assert length(Plans.list_plans(project.id, limit: 3)) == 3
    end

    test "list_plans/2 filters by title", %{project: project} do
      {:ok, _} = Plans.create_plan(project.id, "Roadmap", "Roadmap content")
      {:ok, _} = Plans.create_plan(project.id, "Architecture", "Arch content")

      plans = Plans.list_plans(project.id, title: "Roadmap")
      assert length(plans) == 1
      assert hd(plans).title == "Roadmap"
    end

    test "update_plan/2 updates body", %{project: project} do
      {:ok, plan} = Plans.create_plan(project.id, "Test Plan", "Old content")
      assert {:ok, updated} = Plans.update_plan(plan.id, "New content")
      assert updated.body == "New content"
    end

    test "update_plan/2 returns error for nonexistent plan" do
      assert {:error, :not_found} = Plans.update_plan(Ecto.UUID.generate(), "content")
    end

    test "delete_plan/1 removes a plan", %{project: project} do
      {:ok, plan} = Plans.create_plan(project.id, "Temp Plan", "Temporary")
      assert :ok = Plans.delete_plan(plan.id)
      assert {:error, :not_found} = Plans.get_plan(project.id, "Temp Plan")
    end

    test "delete_plan/1 returns error for nonexistent plan" do
      assert {:error, :not_found} = Plans.delete_plan(Ecto.UUID.generate())
    end

    test "list_plan_titles/1 returns unique titles", %{project: project} do
      {:ok, _} = Plans.create_plan(project.id, "Roadmap", "Content 1")
      {:ok, _} = Plans.create_plan(project.id, "Architecture", "Content 2")
      {:ok, _} = Plans.create_plan(project.id, "API Design", "Content 3")

      titles = Plans.list_plan_titles(project.id)
      assert titles == ["API Design", "Architecture", "Roadmap"]
    end
  end

  describe "plans project isolation" do
    test "plans are isolated by project" do
      {:ok, project1} = Projects.create("Project 1")
      {:ok, project2} = Projects.create("Project 2")

      {:ok, _} = Plans.create_plan(project1.id, "Roadmap", "P1 roadmap")
      {:ok, _} = Plans.create_plan(project2.id, "Roadmap", "P2 roadmap")

      {:ok, p1_plan} = Plans.get_plan(project1.id, "Roadmap")
      {:ok, p2_plan} = Plans.get_plan(project2.id, "Roadmap")

      assert p1_plan.body == "P1 roadmap"
      assert p2_plan.body == "P2 roadmap"
    end
  end

  describe "plan steps" do
    setup %{project: project} do
      {:ok, plan} = Plans.create_plan(project.id, "Test Plan", "Plan body")
      %{project: project, plan: plan}
    end

    test "add_plan_step/3 creates a step with auto-incremented step_number", %{plan: plan} do
      assert {:ok, step1} = Plans.add_plan_step(plan.id, "First step")
      assert step1.step_number == 1.0
      assert step1.description == "First step"
      assert step1.status == "pending"
      assert step1.plan_id == plan.id

      assert {:ok, step2} = Plans.add_plan_step(plan.id, "Second step")
      assert step2.step_number == 2.0

      assert {:ok, step3} = Plans.add_plan_step(plan.id, "Third step")
      assert step3.step_number == 3.0
    end

    test "add_plan_step/3 accepts explicit step_number", %{plan: plan} do
      assert {:ok, step} = Plans.add_plan_step(plan.id, "Step at 5", step_number: 5.0)
      assert step.step_number == 5.0
    end

    test "add_plan_step/3 calculates midpoint with after_step option", %{plan: plan} do
      {:ok, _} = Plans.add_plan_step(plan.id, "Step 1", step_number: 1.0)
      {:ok, _} = Plans.add_plan_step(plan.id, "Step 2", step_number: 2.0)

      # Insert between 1 and 2
      {:ok, middle} = Plans.add_plan_step(plan.id, "Step 1.5", after_step: 1.0)
      assert middle.step_number == 1.5
    end

    test "add_plan_step/3 after_step with no next step adds 1.0", %{plan: plan} do
      {:ok, _} = Plans.add_plan_step(plan.id, "Step 1", step_number: 1.0)

      {:ok, step} = Plans.add_plan_step(plan.id, "Step after 1", after_step: 1.0)
      assert step.step_number == 2.0
    end

    test "add_plan_step/3 accepts created_by and metadata", %{plan: plan} do
      {:ok, step} =
        Plans.add_plan_step(plan.id, "Agent step",
          created_by: "agent",
          metadata: %{"source" => "automation"}
        )

      assert step.created_by == "agent"
      assert step.metadata == %{"source" => "automation"}
    end

    test "add_plan_step/3 returns error for nonexistent plan" do
      assert {:error, :not_found} = Plans.add_plan_step(Ecto.UUID.generate(), "Step")
    end

    test "add_plan_step/3 rejects duplicate step_numbers (unique constraint)", %{plan: plan} do
      {:ok, _} = Plans.add_plan_step(plan.id, "Step 1", step_number: 1.0)

      # Attempting to add another step with the same step_number should fail due to unique constraint
      assert {:error, changeset} = Plans.add_plan_step(plan.id, "Duplicate", step_number: 1.0)

      # The error will be on the changeset, could be on plan_id_step_number or step_number
      assert changeset.valid? == false
      refute Enum.empty?(changeset.errors)
    end

    test "get_next_plan_step/1 returns first pending step", %{plan: plan} do
      {:ok, step1} = Plans.add_plan_step(plan.id, "Step 1")
      {:ok, _step2} = Plans.add_plan_step(plan.id, "Step 2")

      next = Plans.get_next_plan_step(plan.id)
      assert next.id == step1.id
    end

    test "get_next_plan_step/1 returns nil when no pending steps", %{plan: plan} do
      assert Plans.get_next_plan_step(plan.id) == nil
    end

    test "get_next_plan_step/1 skips non-pending steps", %{plan: plan} do
      {:ok, step1} = Plans.add_plan_step(plan.id, "Step 1")
      {:ok, step2} = Plans.add_plan_step(plan.id, "Step 2")

      # Mark step1 as in_progress
      {:ok, _} = Plans.update_plan_step(step1.id, %{status: "in_progress"})

      next = Plans.get_next_plan_step(plan.id)
      assert next.id == step2.id
    end

    test "get_next_step_and_mark_in_progress/1 claims plan and gets step", %{plan: plan} do
      {:ok, step1} = Plans.add_plan_step(plan.id, "Step 1")
      {:ok, _step2} = Plans.add_plan_step(plan.id, "Step 2")

      assert {:ok, marked} = Plans.get_next_step_and_mark_in_progress(plan.id)
      assert marked.id == step1.id
      assert marked.status == "in_progress"

      # Plan is now running - next call returns :plan_locked
      assert {:ok, :plan_locked} = Plans.get_next_step_and_mark_in_progress(plan.id)

      # Complete the step to release the plan
      {:ok, _} = Plans.complete_plan_step(marked.id)

      # Now we can get the next step
      assert {:ok, marked2} = Plans.get_next_step_and_mark_in_progress(plan.id)
      assert marked2.description == "Step 2"
      assert marked2.status == "in_progress"
    end

    test "get_next_step_and_mark_in_progress/1 returns :plan_completed when no pending steps", %{
      plan: plan
    } do
      assert {:ok, :plan_completed} = Plans.get_next_step_and_mark_in_progress(plan.id)

      # Plan is now completed
      {:ok, plan} = Plans.get_plan_by_id(plan.id)
      assert plan.status == "completed"
    end

    test "get_next_step_and_mark_in_progress/1 returns :plan_not_active for paused plan", %{
      plan: plan
    } do
      {:ok, _} = Plans.add_plan_step(plan.id, "Step 1")
      {:ok, _} = Plans.pause_plan(plan.id)

      assert {:ok, :plan_not_active} = Plans.get_next_step_and_mark_in_progress(plan.id)
    end

    test "get_next_step_and_mark_in_progress/1 returns error for nonexistent plan" do
      assert {:error, :not_found} =
               Plans.get_next_step_and_mark_in_progress(Ecto.UUID.generate())
    end

    test "get_next_step_and_mark_in_progress/1 concurrent calls get different steps or locked",
         %{plan: plan} do
      # Create multiple pending steps
      {:ok, step1} = Plans.add_plan_step(plan.id, "Step 1")
      {:ok, step2} = Plans.add_plan_step(plan.id, "Step 2")
      {:ok, _step3} = Plans.add_plan_step(plan.id, "Step 3")

      # Simulate concurrent calls from different agents/processes
      task1 =
        Task.async(fn ->
          Plans.get_next_step_and_mark_in_progress(plan.id)
        end)

      task2 =
        Task.async(fn ->
          Plans.get_next_step_and_mark_in_progress(plan.id)
        end)

      result1 = Task.await(task1)
      result2 = Task.await(task2)

      # One should get a step, the other should get :plan_locked
      results = [result1, result2]
      successful_claims = Enum.count(results, &match?({:ok, %PlanStep{}}, &1))
      locked_claims = Enum.count(results, &match?({:ok, :plan_locked}, &1))

      assert successful_claims == 1
      assert locked_claims == 1

      # The successful claim should have gotten step1
      successful_step =
        Enum.find_value(results, fn
          {:ok, %PlanStep{} = step} -> step
          _ -> nil
        end)

      assert successful_step.id == step1.id
      assert successful_step.status == "in_progress"

      # Complete the step to release the plan
      {:ok, _} = Plans.complete_plan_step(successful_step.id)

      # Now another agent can claim the next step
      {:ok, next_step} = Plans.get_next_step_and_mark_in_progress(plan.id)
      assert next_step.id == step2.id
    end

    test "update_plan_step/2 updates status", %{plan: plan} do
      {:ok, step} = Plans.add_plan_step(plan.id, "Step 1")

      {:ok, updated} = Plans.update_plan_step(step.id, %{status: "in_progress"})
      assert updated.status == "in_progress"
    end

    test "update_plan_step/2 updates result and metadata", %{plan: plan} do
      {:ok, step} = Plans.add_plan_step(plan.id, "Step 1")
      {:ok, _} = Plans.update_plan_step(step.id, %{status: "in_progress"})

      {:ok, updated} =
        Plans.update_plan_step(step.id, %{
          status: "completed",
          result: "Task done successfully",
          metadata: %{"duration_ms" => 1500}
        })

      assert updated.status == "completed"
      assert updated.result == "Task done successfully"
      assert updated.metadata == %{"duration_ms" => 1500}
    end

    test "update_plan_step/2 validates status transitions", %{plan: plan} do
      {:ok, step} = Plans.add_plan_step(plan.id, "Step 1")

      # pending -> completed is invalid (must go through in_progress)
      assert {:error, :invalid_status_transition} =
               Plans.update_plan_step(step.id, %{status: "completed"})

      # pending -> in_progress is valid
      {:ok, _} = Plans.update_plan_step(step.id, %{status: "in_progress"})

      # in_progress -> pending is invalid
      assert {:error, :invalid_status_transition} =
               Plans.update_plan_step(step.id, %{status: "pending"})
    end

    test "update_plan_step/2 allows in_progress -> failed", %{plan: plan} do
      {:ok, step} = Plans.add_plan_step(plan.id, "Step 1")
      {:ok, _} = Plans.update_plan_step(step.id, %{status: "in_progress"})

      {:ok, updated} =
        Plans.update_plan_step(step.id, %{status: "failed", result: "Error occurred"})

      assert updated.status == "failed"
      assert updated.result == "Error occurred"
    end

    test "update_plan_step/2 returns error for nonexistent step" do
      assert {:error, :not_found} =
               Plans.update_plan_step(Ecto.UUID.generate(), %{status: "in_progress"})
    end

    test "list_plan_steps/2 returns steps ordered by step_number", %{plan: plan} do
      {:ok, _} = Plans.add_plan_step(plan.id, "Step 3", step_number: 3.0)
      {:ok, _} = Plans.add_plan_step(plan.id, "Step 1", step_number: 1.0)
      {:ok, _} = Plans.add_plan_step(plan.id, "Step 2", step_number: 2.0)

      steps = Plans.list_plan_steps(plan.id)
      assert length(steps) == 3
      assert Enum.map(steps, & &1.step_number) == [1.0, 2.0, 3.0]
    end

    test "list_plan_steps/2 filters by status", %{plan: plan} do
      {:ok, step1} = Plans.add_plan_step(plan.id, "Step 1")
      {:ok, _step2} = Plans.add_plan_step(plan.id, "Step 2")
      {:ok, _} = Plans.update_plan_step(step1.id, %{status: "in_progress"})

      pending_steps = Plans.list_plan_steps(plan.id, status: "pending")
      assert length(pending_steps) == 1

      in_progress_steps = Plans.list_plan_steps(plan.id, status: "in_progress")
      assert length(in_progress_steps) == 1
    end

    test "get_plan_step/2 retrieves step by plan_id and step_number", %{plan: plan} do
      {:ok, step} = Plans.add_plan_step(plan.id, "Step at 2.5", step_number: 2.5)

      found = Plans.get_plan_step(plan.id, 2.5)
      assert found.id == step.id
    end

    test "get_plan_step/2 returns nil when not found", %{plan: plan} do
      assert Plans.get_plan_step(plan.id, 999.0) == nil
    end

    test "get_plan_step_by_id/1 retrieves step by ID", %{plan: plan} do
      {:ok, step} = Plans.add_plan_step(plan.id, "Step 1")

      found = Plans.get_plan_step_by_id(step.id)
      assert found.id == step.id
    end

    test "get_plan_step_by_id/1 returns nil when not found" do
      assert Plans.get_plan_step_by_id(Ecto.UUID.generate()) == nil
    end

    # complete_plan_step tests

    test "complete_plan_step/2 marks step completed and plan idle", %{plan: plan} do
      {:ok, _} = Plans.add_plan_step(plan.id, "Step 1")
      {:ok, step} = Plans.get_next_step_and_mark_in_progress(plan.id)

      {:ok, completed} = Plans.complete_plan_step(step.id, result: "Done!")
      assert completed.status == "completed"
      assert completed.result == "Done!"

      # Plan should be idle again
      {:ok, plan} = Plans.get_plan_by_id(plan.id)
      assert plan.status == "idle"
    end

    test "complete_plan_step/2 merges metadata", %{plan: plan} do
      {:ok, _} = Plans.add_plan_step(plan.id, "Step 1", metadata: %{"created" => true})
      {:ok, step} = Plans.get_next_step_and_mark_in_progress(plan.id)

      {:ok, completed} = Plans.complete_plan_step(step.id, metadata: %{"duration_ms" => 100})
      assert completed.metadata == %{"created" => true, "duration_ms" => 100}
    end

    test "complete_plan_step/2 returns error for step not in_progress", %{plan: plan} do
      {:ok, step} = Plans.add_plan_step(plan.id, "Step 1")

      assert {:error, :step_not_in_progress} = Plans.complete_plan_step(step.id)
    end

    test "complete_plan_step/2 returns error for nonexistent step" do
      assert {:error, :not_found} = Plans.complete_plan_step(Ecto.UUID.generate())
    end

    # fail_plan_step tests

    test "fail_plan_step/2 marks step and plan as failed", %{plan: plan} do
      {:ok, _} = Plans.add_plan_step(plan.id, "Step 1")
      {:ok, step} = Plans.get_next_step_and_mark_in_progress(plan.id)

      {:ok, failed} = Plans.fail_plan_step(step.id, result: "Something went wrong")
      assert failed.status == "failed"
      assert failed.result == "Something went wrong"

      # Plan should be failed too
      {:ok, plan} = Plans.get_plan_by_id(plan.id)
      assert plan.status == "failed"
    end

    test "fail_plan_step/2 returns error for step not in_progress", %{plan: plan} do
      {:ok, step} = Plans.add_plan_step(plan.id, "Step 1")

      assert {:error, :step_not_in_progress} = Plans.fail_plan_step(step.id)
    end

    # pause_plan / resume_plan tests

    test "pause_plan/1 pauses an idle plan", %{plan: plan} do
      {:ok, paused} = Plans.pause_plan(plan.id)
      assert paused.status == "paused"
    end

    test "pause_plan/1 pauses a running plan", %{plan: plan} do
      {:ok, _} = Plans.add_plan_step(plan.id, "Step 1")
      {:ok, _step} = Plans.get_next_step_and_mark_in_progress(plan.id)

      {:ok, paused} = Plans.pause_plan(plan.id)
      assert paused.status == "paused"
    end

    test "pause_plan/1 returns error for completed plan", %{plan: plan} do
      # Mark plan completed by having no steps
      {:ok, :plan_completed} = Plans.get_next_step_and_mark_in_progress(plan.id)

      assert {:error, :cannot_pause} = Plans.pause_plan(plan.id)
    end

    test "pause_plan/1 returns error for nonexistent plan" do
      assert {:error, :not_found} = Plans.pause_plan(Ecto.UUID.generate())
    end

    test "resume_plan/1 resumes a paused plan", %{plan: plan} do
      {:ok, _} = Plans.pause_plan(plan.id)

      {:ok, resumed} = Plans.resume_plan(plan.id)
      assert resumed.status == "idle"
    end

    test "resume_plan/1 returns error for non-paused plan", %{plan: plan} do
      assert {:error, :not_paused} = Plans.resume_plan(plan.id)
    end

    test "resume_plan/1 returns error for nonexistent plan" do
      assert {:error, :not_found} = Plans.resume_plan(Ecto.UUID.generate())
    end

    # defer_plan_step / undefer_plan_step tests

    test "defer_plan_step/1 marks step as deferred", %{plan: plan} do
      {:ok, step} = Plans.add_plan_step(plan.id, "Step 1")

      {:ok, deferred} = Plans.defer_plan_step(step.id)
      assert deferred.status == "deferred"
    end

    test "defer_plan_step/1 returns error for non-pending step", %{plan: plan} do
      {:ok, _} = Plans.add_plan_step(plan.id, "Step 1")
      {:ok, step} = Plans.get_next_step_and_mark_in_progress(plan.id)

      assert {:error, :can_only_defer_pending} = Plans.defer_plan_step(step.id)
    end

    test "defer_plan_step/1 returns error for nonexistent step" do
      assert {:error, :not_found} = Plans.defer_plan_step(Ecto.UUID.generate())
    end

    test "undefer_plan_step/1 makes step pending again", %{plan: plan} do
      {:ok, step} = Plans.add_plan_step(plan.id, "Step 1")
      {:ok, _} = Plans.defer_plan_step(step.id)

      {:ok, undeferred} = Plans.undefer_plan_step(step.id)
      assert undeferred.status == "pending"
    end

    test "undefer_plan_step/1 returns error for non-deferred step", %{plan: plan} do
      {:ok, step} = Plans.add_plan_step(plan.id, "Step 1")

      assert {:error, :not_deferred} = Plans.undefer_plan_step(step.id)
    end

    test "undefer_plan_step/1 returns error for nonexistent step" do
      assert {:error, :not_found} = Plans.undefer_plan_step(Ecto.UUID.generate())
    end

    test "deferred steps are skipped by get_next_step_and_mark_in_progress", %{plan: plan} do
      {:ok, step1} = Plans.add_plan_step(plan.id, "Step 1")
      {:ok, step2} = Plans.add_plan_step(plan.id, "Step 2")

      # Defer step 1
      {:ok, _} = Plans.defer_plan_step(step1.id)

      # Should get step 2, not step 1
      {:ok, marked} = Plans.get_next_step_and_mark_in_progress(plan.id)
      assert marked.id == step2.id
    end

    # mark_plan_step_outdated tests

    test "mark_plan_step_outdated/2 marks pending step as outdated", %{plan: plan} do
      {:ok, step} = Plans.add_plan_step(plan.id, "Step 1")

      {:ok, outdated} =
        Plans.mark_plan_step_outdated(step.id, result: "Replaced by updated approach")

      assert outdated.status == "outdated"
      assert outdated.result == "Replaced by updated approach"
    end

    test "mark_plan_step_outdated/2 marks in_progress step as outdated and releases plan", %{
      plan: plan
    } do
      {:ok, _} = Plans.add_plan_step(plan.id, "Step 1")
      {:ok, _} = Plans.add_plan_step(plan.id, "Step 2")
      {:ok, step1} = Plans.get_next_step_and_mark_in_progress(plan.id)

      # Plan should be running
      {:ok, plan_before} = Plans.get_plan_by_id(plan.id)
      assert plan_before.status == "running"

      # Mark the in_progress step as outdated
      {:ok, outdated} = Plans.mark_plan_step_outdated(step1.id, result: "No longer needed")

      assert outdated.status == "outdated"

      # Plan should be idle again
      {:ok, plan_after} = Plans.get_plan_by_id(plan.id)
      assert plan_after.status == "idle"

      # Should be able to claim next step
      {:ok, step2} = Plans.get_next_step_and_mark_in_progress(plan.id)
      assert step2.description == "Step 2"
    end

    test "mark_plan_step_outdated/2 merges metadata", %{plan: plan} do
      {:ok, step} = Plans.add_plan_step(plan.id, "Step 1", metadata: %{"original" => true})

      {:ok, outdated} =
        Plans.mark_plan_step_outdated(step.id, metadata: %{"replacement_steps" => [2.1, 2.2]})

      assert outdated.metadata == %{"original" => true, "replacement_steps" => [2.1, 2.2]}
    end

    test "mark_plan_step_outdated/2 returns error for completed step", %{plan: plan} do
      {:ok, _} = Plans.add_plan_step(plan.id, "Step 1")
      {:ok, step} = Plans.get_next_step_and_mark_in_progress(plan.id)
      {:ok, _} = Plans.complete_plan_step(step.id)

      assert {:error, :cannot_mark_outdated} = Plans.mark_plan_step_outdated(step.id)
    end

    test "mark_plan_step_outdated/2 returns error for failed step", %{plan: plan} do
      {:ok, _} = Plans.add_plan_step(plan.id, "Step 1")
      {:ok, step} = Plans.get_next_step_and_mark_in_progress(plan.id)
      {:ok, _} = Plans.fail_plan_step(step.id)

      assert {:error, :cannot_mark_outdated} = Plans.mark_plan_step_outdated(step.id)
    end

    test "mark_plan_step_outdated/2 returns error for deferred step", %{plan: plan} do
      {:ok, step} = Plans.add_plan_step(plan.id, "Step 1")
      {:ok, _} = Plans.defer_plan_step(step.id)

      assert {:error, :cannot_mark_outdated} = Plans.mark_plan_step_outdated(step.id)
    end

    test "mark_plan_step_outdated/2 returns error for already outdated step", %{plan: plan} do
      {:ok, step} = Plans.add_plan_step(plan.id, "Step 1")
      {:ok, _} = Plans.mark_plan_step_outdated(step.id)

      assert {:error, :cannot_mark_outdated} = Plans.mark_plan_step_outdated(step.id)
    end

    test "mark_plan_step_outdated/2 returns error for nonexistent step" do
      assert {:error, :not_found} = Plans.mark_plan_step_outdated(Ecto.UUID.generate())
    end

    test "outdated steps are skipped by get_next_step_and_mark_in_progress", %{plan: plan} do
      {:ok, step1} = Plans.add_plan_step(plan.id, "Step 1")
      {:ok, step2} = Plans.add_plan_step(plan.id, "Step 2")

      # Mark step 1 as outdated
      {:ok, _} = Plans.mark_plan_step_outdated(step1.id, result: "Not needed")

      # Should get step 2, not step 1
      {:ok, marked} = Plans.get_next_step_and_mark_in_progress(plan.id)
      assert marked.id == step2.id
    end

    test "can mark pending step as outdated via update_plan_step", %{plan: plan} do
      {:ok, step} = Plans.add_plan_step(plan.id, "Step 1")

      {:ok, updated} = Plans.update_plan_step(step.id, %{status: "outdated"})
      assert updated.status == "outdated"
    end

    test "can mark in_progress step as outdated via update_plan_step", %{plan: plan} do
      {:ok, _} = Plans.add_plan_step(plan.id, "Step 1")
      {:ok, step} = Plans.get_next_step_and_mark_in_progress(plan.id)

      {:ok, updated} = Plans.update_plan_step(step.id, %{status: "outdated"})
      assert updated.status == "outdated"
    end

    test "outdated is a terminal state", %{plan: plan} do
      {:ok, step} = Plans.add_plan_step(plan.id, "Step 1")
      {:ok, _} = Plans.mark_plan_step_outdated(step.id)

      # Cannot transition back to pending
      assert {:error, :invalid_status_transition} =
               Plans.update_plan_step(step.id, %{status: "pending"})

      # Cannot transition to in_progress
      assert {:error, :invalid_status_transition} =
               Plans.update_plan_step(step.id, %{status: "in_progress"})

      # Cannot transition to completed
      assert {:error, :invalid_status_transition} =
               Plans.update_plan_step(step.id, %{status: "completed"})
    end

    # Plan status field tests

    test "new plans have idle status", %{plan: plan} do
      assert plan.status == "idle"
    end

    test "plan transitions through statuses correctly", %{plan: plan} do
      {:ok, _} = Plans.add_plan_step(plan.id, "Step 1")
      {:ok, _} = Plans.add_plan_step(plan.id, "Step 2")

      # Start: idle
      {:ok, plan} = Plans.get_plan_by_id(plan.id)
      assert plan.status == "idle"

      # Claim step: running
      {:ok, step1} = Plans.get_next_step_and_mark_in_progress(plan.id)
      {:ok, plan} = Plans.get_plan_by_id(plan.id)
      assert plan.status == "running"

      # Complete step: idle
      {:ok, _} = Plans.complete_plan_step(step1.id)
      {:ok, plan} = Plans.get_plan_by_id(plan.id)
      assert plan.status == "idle"

      # Claim next step: running
      {:ok, step2} = Plans.get_next_step_and_mark_in_progress(plan.id)
      {:ok, plan} = Plans.get_plan_by_id(plan.id)
      assert plan.status == "running"

      # Complete last step: idle (step marked complete, plan goes idle)
      {:ok, _} = Plans.complete_plan_step(step2.id)
      {:ok, plan} = Plans.get_plan_by_id(plan.id)
      assert plan.status == "idle"

      # No more steps: completed
      {:ok, :plan_completed} = Plans.get_next_step_and_mark_in_progress(plan.id)
      {:ok, plan} = Plans.get_plan_by_id(plan.id)
      assert plan.status == "completed"
    end
  end
end
