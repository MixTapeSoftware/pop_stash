defmodule PopStashWeb.API.PlanControllerTest do
  use PopStashWeb.ConnCase, async: true

  alias PopStash.Plans
  alias PopStash.Projects

  setup do
    {:ok, project} = Projects.create("Test Project")
    %{project: project}
  end

  describe "GET /api/plans" do
    test "lists all plans for project", %{conn: conn, project: project} do
      {:ok, plan1} = Plans.create_plan(project.id, "Plan 1", "Content 1")
      {:ok, plan2} = Plans.create_plan(project.id, "Plan 2", "Content 2")

      conn =
        conn
        |> put_req_header("x-project-id", project.id)
        |> get("/api/plans")

      assert %{"plans" => plans} = json_response(conn, 200)
      assert length(plans) == 2

      plan_ids = Enum.map(plans, & &1["id"])
      assert plan1.id in plan_ids
      assert plan2.id in plan_ids
    end

    test "filters plans by title", %{conn: conn, project: project} do
      {:ok, plan1} = Plans.create_plan(project.id, "Roadmap", "Content 1")
      {:ok, _plan2} = Plans.create_plan(project.id, "Architecture", "Content 2")

      conn =
        conn
        |> put_req_header("x-project-id", project.id)
        |> get("/api/plans?title=Roadmap")

      assert %{"plans" => [plan]} = json_response(conn, 200)
      assert plan["id"] == plan1.id
      assert plan["title"] == "Roadmap"
    end

    test "returns empty list when no plans exist", %{conn: conn, project: project} do
      conn =
        conn
        |> put_req_header("x-project-id", project.id)
        |> get("/api/plans")

      assert %{"plans" => []} = json_response(conn, 200)
    end
  end

  describe "POST /api/plans" do
    test "creates a plan with valid data", %{conn: conn, project: project} do
      conn =
        conn
        |> put_req_header("x-project-id", project.id)
        |> put_req_header("content-type", "application/json")
        |> post("/api/plans", %{
          "title" => "New Plan",
          "body" => "Plan content"
        })

      assert %{"plan" => plan} = json_response(conn, 201)
      assert plan["title"] == "New Plan"
      assert plan["body"] == "Plan content"
      assert plan["status"] == "idle"
      assert plan["id"] != nil
    end

    test "creates a plan with tags and files", %{conn: conn, project: project} do
      conn =
        conn
        |> put_req_header("x-project-id", project.id)
        |> put_req_header("content-type", "application/json")
        |> post("/api/plans", %{
          "title" => "Tagged Plan",
          "body" => "Content",
          "tags" => ["tag1", "tag2"],
          "files" => ["file1.ex", "file2.ex"]
        })

      assert %{"plan" => plan} = json_response(conn, 201)
      assert plan["tags"] == ["tag1", "tag2"]
      assert plan["files"] == ["file1.ex", "file2.ex"]
    end

    test "returns error when title is missing", %{conn: conn, project: project} do
      conn =
        conn
        |> put_req_header("x-project-id", project.id)
        |> put_req_header("content-type", "application/json")
        |> post("/api/plans", %{"body" => "Content"})

      assert %{"error" => _} = json_response(conn, 400)
    end

    test "returns error when body is missing", %{conn: conn, project: project} do
      conn =
        conn
        |> put_req_header("x-project-id", project.id)
        |> put_req_header("content-type", "application/json")
        |> post("/api/plans", %{"title" => "Title"})

      assert %{"error" => _} = json_response(conn, 400)
    end
  end

  describe "GET /api/plans/:id" do
    test "returns plan by ID", %{conn: conn, project: project} do
      {:ok, plan} = Plans.create_plan(project.id, "Test Plan", "Content")

      conn = get(conn, "/api/plans/#{plan.id}")

      assert %{"plan" => returned_plan} = json_response(conn, 200)
      assert returned_plan["id"] == plan.id
      assert returned_plan["title"] == "Test Plan"
      assert returned_plan["status"] == "idle"
    end

    test "returns 404 for nonexistent plan", %{conn: conn} do
      conn = get(conn, "/api/plans/#{Ecto.UUID.generate()}")

      assert %{"error" => "Plan not found"} = json_response(conn, 404)
    end
  end

  describe "GET /api/plans/:id/next-step" do
    test "returns next step and marks it in_progress", %{conn: conn, project: project} do
      {:ok, plan} = Plans.create_plan(project.id, "Test Plan", "Content")
      {:ok, step1} = Plans.add_plan_step(plan.id, "Step 1")
      {:ok, _step2} = Plans.add_plan_step(plan.id, "Step 2")

      conn = get(conn, "/api/plans/#{plan.id}/next-step")

      assert %{"status" => "next", "step" => step} = json_response(conn, 200)
      assert step["id"] == step1.id
      assert step["status"] == "in_progress"
    end

    test "returns 'complete' when no pending steps", %{conn: conn, project: project} do
      {:ok, plan} = Plans.create_plan(project.id, "Test Plan", "Content")

      conn = get(conn, "/api/plans/#{plan.id}/next-step")

      assert %{"status" => "complete"} = json_response(conn, 200)
    end

    test "returns 'locked' when plan is already running", %{conn: conn, project: project} do
      {:ok, plan} = Plans.create_plan(project.id, "Test Plan", "Content")
      {:ok, _step} = Plans.add_plan_step(plan.id, "Step 1")

      # First call claims the plan
      {:ok, _} = Plans.get_next_step_and_mark_in_progress(plan.id)

      # Second call should get :plan_locked
      conn = get(conn, "/api/plans/#{plan.id}/next-step")

      assert %{"status" => "locked"} = json_response(conn, 200)
    end

    test "returns 'not_active' when plan is paused", %{conn: conn, project: project} do
      {:ok, plan} = Plans.create_plan(project.id, "Test Plan", "Content")
      {:ok, _step} = Plans.add_plan_step(plan.id, "Step 1")
      {:ok, _} = Plans.pause_plan(plan.id)

      conn = get(conn, "/api/plans/#{plan.id}/next-step")

      assert %{"status" => "not_active"} = json_response(conn, 200)
    end

    test "returns 404 for nonexistent plan", %{conn: conn} do
      conn = get(conn, "/api/plans/#{Ecto.UUID.generate()}/next-step")

      assert %{"error" => "Plan not found"} = json_response(conn, 404)
    end
  end

  describe "GET /api/plans/:id/steps" do
    test "lists all steps for plan ordered by step_number", %{conn: conn, project: project} do
      {:ok, plan} = Plans.create_plan(project.id, "Test Plan", "Content")
      {:ok, _step1} = Plans.add_plan_step(plan.id, "Step 3", step_number: 3.0)
      {:ok, _step2} = Plans.add_plan_step(plan.id, "Step 1", step_number: 1.0)
      {:ok, _step3} = Plans.add_plan_step(plan.id, "Step 2", step_number: 2.0)

      conn = get(conn, "/api/plans/#{plan.id}/steps")

      assert %{"steps" => steps} = json_response(conn, 200)
      assert length(steps) == 3

      # Should be ordered by step_number
      assert Enum.at(steps, 0)["step_number"] == 1.0
      assert Enum.at(steps, 1)["step_number"] == 2.0
      assert Enum.at(steps, 2)["step_number"] == 3.0
    end

    test "filters steps by status", %{conn: conn, project: project} do
      {:ok, plan} = Plans.create_plan(project.id, "Test Plan", "Content")
      {:ok, step1} = Plans.add_plan_step(plan.id, "Step 1")
      {:ok, _step2} = Plans.add_plan_step(plan.id, "Step 2")

      {:ok, _} = Plans.update_plan_step(step1.id, %{status: "in_progress"})

      conn = get(conn, "/api/plans/#{plan.id}/steps?status=pending")

      assert %{"steps" => steps} = json_response(conn, 200)
      assert length(steps) == 1
      assert hd(steps)["description"] == "Step 2"
    end

    test "returns empty list when no steps exist", %{conn: conn, project: project} do
      {:ok, plan} = Plans.create_plan(project.id, "Test Plan", "Content")

      conn = get(conn, "/api/plans/#{plan.id}/steps")

      assert %{"steps" => []} = json_response(conn, 200)
    end
  end

  describe "POST /api/plans/:id/steps" do
    test "adds a step with auto-incremented step_number", %{conn: conn, project: project} do
      {:ok, plan} = Plans.create_plan(project.id, "Test Plan", "Content")

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/plans/#{plan.id}/steps", %{"description" => "New step"})

      assert %{"step" => step} = json_response(conn, 201)
      assert step["description"] == "New step"
      assert step["step_number"] == 1.0
      assert step["status"] == "pending"
    end

    test "adds a step with explicit step_number", %{conn: conn, project: project} do
      {:ok, plan} = Plans.create_plan(project.id, "Test Plan", "Content")

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/plans/#{plan.id}/steps", %{
          "description" => "Step at 5",
          "step_number" => 5.0
        })

      assert %{"step" => step} = json_response(conn, 201)
      assert step["step_number"] == 5.0
    end

    test "adds a step with after_step option", %{conn: conn, project: project} do
      {:ok, plan} = Plans.create_plan(project.id, "Test Plan", "Content")
      {:ok, _} = Plans.add_plan_step(plan.id, "Step 1", step_number: 1.0)
      {:ok, _} = Plans.add_plan_step(plan.id, "Step 2", step_number: 2.0)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/plans/#{plan.id}/steps", %{
          "description" => "Step 1.5",
          "after_step" => 1.0
        })

      assert %{"step" => step} = json_response(conn, 201)
      assert step["step_number"] == 1.5
    end

    test "adds a step with metadata and created_by", %{conn: conn, project: project} do
      {:ok, plan} = Plans.create_plan(project.id, "Test Plan", "Content")

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/plans/#{plan.id}/steps", %{
          "description" => "Agent step",
          "created_by" => "agent",
          "metadata" => %{"source" => "automation"}
        })

      assert %{"step" => step} = json_response(conn, 201)
      assert step["created_by"] == "agent"
      assert step["metadata"]["source"] == "automation"
    end

    test "returns error when description is missing", %{conn: conn, project: project} do
      {:ok, plan} = Plans.create_plan(project.id, "Test Plan", "Content")

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/plans/#{plan.id}/steps", %{})

      assert %{"error" => _} = json_response(conn, 400)
    end

    test "returns 404 for nonexistent plan", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/plans/#{Ecto.UUID.generate()}/steps", %{"description" => "Step"})

      assert %{"error" => "Plan not found"} = json_response(conn, 404)
    end
  end
end
