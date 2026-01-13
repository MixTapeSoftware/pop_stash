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
    test "returns empty list when no items exist", %{project: _project} do
      # Create a fresh project with no items
      {:ok, empty_project} = Projects.create("Empty Project")
      items = Activity.list_recent(project_id: empty_project.id)
      assert items == []
    end

    test "returns items sorted by inserted_at descending", %{project: project} do
      {:ok, stash1} = Memory.create_stash(project.id, "stash1", "First stash")
      Process.sleep(10)
      {:ok, _insight1} = Memory.create_insight(project.id, "First insight")
      Process.sleep(10)
      {:ok, _decision1} = Memory.create_decision(project.id, "topic", "A decision")

      items = Activity.list_recent(project_id: project.id)

      assert length(items) == 3
      # Most recent first (decision)
      assert hd(items).type == :decision
      # Oldest last (stash)
      assert List.last(items).id == stash1.id
    end

    test "respects limit option", %{project: project} do
      for i <- 1..10 do
        Memory.create_stash(project.id, "stash#{i}", "Stash #{i}")
      end

      items = Activity.list_recent(project_id: project.id, limit: 5)
      assert length(items) == 5
    end

    test "defaults to limit of 20", %{project: project} do
      for i <- 1..25 do
        Memory.create_stash(project.id, "stash#{i}", "Stash #{i}")
      end

      items = Activity.list_recent(project_id: project.id)
      assert length(items) == 20
    end

    test "filters by project_id", %{project: project} do
      {:ok, project2} = Projects.create("Project 2")

      {:ok, _} = Memory.create_stash(project.id, "p1-stash", "Project 1 stash")
      {:ok, _} = Memory.create_stash(project2.id, "p2-stash", "Project 2 stash")

      items1 = Activity.list_recent(project_id: project.id)
      items2 = Activity.list_recent(project_id: project2.id)

      assert length(items1) == 1
      assert hd(items1).title == "p1-stash"

      assert length(items2) == 1
      assert hd(items2).title == "p2-stash"
    end

    test "returns all projects when project_id is nil", %{project: project} do
      {:ok, project2} = Projects.create("Project 2")

      {:ok, _} = Memory.create_stash(project.id, "p1-stash", "Project 1 stash")
      {:ok, _} = Memory.create_stash(project2.id, "p2-stash", "Project 2 stash")

      items = Activity.list_recent(project_id: nil)

      assert length(items) >= 2
      titles = Enum.map(items, & &1.title)
      assert "p1-stash" in titles
      assert "p2-stash" in titles
    end

    test "filters by types option", %{project: project} do
      {:ok, _} = Memory.create_stash(project.id, "stash1", "A stash")
      {:ok, _} = Memory.create_insight(project.id, "An insight")
      {:ok, _} = Memory.create_decision(project.id, "topic", "A decision")

      stash_items = Activity.list_recent(project_id: project.id, types: [:stash])
      assert length(stash_items) == 1
      assert hd(stash_items).type == :stash

      insight_items = Activity.list_recent(project_id: project.id, types: [:insight])
      assert length(insight_items) == 1
      assert hd(insight_items).type == :insight

      decision_items = Activity.list_recent(project_id: project.id, types: [:decision])
      assert length(decision_items) == 1
      assert hd(decision_items).type == :decision
    end

    test "filters multiple types", %{project: project} do
      {:ok, _} = Memory.create_stash(project.id, "stash1", "A stash")
      {:ok, _} = Memory.create_insight(project.id, "An insight")
      {:ok, _} = Memory.create_decision(project.id, "topic", "A decision")

      items = Activity.list_recent(project_id: project.id, types: [:stash, :insight])

      assert length(items) == 2
      types = Enum.map(items, & &1.type)
      assert :stash in types
      assert :insight in types
      refute :decision in types
    end

    test "excludes expired stashes", %{project: project} do
      past = DateTime.add(DateTime.utc_now(), -3600, :second)

      {:ok, _} = Memory.create_stash(project.id, "expired", "Old stash", expires_at: past)
      {:ok, _} = Memory.create_stash(project.id, "valid", "Valid stash")

      items = Activity.list_recent(project_id: project.id)

      assert length(items) == 1
      assert hd(items).title == "valid"
    end

    test "includes non-expired stashes", %{project: project} do
      future = DateTime.add(DateTime.utc_now(), 3600, :second)

      {:ok, _} = Memory.create_stash(project.id, "future", "Valid stash", expires_at: future)

      items = Activity.list_recent(project_id: project.id)

      assert length(items) == 1
      assert hd(items).title == "future"
    end
  end

  describe "to_item/1 for stashes" do
    test "converts stash to activity item", %{project: project} do
      {:ok, stash} =
        Memory.create_stash(project.id, "my-stash", "This is a summary of the stash")

      item = Activity.to_item(stash)

      assert %Item{} = item
      assert item.id == stash.id
      assert item.type == :stash
      assert item.title == "my-stash"
      assert item.preview == "This is a summary of the stash"
      assert item.project_id == project.id
      assert item.project_name == "Test Project"
      assert item.inserted_at == stash.inserted_at
      assert item.source == stash
    end

    test "truncates long summaries", %{project: project} do
      long_summary = String.duplicate("a", 150)
      {:ok, stash} = Memory.create_stash(project.id, "stash", long_summary)

      item = Activity.to_item(stash)

      assert String.length(item.preview) == 103
      assert String.ends_with?(item.preview, "...")
    end

    test "handles nil summary", %{project: project} do
      {:ok, stash} = Memory.create_stash(project.id, "stash", "short")

      # Manually set summary to nil for testing
      stash = %{stash | summary: nil}
      item = Activity.to_item(stash)

      assert item.preview == nil
    end
  end

  describe "to_item/1 for decisions" do
    test "converts decision to activity item", %{project: project} do
      {:ok, decision} =
        Memory.create_decision(project.id, "Authentication", "Use Guardian for JWT")

      item = Activity.to_item(decision)

      assert %Item{} = item
      assert item.id == decision.id
      assert item.type == :decision
      # normalized topic
      assert item.title == "authentication"
      assert item.preview == "Use Guardian for JWT"
      assert item.project_id == project.id
      assert item.project_name == "Test Project"
      assert item.inserted_at == decision.inserted_at
      assert item.source == decision
    end

    test "truncates long decisions", %{project: project} do
      long_decision = String.duplicate("b", 150)
      {:ok, decision} = Memory.create_decision(project.id, "topic", long_decision)

      item = Activity.to_item(decision)

      assert String.length(item.preview) == 103
      assert String.ends_with?(item.preview, "...")
    end
  end

  describe "to_item/1 for insights" do
    test "converts insight to activity item with key", %{project: project} do
      {:ok, insight} =
        Memory.create_insight(project.id, "Auth uses Guardian for JWT handling", key: "auth-jwt")

      item = Activity.to_item(insight)

      assert %Item{} = item
      assert item.id == insight.id
      assert item.type == :insight
      assert item.title == "auth-jwt"
      assert item.preview == "Auth uses Guardian for JWT handling"
      assert item.project_id == project.id
      assert item.project_name == "Test Project"
      assert item.inserted_at == insight.inserted_at
      assert item.source == insight
    end

    test "uses 'Insight' as title when key is nil", %{project: project} do
      {:ok, insight} = Memory.create_insight(project.id, "Some insight content")

      item = Activity.to_item(insight)

      assert item.title == "Insight"
    end

    test "truncates long content", %{project: project} do
      long_content = String.duplicate("c", 150)
      {:ok, insight} = Memory.create_insight(project.id, long_content)

      item = Activity.to_item(insight)

      assert String.length(item.preview) == 103
      assert String.ends_with?(item.preview, "...")
    end
  end

  describe "Item struct" do
    test "has expected fields" do
      item = %Item{
        id: "123",
        type: :stash,
        title: "Test",
        preview: "Preview",
        project_id: "456",
        project_name: "Project",
        inserted_at: DateTime.utc_now(),
        source: %{}
      }

      assert item.id == "123"
      assert item.type == :stash
      assert item.title == "Test"
      assert item.preview == "Preview"
      assert item.project_id == "456"
      assert item.project_name == "Project"
      assert item.source == %{}
    end
  end
end
