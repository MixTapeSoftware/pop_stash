defmodule PopStashWeb.API.StepControllerTest do
  use PopStashWeb.ConnCase, async: true

  alias PopStash.Plans
  alias PopStash.Projects

  setup do
    {:ok, project} = Projects.create("Test Project")
    {:ok, plan} = Plans.create_plan(project.id, "Test Plan", "Plan content")
    %{project: project, plan: plan}
  end

  describe "GET /api/steps/:id" do
    test "returns step by ID", %{conn: conn, plan: plan} do
      {:ok, step} = Plans.add_plan_step(plan.id, "Test step")

      conn = get(conn, "/api/steps/#{step.id}")

      assert %{"step" => returned_step} = json_response(conn, 200)
      assert returned_step["id"] == step.id
      assert returned_step["description"] == "Test step"
      assert returned_step["status"] == "pending"
    end

    test "returns 404 for nonexistent step", %{conn: conn} do
      conn = get(conn, "/api/steps/#{Ecto.UUID.generate()}")

      assert %{"error" => "Step not found"} = json_response(conn, 404)
    end
  end

  describe "PATCH /api/steps/:id" do
    test "updates step status", %{conn: conn, plan: plan} do
      {:ok, step} = Plans.add_plan_step(plan.id, "Test step")

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> patch("/api/steps/#{step.id}", %{"status" => "in_progress"})

      assert %{"step" => updated_step} = json_response(conn, 200)
      assert updated_step["status"] == "in_progress"
    end

    test "updates step result", %{conn: conn, plan: plan} do
      {:ok, step} = Plans.add_plan_step(plan.id, "Test step")
      {:ok, _} = Plans.update_plan_step(step.id, %{status: "in_progress"})

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> patch("/api/steps/#{step.id}", %{"result" => "Task completed successfully"})

      assert %{"step" => updated_step} = json_response(conn, 200)
      assert updated_step["result"] == "Task completed successfully"
    end

    test "updates step metadata", %{conn: conn, plan: plan} do
      {:ok, step} = Plans.add_plan_step(plan.id, "Test step")

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> patch("/api/steps/#{step.id}", %{
          "status" => "in_progress",
          "metadata" => %{"duration_ms" => 1500}
        })

      assert %{"step" => updated_step} = json_response(conn, 200)
      assert updated_step["metadata"]["duration_ms"] == 1500
    end

    test "completes step and releases plan when status is 'completed'", %{conn: conn, plan: plan} do
      {:ok, _} = Plans.add_plan_step(plan.id, "Step 1")
      {:ok, step} = Plans.get_next_step_and_mark_in_progress(plan.id)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> patch("/api/steps/#{step.id}", %{
          "status" => "completed",
          "result" => "Done!"
        })

      assert %{"step" => updated_step} = json_response(conn, 200)
      assert updated_step["status"] == "completed"
      assert updated_step["result"] == "Done!"

      # Plan should be idle again
      {:ok, plan} = Plans.get_plan_by_id(plan.id)
      assert plan.status == "idle"
    end

    test "fails step and marks plan failed when status is 'failed'", %{conn: conn, plan: plan} do
      {:ok, _} = Plans.add_plan_step(plan.id, "Step 1")
      {:ok, step} = Plans.get_next_step_and_mark_in_progress(plan.id)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> patch("/api/steps/#{step.id}", %{
          "status" => "failed",
          "result" => "Error occurred"
        })

      assert %{"step" => updated_step} = json_response(conn, 200)
      assert updated_step["status"] == "failed"
      assert updated_step["result"] == "Error occurred"

      # Plan should be failed too
      {:ok, plan} = Plans.get_plan_by_id(plan.id)
      assert plan.status == "failed"
    end

    test "returns error for invalid status transition", %{conn: conn, plan: plan} do
      {:ok, step} = Plans.add_plan_step(plan.id, "Test step")
      {:ok, _} = Plans.update_plan_step(step.id, %{status: "in_progress"})

      # in_progress -> pending is invalid
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> patch("/api/steps/#{step.id}", %{"status" => "pending"})

      assert %{"error" => "Invalid status transition"} = json_response(conn, 422)
    end

    test "returns error when completing step not in_progress", %{conn: conn, plan: plan} do
      {:ok, step} = Plans.add_plan_step(plan.id, "Test step")

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> patch("/api/steps/#{step.id}", %{
          "status" => "completed",
          "result" => "Done"
        })

      assert %{"error" => "Step must be in_progress to complete or fail"} =
               json_response(conn, 422)
    end

    test "returns error when failing step not in_progress", %{conn: conn, plan: plan} do
      {:ok, step} = Plans.add_plan_step(plan.id, "Test step")

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> patch("/api/steps/#{step.id}", %{
          "status" => "failed",
          "result" => "Error"
        })

      assert %{"error" => "Step must be in_progress to complete or fail"} =
               json_response(conn, 422)
    end

    test "returns error when no fields to update", %{conn: conn, plan: plan} do
      {:ok, step} = Plans.add_plan_step(plan.id, "Test step")

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> patch("/api/steps/#{step.id}", %{})

      assert %{"error" => error} = json_response(conn, 400)
      assert error =~ "No valid fields to update"
    end

    test "returns 404 for nonexistent step", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> patch("/api/steps/#{Ecto.UUID.generate()}", %{"status" => "in_progress"})

      assert %{"error" => "Step not found"} = json_response(conn, 404)
    end
  end
end
