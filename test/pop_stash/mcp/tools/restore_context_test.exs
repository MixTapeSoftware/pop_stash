defmodule PopStash.MCP.Tools.RestoreContextTest do
  use PopStash.DataCase, async: true

  alias PopStash.MCP.Tools.RestoreContext
  alias PopStash.Memory
  alias PopStash.Projects

  setup do
    {:ok, project} = Projects.create("Test Project")
    %{project: project}
  end

  describe "tools/0" do
    test "returns restore_context tool definition" do
      [tool] = RestoreContext.tools()

      assert tool.name == "restore_context"
      assert tool.inputSchema.required == ["name"]
      assert Map.has_key?(tool.inputSchema.properties, :name)
      assert Map.has_key?(tool.inputSchema.properties, :limit)
    end
  end

  describe "execute/2 - exact match" do
    test "returns context when exact name match found", %{project: project} do
      {:ok, context} =
        Memory.create_context(project.id, "auth-work", "Working on authentication",
          files: ["lib/auth.ex"]
        )

      result = RestoreContext.execute(%{"name" => "auth-work"}, %{project_id: project.id})

      assert {:ok, %{results: [found], match_type: "exact"}} = result
      assert found.id == context.id
      assert found.name == "auth-work"
      assert found.summary == "Working on authentication"
      assert found.files == ["lib/auth.ex"]
    end
  end

  describe "execute/2 - semantic search fallback" do
    test "returns error when no match found and embeddings disabled", %{
      project: project
    } do
      {:ok, _} = Memory.create_context(project.id, "other-context", "Some summary")

      result = RestoreContext.execute(%{"name" => "nonexistent"}, %{project_id: project.id})

      # Since embeddings are disabled, semantic search returns error
      assert {:error, "Semantic search unavailable. Use exact name match."} = result
    end

    test "returns error when no contexts exist", %{project: project} do
      result = RestoreContext.execute(%{"name" => "anything"}, %{project_id: project.id})

      assert {:error, "Semantic search unavailable. Use exact name match."} = result
    end
  end

  describe "execute/2 - result format" do
    test "formats context with all expected fields", %{project: project} do
      {:ok, context} =
        Memory.create_context(project.id, "test-context", "Test summary",
          files: ["file1.ex", "file2.ex"]
        )

      {:ok, %{results: [result]}} =
        RestoreContext.execute(%{"name" => "test-context"}, %{project_id: project.id})

      assert Map.has_key?(result, :id)
      assert Map.has_key?(result, :name)
      assert Map.has_key?(result, :summary)
      assert Map.has_key?(result, :files)
      assert Map.has_key?(result, :created_at)
      assert result.id == context.id
      assert result.files == ["file1.ex", "file2.ex"]
    end

    test "handles context without files", %{project: project} do
      {:ok, _context} = Memory.create_context(project.id, "no-files", "No files context")

      {:ok, %{results: [result]}} =
        RestoreContext.execute(%{"name" => "no-files"}, %{project_id: project.id})

      assert result.files == []
    end
  end
end
