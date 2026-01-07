defmodule PopStash.AgentsTest do
  use PopStash.DataCase, async: true

  alias PopStash.Agents
  alias PopStash.Projects

  setup do
    {:ok, project} = Projects.create("Test Project")
    %{project: project}
  end

  describe "connect/2" do
    test "creates an active agent", %{project: project} do
      assert {:ok, agent} = Agents.connect(project.id)
      assert agent.project_id == project.id
      assert agent.status == "active"
      assert agent.connected_at
      assert agent.last_seen_at
    end

    test "accepts custom name and metadata", %{project: project} do
      assert {:ok, agent} =
               Agents.connect(project.id, name: "Claude", metadata: %{editor: "cursor"})

      assert agent.name == "Claude"
      assert agent.metadata == %{editor: "cursor"}
    end

    test "validates project exists" do
      assert {:error, changeset} = Agents.connect(Ecto.UUID.generate())
      assert "does not exist" in errors_on(changeset).project_id
    end
  end

  describe "get/1" do
    test "returns agent when found", %{project: project} do
      {:ok, agent} = Agents.connect(project.id)
      assert {:ok, found} = Agents.get(agent.id)
      assert found.id == agent.id
    end

    test "returns error when not found" do
      assert {:error, :not_found} = Agents.get(Ecto.UUID.generate())
    end
  end

  describe "heartbeat/1" do
    test "updates last_seen_at", %{project: project} do
      {:ok, agent} = Agents.connect(project.id)
      old_time = agent.last_seen_at

      Process.sleep(10)
      assert {:ok, updated} = Agents.heartbeat(agent.id)
      assert DateTime.compare(updated.last_seen_at, old_time) == :gt
    end
  end

  describe "disconnect/1" do
    test "marks agent as disconnected", %{project: project} do
      {:ok, agent} = Agents.connect(project.id)
      assert {:ok, updated} = Agents.disconnect(agent.id)
      assert updated.status == "disconnected"
    end
  end

  describe "update_task/2" do
    test "sets current task", %{project: project} do
      {:ok, agent} = Agents.connect(project.id)
      assert {:ok, updated} = Agents.update_task(agent.id, "Implementing auth")
      assert updated.current_task == "Implementing auth"
    end
  end

  describe "list_active/1" do
    test "returns only active agents", %{project: project} do
      {:ok, agent1} = Agents.connect(project.id)
      {:ok, agent2} = Agents.connect(project.id)
      {:ok, _} = Agents.disconnect(agent2.id)

      active = Agents.list_active(project.id)
      assert length(active) == 1
      assert hd(active).id == agent1.id
    end

    test "returns empty list for project with no agents", %{project: project} do
      assert Agents.list_active(project.id) == []
    end
  end

  describe "list_all/1" do
    test "returns all agents regardless of status", %{project: project} do
      {:ok, _} = Agents.connect(project.id)
      {:ok, agent2} = Agents.connect(project.id)
      {:ok, _} = Agents.disconnect(agent2.id)

      all = Agents.list_all(project.id)
      assert length(all) == 2
    end
  end
end
