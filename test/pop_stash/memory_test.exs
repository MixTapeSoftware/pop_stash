defmodule PopStash.MemoryTest do
  use PopStash.DataCase, async: true

  alias PopStash.Memory
  alias PopStash.Projects

  setup do
    {:ok, project} = Projects.create("Test Project")
    %{project: project}
  end

  describe "contexts" do
    test "create_context/4 creates a context", %{project: project} do
      assert {:ok, context} =
               Memory.create_context(project.id, "my-work", "Working on auth")

      assert context.title == "my-work"
      assert context.body == "Working on auth"
      assert context.project_id == project.id
    end

    test "create_context/4 accepts files and tags", %{project: project} do
      assert {:ok, context} =
               Memory.create_context(project.id, "test", "summary",
                 files: ["lib/auth.ex"],
                 tags: ["high-priority", "auth"]
               )

      assert context.files == ["lib/auth.ex"]
      assert context.tags == ["high-priority", "auth"]
    end

    test "get_context_by_title/2 retrieves context by exact name", %{project: project} do
      {:ok, context} = Memory.create_context(project.id, "my-work", "Summary")
      assert {:ok, found} = Memory.get_context_by_title(project.id, "my-work")
      assert found.id == context.id
    end

    test "get_context_by_title/2 returns error when not found", %{project: project} do
      assert {:error, :not_found} = Memory.get_context_by_title(project.id, "nonexistent")
    end

    test "get_context_by_title/2 ignores expired contexts", %{project: project} do
      past = DateTime.add(DateTime.utc_now(), -3600, :second)

      {:ok, _} =
        Memory.create_context(project.id, "expired", "Old", expires_at: past)

      assert {:error, :not_found} = Memory.get_context_by_title(project.id, "expired")
    end

    test "get_context_by_title/2 returns non-expired contexts", %{project: project} do
      future = DateTime.add(DateTime.utc_now(), 3600, :second)

      {:ok, context} =
        Memory.create_context(project.id, "future", "Valid", expires_at: future)

      assert {:ok, found} = Memory.get_context_by_title(project.id, "future")
      assert found.id == context.id
    end

    test "list_contexts/1 returns all non-expired contexts", %{project: project} do
      {:ok, _} = Memory.create_context(project.id, "context1", "First")
      {:ok, _} = Memory.create_context(project.id, "context2", "Second")

      contexts = Memory.list_contexts(project.id)
      assert length(contexts) == 2
    end

    test "list_contexts/1 excludes expired contexts", %{project: project} do
      {:ok, _} = Memory.create_context(project.id, "valid", "Valid")

      past = DateTime.add(DateTime.utc_now(), -3600, :second)
      {:ok, _} = Memory.create_context(project.id, "expired", "Old", expires_at: past)

      contexts = Memory.list_contexts(project.id)
      assert length(contexts) == 1
      assert hd(contexts).title == "valid"
    end

    test "delete_context/1 removes a context", %{project: project} do
      {:ok, context} = Memory.create_context(project.id, "temp", "Temp")
      assert :ok = Memory.delete_context(context.id)
      assert {:error, :not_found} = Memory.get_context_by_title(project.id, "temp")
    end

    test "delete_context/1 returns error for nonexistent context" do
      assert {:error, :not_found} = Memory.delete_context(Ecto.UUID.generate())
    end
  end

  describe "insights" do
    test "create_insight/3 creates an insight", %{project: project} do
      assert {:ok, insight} =
               Memory.create_insight(project.id, "Auth uses Guardian")

      assert insight.body == "Auth uses Guardian"
      assert insight.project_id == project.id
    end

    test "create_insight/3 accepts key and tags", %{project: project} do
      assert {:ok, insight} =
               Memory.create_insight(project.id, "Content",
                 title: "auth",
                 tags: ["verified", "important"]
               )

      assert insight.title == "auth"
      assert insight.tags == ["verified", "important"]
    end

    test "get_insight_by_title/2 retrieves insight by key", %{project: project} do
      {:ok, insight} =
        Memory.create_insight(project.id, "JWT patterns", title: "auth-jwt")

      assert {:ok, found} = Memory.get_insight_by_title(project.id, "auth-jwt")
      assert found.id == insight.id
    end

    test "get_insight_by_title/2 returns error when not found", %{project: project} do
      assert {:error, :not_found} = Memory.get_insight_by_title(project.id, "nonexistent")
    end

    test "list_insights/2 returns recent insights", %{project: project} do
      {:ok, _} = Memory.create_insight(project.id, "First")
      {:ok, _} = Memory.create_insight(project.id, "Second")

      insights = Memory.list_insights(project.id, limit: 10)
      assert length(insights) == 2
    end

    test "list_insights/2 respects limit", %{project: project} do
      for i <- 1..10 do
        Memory.create_insight(project.id, "Insight #{i}")
      end

      assert length(Memory.list_insights(project.id, limit: 3)) == 3
    end

    test "update_insight/2 updates body", %{project: project} do
      {:ok, insight} = Memory.create_insight(project.id, "Old content")
      assert {:ok, updated} = Memory.update_insight(insight.id, "New content")
      assert updated.body == "New content"
    end

    test "update_insight/2 returns error for nonexistent insight" do
      assert {:error, :not_found} = Memory.update_insight(Ecto.UUID.generate(), "content")
    end

    test "delete_insight/1 removes an insight", %{project: project} do
      {:ok, insight} = Memory.create_insight(project.id, "Temp", title: "temp")
      assert :ok = Memory.delete_insight(insight.id)
      assert {:error, :not_found} = Memory.get_insight_by_title(project.id, "temp")
    end

    test "delete_insight/1 returns error for nonexistent insight" do
      assert {:error, :not_found} = Memory.delete_insight(Ecto.UUID.generate())
    end
  end

  describe "project isolation" do
    test "contexts are isolated by project" do
      {:ok, project1} = Projects.create("Project 1")
      {:ok, project2} = Projects.create("Project 2")

      {:ok, _} = Memory.create_context(project1.id, "shared-name", "Project 1 context")
      {:ok, _} = Memory.create_context(project2.id, "shared-name", "Project 2 context")

      {:ok, context1} = Memory.get_context_by_title(project1.id, "shared-name")
      {:ok, context2} = Memory.get_context_by_title(project2.id, "shared-name")

      assert context1.body == "Project 1 context"
      assert context2.body == "Project 2 context"
    end

    test "insights are isolated by project" do
      {:ok, project1} = Projects.create("Project 1")
      {:ok, project2} = Projects.create("Project 2")

      {:ok, _} = Memory.create_insight(project1.id, "Insight 1", title: "shared")
      {:ok, _} = Memory.create_insight(project2.id, "Insight 2", title: "shared")

      {:ok, insight1} = Memory.get_insight_by_title(project1.id, "shared")
      {:ok, insight2} = Memory.get_insight_by_title(project2.id, "shared")

      assert insight1.body == "Insight 1"
      assert insight2.body == "Insight 2"
    end
  end

  describe "decisions" do
    test "create_decision/4 creates a decision", %{project: project} do
      assert {:ok, decision} =
               Memory.create_decision(
                 project.id,
                 "Authentication",
                 "Use Guardian for JWT auth"
               )

      # normalized
      assert decision.title == "authentication"
      assert decision.body == "Use Guardian for JWT auth"
      assert decision.project_id == project.id
    end

    test "create_decision/4 accepts reasoning and tags", %{project: project} do
      assert {:ok, decision} =
               Memory.create_decision(project.id, "database", "Use PostgreSQL",
                 reasoning: "Better JSON support than MySQL",
                 tags: ["database", "infrastructure"]
               )

      assert decision.reasoning == "Better JSON support than MySQL"
      assert decision.tags == ["database", "infrastructure"]
    end

    test "create_decision/4 normalizes title (lowercase, trim)", %{project: project} do
      assert {:ok, d1} = Memory.create_decision(project.id, "  AUTH  ", "Decision 1")
      assert {:ok, d2} = Memory.create_decision(project.id, "Auth", "Decision 2")
      assert {:ok, d3} = Memory.create_decision(project.id, "auth", "Decision 3")

      assert d1.title == "auth"
      assert d2.title == "auth"
      assert d3.title == "auth"
    end

    test "get_decision/1 retrieves decision by ID", %{project: project} do
      {:ok, decision} = Memory.create_decision(project.id, "testing", "Use ExUnit")

      assert {:ok, found} = Memory.get_decision(decision.id)
      assert found.id == decision.id
      assert found.title == "testing"
    end

    test "get_decision/1 returns error when not found" do
      assert {:error, :not_found} = Memory.get_decision(Ecto.UUID.generate())
    end

    test "get_decisions_by_title/2 returns all decisions for topic (most recent first)", %{
      project: project
    } do
      {:ok, d1} = Memory.create_decision(project.id, "auth", "First decision")
      # Ensure different timestamps
      Process.sleep(10)
      # Different case
      {:ok, d2} = Memory.create_decision(project.id, "AUTH", "Second decision")
      {:ok, _other} = Memory.create_decision(project.id, "database", "Other topic")

      # Query with different case
      decisions = Memory.get_decisions_by_title(project.id, "Auth")

      assert length(decisions) == 2
      # Most recent first
      assert hd(decisions).id == d2.id
      assert List.last(decisions).id == d1.id
    end

    test "list_decisions/2 returns recent decisions", %{project: project} do
      {:ok, _} = Memory.create_decision(project.id, "topic1", "Decision 1")
      {:ok, _} = Memory.create_decision(project.id, "topic2", "Decision 2")

      decisions = Memory.list_decisions(project.id)
      assert length(decisions) == 2
    end

    test "list_decisions/2 respects limit", %{project: project} do
      for i <- 1..10 do
        Memory.create_decision(project.id, "topic#{i}", "Decision #{i}")
      end

      assert length(Memory.list_decisions(project.id, limit: 3)) == 3
    end

    test "list_decisions/2 filters by title", %{project: project} do
      {:ok, _} = Memory.create_decision(project.id, "auth", "Auth decision")
      {:ok, _} = Memory.create_decision(project.id, "database", "DB decision")

      decisions = Memory.list_decisions(project.id, title: "auth")
      assert length(decisions) == 1
      assert hd(decisions).title == "auth"
    end

    test "list_decisions/2 filters by since datetime", %{project: project} do
      {:ok, _old} = Memory.create_decision(project.id, "old", "Old decision")
      cutoff = DateTime.utc_now()
      Process.sleep(10)
      {:ok, new} = Memory.create_decision(project.id, "new", "New decision")

      decisions = Memory.list_decisions(project.id, since: cutoff)
      assert length(decisions) == 1
      assert hd(decisions).id == new.id
    end

    test "delete_decision/1 removes a decision", %{project: project} do
      {:ok, decision} = Memory.create_decision(project.id, "temp", "Temporary")

      assert :ok = Memory.delete_decision(decision.id)
      assert {:error, :not_found} = Memory.get_decision(decision.id)
    end

    test "delete_decision/1 returns error for nonexistent decision" do
      assert {:error, :not_found} = Memory.delete_decision(Ecto.UUID.generate())
    end

    test "list_decision_titles/1 returns unique topics", %{project: project} do
      {:ok, _} = Memory.create_decision(project.id, "auth", "Decision 1")
      {:ok, _} = Memory.create_decision(project.id, "auth", "Decision 2")
      {:ok, _} = Memory.create_decision(project.id, "database", "Decision 3")
      {:ok, _} = Memory.create_decision(project.id, "api", "Decision 4")

      topics = Memory.list_decision_titles(project.id)
      # Alphabetical order
      assert topics == ["api", "auth", "database"]
    end
  end

  describe "decisions project isolation" do
    test "decisions are isolated by project" do
      {:ok, project1} = Projects.create("Project 1")
      {:ok, project2} = Projects.create("Project 2")

      {:ok, _} = Memory.create_decision(project1.id, "auth", "P1 decision")
      {:ok, _} = Memory.create_decision(project2.id, "auth", "P2 decision")

      p1_decisions = Memory.get_decisions_by_title(project1.id, "auth")
      p2_decisions = Memory.get_decisions_by_title(project2.id, "auth")

      assert length(p1_decisions) == 1
      assert length(p2_decisions) == 1
      assert hd(p1_decisions).body == "P1 decision"
      assert hd(p2_decisions).body == "P2 decision"
    end
  end

  describe "plans" do
    test "create_plan/4 creates a plan", %{project: project} do
      assert {:ok, plan} =
               Memory.create_plan(project.id, "Q1 Roadmap", "Goals for Q1")

      assert plan.title == "Q1 Roadmap"
      assert plan.body == "Goals for Q1"
      assert plan.project_id == project.id
    end

    test "create_plan/4 accepts tags and files", %{project: project} do
      assert {:ok, plan} =
               Memory.create_plan(project.id, "Architecture", "System design",
                 tags: ["architecture", "design"],
                 files: ["docs/architecture.md"]
               )

      assert plan.tags == ["architecture", "design"]
      assert plan.files == ["docs/architecture.md"]
    end

    test "get_plan/2 retrieves plan by title", %{project: project} do
      {:ok, plan} = Memory.create_plan(project.id, "My Plan", "Plan content")
      assert {:ok, found} = Memory.get_plan(project.id, "My Plan")
      assert found.id == plan.id
    end

    test "get_plan/2 returns error when not found", %{project: project} do
      assert {:error, :not_found} = Memory.get_plan(project.id, "nonexistent")
    end

    test "list_plans/2 returns plans for project", %{project: project} do
      {:ok, _} = Memory.create_plan(project.id, "Plan 1", "First")
      {:ok, _} = Memory.create_plan(project.id, "Plan 2", "Second")

      plans = Memory.list_plans(project.id)
      assert length(plans) == 2
    end

    test "list_plans/2 respects limit", %{project: project} do
      for i <- 1..10 do
        Memory.create_plan(project.id, "Plan #{i}", "Content #{i}")
      end

      assert length(Memory.list_plans(project.id, limit: 3)) == 3
    end

    test "list_plans/2 filters by title", %{project: project} do
      {:ok, _} = Memory.create_plan(project.id, "Roadmap", "Roadmap content")
      {:ok, _} = Memory.create_plan(project.id, "Architecture", "Arch content")

      plans = Memory.list_plans(project.id, title: "Roadmap")
      assert length(plans) == 1
      assert hd(plans).title == "Roadmap"
    end

    test "update_plan/2 updates body", %{project: project} do
      {:ok, plan} = Memory.create_plan(project.id, "Test Plan", "Old content")
      assert {:ok, updated} = Memory.update_plan(plan.id, "New content")
      assert updated.body == "New content"
    end

    test "update_plan/2 returns error for nonexistent plan" do
      assert {:error, :not_found} = Memory.update_plan(Ecto.UUID.generate(), "content")
    end

    test "delete_plan/1 removes a plan", %{project: project} do
      {:ok, plan} = Memory.create_plan(project.id, "Temp Plan", "Temporary")
      assert :ok = Memory.delete_plan(plan.id)
      assert {:error, :not_found} = Memory.get_plan(project.id, "Temp Plan")
    end

    test "delete_plan/1 returns error for nonexistent plan" do
      assert {:error, :not_found} = Memory.delete_plan(Ecto.UUID.generate())
    end

    test "list_plan_titles/1 returns unique titles", %{project: project} do
      {:ok, _} = Memory.create_plan(project.id, "Roadmap", "Content 1")
      {:ok, _} = Memory.create_plan(project.id, "Architecture", "Content 2")
      {:ok, _} = Memory.create_plan(project.id, "API Design", "Content 3")

      titles = Memory.list_plan_titles(project.id)
      assert titles == ["API Design", "Architecture", "Roadmap"]
    end
  end

  describe "plans project isolation" do
    test "plans are isolated by project" do
      {:ok, project1} = Projects.create("Project 1")
      {:ok, project2} = Projects.create("Project 2")

      {:ok, _} = Memory.create_plan(project1.id, "Roadmap", "P1 roadmap")
      {:ok, _} = Memory.create_plan(project2.id, "Roadmap", "P2 roadmap")

      {:ok, p1_plan} = Memory.get_plan(project1.id, "Roadmap")
      {:ok, p2_plan} = Memory.get_plan(project2.id, "Roadmap")

      assert p1_plan.body == "P1 roadmap"
      assert p2_plan.body == "P2 roadmap"
    end
  end
end
