defmodule PopStash.ActivityTest do
  use PopStash.DataCase, async: true

  alias PopStash.Activity
  alias PopStash.Activity.Item
  alias PopStash.Memory
  alias PopStash.Projects

  setup do
    {:ok, project} = Projects.create("Test Project")
    %{project: project}
  end

  describe "list_recent/1" do
    test "returns empty list when no items exist", %{project: project} do
      items = Activity.list_recent(project_id: project.id)

      assert items == []
    end

    test "returns items sorted by inserted_at descending", %{project: project} do
      {:ok, context1} = Memory.create_context(project.id, "context1", "First context")
      Process.sleep(10)
      {:ok, _insight1} = Memory.create_insight(project.id, "First insight")
      Process.sleep(10)
      {:ok, _decision1} = Memory.create_decision(project.id, "topic1", "First decision")

      items = Activity.list_recent(project_id: project.id)

      assert length(items) == 3
      # Most recent (decision) should be first
      assert hd(items).type == :decision
    end

    test "respects limit option", %{project: project} do
      for i <- 1..5 do
        {:ok, _} = Memory.create_insight(project.id, "Insight #{i}")
      end

      items = Activity.list_recent(project_id: project.id, limit: 3)

      assert length(items) == 3
    end

    test "filters by project_id", %{project: project} do
      {:ok, project2} = Projects.create("Project 2")

      {:ok, _} = Memory.create_insight(project.id, "Project 1 insight")
      {:ok, _} = Memory.create_insight(project2.id, "Project 2 insight")

      items = Activity.list_recent(project_id: project.id)

      assert length(items) == 1
      assert hd(items).title == "Project 1 insight"
    end

    test "includes all projects when project_id is nil", %{project: project} do
      {:ok, project2} = Projects.create("Project 2")

      {:ok, _} = Memory.create_decision(project.id, "topic1", "Project 1 decision")
      {:ok, _} = Memory.create_decision(project2.id, "topic2", "Project 2 decision")

      items = Activity.list_recent(project_id: nil)

      assert length(items) == 2
      topics = items |> Enum.map(& &1.title) |> Enum.sort()
      assert topics == ["topic1", "topic2"]
    end

    test "returns all projects when project_id is nil", %{project: project} do
      {:ok, project2} = Projects.create("Project 2")

      {:ok, _} = Memory.create_context(project.id, "p1-context", "Project 1 context")
      {:ok, _} = Memory.create_context(project2.id, "p2-context", "Project 2 context")

      items = Activity.list_recent(project_id: nil)

      assert length(items) >= 2
      titles = Enum.map(items, & &1.title)
      assert "p1-context" in titles
      assert "p2-context" in titles
    end

    test "filters by types option", %{project: project} do
      {:ok, _} = Memory.create_context(project.id, "context1", "A context")
      {:ok, _} = Memory.create_insight(project.id, "An insight")
      {:ok, _} = Memory.create_decision(project.id, "topic", "A decision")

      context_items = Activity.list_recent(project_id: project.id, types: [:context])
      assert length(context_items) == 1
      assert hd(context_items).type == :context

      insight_items = Activity.list_recent(project_id: project.id, types: [:insight])
      assert length(insight_items) == 1
      assert hd(insight_items).type == :insight

      decision_items = Activity.list_recent(project_id: project.id, types: [:decision])
      assert length(decision_items) == 1
      assert hd(decision_items).type == :decision
    end

    test "filters multiple types", %{project: project} do
      {:ok, _} = Memory.create_context(project.id, "context", "Context")
      {:ok, _} = Memory.create_insight(project.id, "An insight")
      {:ok, _} = Memory.create_decision(project.id, "topic", "A decision")

      items = Activity.list_recent(project_id: project.id, types: [:context, :insight])

      assert length(items) == 2
      types = Enum.map(items, & &1.type)
      assert :context in types
      assert :insight in types
      refute :decision in types
    end

    test "excludes expired contexts", %{project: project} do
      past = DateTime.add(DateTime.utc_now(), -3600, :second)

      {:ok, _} = Memory.create_context(project.id, "expired", "Old context", expires_at: past)
      {:ok, _} = Memory.create_context(project.id, "valid", "Valid context")

      items = Activity.list_recent(project_id: project.id)

      assert length(items) == 1
      assert hd(items).title == "valid"
    end

    test "includes non-expired contexts", %{project: project} do
      future = DateTime.add(DateTime.utc_now(), 3600, :second)

      {:ok, _} = Memory.create_context(project.id, "future", "Valid context", expires_at: future)

      items = Activity.list_recent(project_id: project.id)

      assert length(items) == 1
      assert hd(items).title == "future"
    end
  end

  describe "to_item/1 for contexts" do
    test "converts context to activity item", %{project: project} do
      {:ok, context} =
        Memory.create_context(project.id, "my-context", "This is a summary of the context")

      item = Activity.to_item(context)

      assert %Item{} = item
      assert item.id == context.id
      assert item.type == :context
      assert item.title == "my-context"
      assert item.preview == "This is a summary of the context"
      assert item.project_id == project.id
      assert item.project_name == "Test Project"
      assert item.inserted_at == context.inserted_at
      assert item.source == context
    end

    test "truncates long summaries", %{project: project} do
      long_summary = String.duplicate("a", 150)
      {:ok, context} = Memory.create_context(project.id, "context", long_summary)

      item = Activity.to_item(context)

      assert String.length(item.preview) == 103
      assert String.ends_with?(item.preview, "...")
    end

    test "handles nil summary", %{project: project} do
      {:ok, context} = Memory.create_context(project.id, "context", "short")

      # Manually set summary to nil for testing
      context = %{context | summary: nil}
      item = Activity.to_item(context)

      assert item.preview == nil
    end
  end

  describe "to_item/1 for insights" do
    test "converts insight to activity item", %{project: project} do
      {:ok, insight} = Memory.create_insight(project.id, "This is an insight", key: "my-key")

      item = Activity.to_item(insight)

      assert %Item{} = item
      assert item.id == insight.id
      assert item.type == :insight
      assert item.title == "my-key"
      assert item.preview == "This is an insight"
      assert item.project_id == project.id
      assert item.project_name == "Test Project"
      assert item.inserted_at == insight.inserted_at
      assert item.source == insight
    end

    test "uses truncated content as title when no key", %{project: project} do
      {:ok, insight} = Memory.create_insight(project.id, "This is a long insight content")

      item = Activity.to_item(insight)

      assert item.title == "This is a long insight content"
    end

    test "truncates long content for preview", %{project: project} do
      long_content = String.duplicate("a", 150)
      {:ok, insight} = Memory.create_insight(project.id, long_content)

      item = Activity.to_item(insight)

      assert String.length(item.preview) == 103
      assert String.ends_with?(item.preview, "...")
    end
  end

  describe "to_item/1 for decisions" do
    test "converts decision to activity item", %{project: project} do
      {:ok, decision} =
        Memory.create_decision(project.id, "authentication", "Use JWT tokens",
          reasoning: "Industry standard"
        )

      item = Activity.to_item(decision)

      assert %Item{} = item
      assert item.id == decision.id
      assert item.type == :decision
      assert item.title == "authentication"
      assert item.preview == "Use JWT tokens"
      assert item.project_id == project.id
      assert item.project_name == "Test Project"
      assert item.inserted_at == decision.inserted_at
      assert item.source == decision
    end

    test "truncates long decisions for preview", %{project: project} do
      long_decision = String.duplicate("a", 150)
      {:ok, decision} = Memory.create_decision(project.id, "topic", long_decision)

      item = Activity.to_item(decision)

      assert String.length(item.preview) == 103
      assert String.ends_with?(item.preview, "...")
    end
  end

  describe "to_item/1 for search logs" do
    test "converts search log to activity item", %{project: project} do
      # Create a search log via Memory context
      Memory.log_search(project.id, "test query", :insights, :semantic,
        tool: "recall",
        result_count: 5,
        found: true
      )

      # Wait for async task to complete
      Process.sleep(50)

      # Get the search log from the database
      [search_log] = Memory.list_search_logs(project.id)

      item = Activity.to_item(search_log)

      assert %Item{} = item
      assert item.id == search_log.id
      assert item.type == :search
      assert item.title == "test query"
      assert item.preview == "insights search (5 results)"
      assert item.project_id == project.id
      assert item.project_name == "Test Project"
      assert item.inserted_at == search_log.inserted_at
      assert item.source == search_log
    end

    test "shows not found in preview when no results", %{project: project} do
      Memory.log_search(project.id, "failed query", :insights, :semantic,
        tool: "recall",
        result_count: 0,
        found: false
      )

      # Wait for async task to complete
      Process.sleep(50)

      [search_log] = Memory.list_search_logs(project.id)
      item = Activity.to_item(search_log)

      assert item.preview == "insights search (not found)"
    end
  end
end
