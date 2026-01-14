defmodule PopStash.Search.IndexerTest do
  use PopStash.DataCase, async: false

  alias PopStash.Memory
  alias PopStash.Projects
  alias PopStash.Search.Indexer

  setup do
    {:ok, project} = Projects.create("Test Project")
    %{project: project}
  end

  describe "PubSub event handling" do
    test "indexer module has correct structure" do
      # Indexer is not started in test environment (embeddings disabled)
      # This test verifies the module compiles and has correct structure
      # Load the module first
      Code.ensure_loaded!(Indexer)
      assert function_exported?(Indexer, :start_link, 1)
      assert function_exported?(Indexer, :init, 1)
      assert function_exported?(Indexer, :handle_info, 2)
    end
  end

  describe "Memory context broadcasts events" do
    test "create_context broadcasts :context_created", %{project: project} do
      # Subscribe to memory events
      Phoenix.PubSub.subscribe(PopStash.PubSub, "memory:events")

      {:ok, context} = Memory.create_context(project.id, "test-context", "Test summary")

      assert_receive {:context_created, received_context}
      assert received_context.id == context.id
    end

    test "create_insight broadcasts :insight_created", %{project: project} do
      Phoenix.PubSub.subscribe(PopStash.PubSub, "memory:events")

      {:ok, insight} =
        Memory.create_insight(project.id, "Test content", key: "test-key")

      assert_receive {:insight_created, received_insight}
      assert received_insight.id == insight.id
    end

    test "create_decision broadcasts :decision_created", %{project: project} do
      Phoenix.PubSub.subscribe(PopStash.PubSub, "memory:events")

      {:ok, decision} =
        Memory.create_decision(project.id, "test-topic", "Test decision")

      assert_receive {:decision_created, received_decision}
      assert received_decision.id == decision.id
    end

    test "update_insight broadcasts :insight_updated", %{project: project} do
      {:ok, insight} = Memory.create_insight(project.id, "Original content")

      Phoenix.PubSub.subscribe(PopStash.PubSub, "memory:events")

      {:ok, updated} = Memory.update_insight(insight.id, "Updated content")

      assert_receive {:insight_updated, received_insight}
      assert received_insight.id == updated.id
      assert received_insight.content == "Updated content"
    end

    test "delete_context broadcasts :context_deleted", %{project: project} do
      {:ok, context} = Memory.create_context(project.id, "to-delete", "Will be deleted")

      Phoenix.PubSub.subscribe(PopStash.PubSub, "memory:events")

      :ok = Memory.delete_context(context.id)

      assert_receive {:context_deleted, deleted_id}
      assert deleted_id == context.id
    end

    test "delete_insight broadcasts :insight_deleted", %{project: project} do
      {:ok, insight} = Memory.create_insight(project.id, "To delete")

      Phoenix.PubSub.subscribe(PopStash.PubSub, "memory:events")

      :ok = Memory.delete_insight(insight.id)

      assert_receive {:insight_deleted, deleted_id}
      assert deleted_id == insight.id
    end

    test "delete_decision broadcasts :decision_deleted", %{project: project} do
      {:ok, decision} = Memory.create_decision(project.id, "topic", "To delete")

      Phoenix.PubSub.subscribe(PopStash.PubSub, "memory:events")

      :ok = Memory.delete_decision(decision.id)

      assert_receive {:decision_deleted, deleted_id}
      assert deleted_id == decision.id
    end
  end
end
