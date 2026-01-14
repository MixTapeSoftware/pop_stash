defmodule PopStash.MCP.Tools.RecallTest do
  use PopStash.DataCase, async: true

  alias PopStash.MCP.Tools.Recall
  alias PopStash.Memory
  alias PopStash.Projects

  setup do
    {:ok, project} = Projects.create("Test Project")
    %{project: project}
  end

  describe "tools/0" do
    test "returns recall tool definition" do
      [tool] = Recall.tools()

      assert tool.name == "recall"
      assert tool.inputSchema.required == ["title"]
      assert Map.has_key?(tool.inputSchema.properties, :title)
      assert Map.has_key?(tool.inputSchema.properties, :limit)
    end
  end

  describe "execute/2 - exact match" do
    test "returns insight when exact title match found", %{project: project} do
      {:ok, insight} =
        Memory.create_insight(project.id, "JWT uses HS256 by default", title: "jwt-config")

      result = Recall.execute(%{"title" => "jwt-config"}, %{project_id: project.id})

      assert {:ok, %{results: [found], match_type: "exact"}} = result
      assert found.id == insight.id
      assert found.title == "jwt-config"
      assert found.body == "JWT uses HS256 by default"
    end
  end

  describe "execute/2 - semantic search fallback" do
    test "returns empty results with hint when no match found", %{project: project} do
      # Create some insights with keys
      {:ok, _} = Memory.create_insight(project.id, "Content 1", title: "auth-setup")
      {:ok, _} = Memory.create_insight(project.id, "Content 2", title: "db-config")

      result = Recall.execute(%{"title" => "nonexistent"}, %{project_id: project.id})

      # Since embeddings are disabled, semantic search returns error which leads to empty results
      assert {:error, "Semantic search unavailable. Use exact title match."} = result
    end

    test "returns empty results message when no insights exist", %{project: project} do
      result = Recall.execute(%{"title" => "anything"}, %{project_id: project.id})

      # Without embeddings, returns search unavailable error
      assert {:error, "Semantic search unavailable. Use exact title match."} = result
    end
  end

  describe "execute/2 - result format" do
    test "formats insight with all expected fields", %{project: project} do
      {:ok, insight} =
        Memory.create_insight(project.id, "Test content", title: "test-key")

      {:ok, %{results: [result]}} =
        Recall.execute(%{"title" => "test-key"}, %{project_id: project.id})

      assert Map.has_key?(result, :id)
      assert Map.has_key?(result, :title)
      assert Map.has_key?(result, :content)
      assert Map.has_key?(result, :created_at)
      assert result.id == insight.id
    end
  end
end
