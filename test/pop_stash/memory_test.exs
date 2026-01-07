defmodule PopStash.MemoryTest do
  use PopStash.DataCase, async: true

  alias PopStash.{Projects, Agents, Memory}

  setup do
    {:ok, project} = Projects.create("Test Project")
    {:ok, agent} = Agents.connect(project.id, name: "TestAgent")
    %{project: project, agent: agent}
  end

  describe "stashes" do
    test "create_stash/5 creates a stash", %{project: project, agent: agent} do
      assert {:ok, stash} =
               Memory.create_stash(project.id, agent.id, "my-work", "Working on auth")

      assert stash.name == "my-work"
      assert stash.summary == "Working on auth"
      assert stash.project_id == project.id
      assert stash.created_by == agent.id
    end

    test "create_stash/5 accepts files and metadata", %{project: project, agent: agent} do
      assert {:ok, stash} =
               Memory.create_stash(project.id, agent.id, "test", "summary",
                 files: ["lib/auth.ex"],
                 metadata: %{priority: "high"}
               )

      assert stash.files == ["lib/auth.ex"]
      assert stash.metadata == %{priority: "high"}
    end

    test "get_stash_by_name/2 retrieves stash by exact name", %{project: project, agent: agent} do
      {:ok, stash} = Memory.create_stash(project.id, agent.id, "my-work", "Summary")
      assert {:ok, found} = Memory.get_stash_by_name(project.id, "my-work")
      assert found.id == stash.id
    end

    test "get_stash_by_name/2 returns error when not found", %{project: project} do
      assert {:error, :not_found} = Memory.get_stash_by_name(project.id, "nonexistent")
    end

    test "get_stash_by_name/2 ignores expired stashes", %{project: project, agent: agent} do
      past = DateTime.add(DateTime.utc_now(), -3600, :second)

      {:ok, _} =
        Memory.create_stash(project.id, agent.id, "expired", "Old", expires_at: past)

      assert {:error, :not_found} = Memory.get_stash_by_name(project.id, "expired")
    end

    test "get_stash_by_name/2 returns non-expired stashes", %{project: project, agent: agent} do
      future = DateTime.add(DateTime.utc_now(), 3600, :second)

      {:ok, stash} =
        Memory.create_stash(project.id, agent.id, "future", "Valid", expires_at: future)

      assert {:ok, found} = Memory.get_stash_by_name(project.id, "future")
      assert found.id == stash.id
    end

    test "list_stashes/1 returns all non-expired stashes", %{project: project, agent: agent} do
      {:ok, _} = Memory.create_stash(project.id, agent.id, "stash1", "First")
      {:ok, _} = Memory.create_stash(project.id, agent.id, "stash2", "Second")

      stashes = Memory.list_stashes(project.id)
      assert length(stashes) == 2
    end

    test "list_stashes/1 excludes expired stashes", %{project: project, agent: agent} do
      {:ok, _} = Memory.create_stash(project.id, agent.id, "valid", "Valid")

      past = DateTime.add(DateTime.utc_now(), -3600, :second)
      {:ok, _} = Memory.create_stash(project.id, agent.id, "expired", "Old", expires_at: past)

      stashes = Memory.list_stashes(project.id)
      assert length(stashes) == 1
      assert hd(stashes).name == "valid"
    end

    test "delete_stash/1 removes a stash", %{project: project, agent: agent} do
      {:ok, stash} = Memory.create_stash(project.id, agent.id, "temp", "Temp")
      assert {:ok, _} = Memory.delete_stash(stash.id)
      assert {:error, :not_found} = Memory.get_stash_by_name(project.id, "temp")
    end

    test "delete_stash/1 returns error for nonexistent stash" do
      assert {:error, :not_found} = Memory.delete_stash(Ecto.UUID.generate())
    end
  end

  describe "insights" do
    test "create_insight/4 creates an insight", %{project: project, agent: agent} do
      assert {:ok, insight} =
               Memory.create_insight(project.id, agent.id, "Auth uses Guardian")

      assert insight.content == "Auth uses Guardian"
      assert insight.project_id == project.id
      assert insight.created_by == agent.id
    end

    test "create_insight/4 accepts key and metadata", %{project: project, agent: agent} do
      assert {:ok, insight} =
               Memory.create_insight(project.id, agent.id, "Content",
                 key: "auth",
                 metadata: %{verified: true}
               )

      assert insight.key == "auth"
      assert insight.metadata == %{verified: true}
    end

    test "get_insight_by_key/2 retrieves insight by key", %{project: project, agent: agent} do
      {:ok, insight} =
        Memory.create_insight(project.id, agent.id, "JWT patterns", key: "auth-jwt")

      assert {:ok, found} = Memory.get_insight_by_key(project.id, "auth-jwt")
      assert found.id == insight.id
    end

    test "get_insight_by_key/2 returns error when not found", %{project: project} do
      assert {:error, :not_found} = Memory.get_insight_by_key(project.id, "nonexistent")
    end

    test "list_insights/2 returns recent insights", %{project: project, agent: agent} do
      {:ok, _} = Memory.create_insight(project.id, agent.id, "First")
      {:ok, _} = Memory.create_insight(project.id, agent.id, "Second")

      insights = Memory.list_insights(project.id, limit: 10)
      assert length(insights) == 2
    end

    test "list_insights/2 respects limit", %{project: project, agent: agent} do
      for i <- 1..10 do
        Memory.create_insight(project.id, agent.id, "Insight #{i}")
      end

      assert length(Memory.list_insights(project.id, limit: 3)) == 3
    end

    test "update_insight/2 updates content", %{project: project, agent: agent} do
      {:ok, insight} = Memory.create_insight(project.id, agent.id, "Old content")
      assert {:ok, updated} = Memory.update_insight(insight.id, "New content")
      assert updated.content == "New content"
    end

    test "update_insight/2 returns error for nonexistent insight" do
      assert {:error, :not_found} = Memory.update_insight(Ecto.UUID.generate(), "content")
    end

    test "delete_insight/1 removes an insight", %{project: project, agent: agent} do
      {:ok, insight} = Memory.create_insight(project.id, agent.id, "Temp", key: "temp")
      assert {:ok, _} = Memory.delete_insight(insight.id)
      assert {:error, :not_found} = Memory.get_insight_by_key(project.id, "temp")
    end

    test "delete_insight/1 returns error for nonexistent insight" do
      assert {:error, :not_found} = Memory.delete_insight(Ecto.UUID.generate())
    end
  end

  describe "project isolation" do
    test "stashes are isolated by project", %{agent: agent} do
      {:ok, project1} = Projects.create("Project 1")
      {:ok, project2} = Projects.create("Project 2")

      {:ok, _} = Memory.create_stash(project1.id, agent.id, "shared-name", "Project 1 stash")
      {:ok, _} = Memory.create_stash(project2.id, agent.id, "shared-name", "Project 2 stash")

      {:ok, stash1} = Memory.get_stash_by_name(project1.id, "shared-name")
      {:ok, stash2} = Memory.get_stash_by_name(project2.id, "shared-name")

      assert stash1.summary == "Project 1 stash"
      assert stash2.summary == "Project 2 stash"
    end

    test "insights are isolated by project", %{agent: agent} do
      {:ok, project1} = Projects.create("Project 1")
      {:ok, project2} = Projects.create("Project 2")

      {:ok, _} = Memory.create_insight(project1.id, agent.id, "Insight 1", key: "shared")
      {:ok, _} = Memory.create_insight(project2.id, agent.id, "Insight 2", key: "shared")

      {:ok, insight1} = Memory.get_insight_by_key(project1.id, "shared")
      {:ok, insight2} = Memory.get_insight_by_key(project2.id, "shared")

      assert insight1.content == "Insight 1"
      assert insight2.content == "Insight 2"
    end
  end

  describe "decisions" do
    test "create_decision/5 creates a decision", %{project: project, agent: agent} do
      assert {:ok, decision} =
               Memory.create_decision(
                 project.id,
                 agent.id,
                 "Authentication",
                 "Use Guardian for JWT auth"
               )

      # normalized
      assert decision.topic == "authentication"
      assert decision.decision == "Use Guardian for JWT auth"
      assert decision.project_id == project.id
      assert decision.created_by == agent.id
    end

    test "create_decision/5 accepts reasoning and metadata", %{project: project, agent: agent} do
      assert {:ok, decision} =
               Memory.create_decision(project.id, agent.id, "database", "Use PostgreSQL",
                 reasoning: "Better JSON support than MySQL",
                 metadata: %{alternatives_considered: ["MySQL", "SQLite"]}
               )

      assert decision.reasoning == "Better JSON support than MySQL"
      assert decision.metadata == %{alternatives_considered: ["MySQL", "SQLite"]}
    end

    test "create_decision/5 normalizes topic (lowercase, trim)", %{project: project, agent: agent} do
      assert {:ok, d1} = Memory.create_decision(project.id, agent.id, "  AUTH  ", "Decision 1")
      assert {:ok, d2} = Memory.create_decision(project.id, agent.id, "Auth", "Decision 2")
      assert {:ok, d3} = Memory.create_decision(project.id, agent.id, "auth", "Decision 3")

      assert d1.topic == "auth"
      assert d2.topic == "auth"
      assert d3.topic == "auth"
    end

    test "get_decision/1 retrieves decision by ID", %{project: project, agent: agent} do
      {:ok, decision} = Memory.create_decision(project.id, agent.id, "testing", "Use ExUnit")

      assert {:ok, found} = Memory.get_decision(decision.id)
      assert found.id == decision.id
      assert found.topic == "testing"
    end

    test "get_decision/1 returns error when not found" do
      assert {:error, :not_found} = Memory.get_decision(Ecto.UUID.generate())
    end

    test "get_decisions_by_topic/2 returns all decisions for topic (most recent first)", %{
      project: project,
      agent: agent
    } do
      {:ok, d1} = Memory.create_decision(project.id, agent.id, "auth", "First decision")
      # Ensure different timestamps
      Process.sleep(10)
      # Different case
      {:ok, d2} = Memory.create_decision(project.id, agent.id, "AUTH", "Second decision")
      {:ok, _other} = Memory.create_decision(project.id, agent.id, "database", "Other topic")

      # Query with different case
      decisions = Memory.get_decisions_by_topic(project.id, "Auth")

      assert length(decisions) == 2
      # Most recent first
      assert hd(decisions).id == d2.id
      assert List.last(decisions).id == d1.id
    end

    test "list_decisions/2 returns recent decisions", %{project: project, agent: agent} do
      {:ok, _} = Memory.create_decision(project.id, agent.id, "topic1", "Decision 1")
      {:ok, _} = Memory.create_decision(project.id, agent.id, "topic2", "Decision 2")

      decisions = Memory.list_decisions(project.id)
      assert length(decisions) == 2
    end

    test "list_decisions/2 respects limit", %{project: project, agent: agent} do
      for i <- 1..10 do
        Memory.create_decision(project.id, agent.id, "topic#{i}", "Decision #{i}")
      end

      assert length(Memory.list_decisions(project.id, limit: 3)) == 3
    end

    test "list_decisions/2 filters by topic", %{project: project, agent: agent} do
      {:ok, _} = Memory.create_decision(project.id, agent.id, "auth", "Auth decision")
      {:ok, _} = Memory.create_decision(project.id, agent.id, "database", "DB decision")

      decisions = Memory.list_decisions(project.id, topic: "auth")
      assert length(decisions) == 1
      assert hd(decisions).topic == "auth"
    end

    test "list_decisions/2 filters by since datetime", %{project: project, agent: agent} do
      {:ok, _old} = Memory.create_decision(project.id, agent.id, "old", "Old decision")
      cutoff = DateTime.utc_now()
      Process.sleep(10)
      {:ok, new} = Memory.create_decision(project.id, agent.id, "new", "New decision")

      decisions = Memory.list_decisions(project.id, since: cutoff)
      assert length(decisions) == 1
      assert hd(decisions).id == new.id
    end

    test "delete_decision/1 removes a decision", %{project: project, agent: agent} do
      {:ok, decision} = Memory.create_decision(project.id, agent.id, "temp", "Temporary")

      assert {:ok, _} = Memory.delete_decision(decision.id)
      assert {:error, :not_found} = Memory.get_decision(decision.id)
    end

    test "delete_decision/1 returns error for nonexistent decision" do
      assert {:error, :not_found} = Memory.delete_decision(Ecto.UUID.generate())
    end

    test "list_decision_topics/1 returns unique topics", %{project: project, agent: agent} do
      {:ok, _} = Memory.create_decision(project.id, agent.id, "auth", "Decision 1")
      {:ok, _} = Memory.create_decision(project.id, agent.id, "auth", "Decision 2")
      {:ok, _} = Memory.create_decision(project.id, agent.id, "database", "Decision 3")
      {:ok, _} = Memory.create_decision(project.id, agent.id, "api", "Decision 4")

      topics = Memory.list_decision_topics(project.id)
      # Alphabetical order
      assert topics == ["api", "auth", "database"]
    end
  end

  describe "decisions project isolation" do
    test "decisions are isolated by project", %{agent: agent} do
      {:ok, project1} = Projects.create("Project 1")
      {:ok, project2} = Projects.create("Project 2")

      {:ok, _} = Memory.create_decision(project1.id, agent.id, "auth", "P1 decision")
      {:ok, _} = Memory.create_decision(project2.id, agent.id, "auth", "P2 decision")

      p1_decisions = Memory.get_decisions_by_topic(project1.id, "auth")
      p2_decisions = Memory.get_decisions_by_topic(project2.id, "auth")

      assert length(p1_decisions) == 1
      assert length(p2_decisions) == 1
      assert hd(p1_decisions).decision == "P1 decision"
      assert hd(p2_decisions).decision == "P2 decision"
    end
  end
end
