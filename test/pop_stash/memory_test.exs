defmodule PopStash.MemoryTest do
  use PopStash.DataCase, async: true

  alias PopStash.Memory
  alias PopStash.Projects

  setup do
    {:ok, project} = Projects.create("Test Project")
    %{project: project}
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
end
