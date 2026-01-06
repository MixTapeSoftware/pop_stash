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
end
