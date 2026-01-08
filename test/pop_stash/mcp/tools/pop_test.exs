defmodule PopStash.MCP.Tools.PopTest do
  use PopStash.DataCase, async: true

  alias PopStash.MCP.Tools.Pop
  alias PopStash.Memory
  alias PopStash.Projects

  setup do
    {:ok, project} = Projects.create("Test Project")
    %{project: project}
  end

  describe "tools/0" do
    test "returns pop tool definition" do
      [tool] = Pop.tools()

      assert tool.name == "pop"
      assert tool.inputSchema.required == ["name"]
      assert Map.has_key?(tool.inputSchema.properties, :name)
      assert Map.has_key?(tool.inputSchema.properties, :limit)
    end
  end

  describe "execute/2 - exact match" do
    test "returns stash when exact name match found", %{project: project} do
      {:ok, stash} =
        Memory.create_stash(project.id, "auth-work", "Working on authentication",
          files: ["lib/auth.ex"]
        )

      result = Pop.execute(%{"name" => "auth-work"}, %{project_id: project.id})

      assert {:ok, %{results: [found], match_type: "exact"}} = result
      assert found.id == stash.id
      assert found.name == "auth-work"
      assert found.summary == "Working on authentication"
      assert found.files == ["lib/auth.ex"]
    end
  end

  describe "execute/2 - semantic search fallback" do
    test "returns error when no match found and embeddings disabled", %{
      project: project
    } do
      {:ok, _} = Memory.create_stash(project.id, "other-stash", "Some summary")

      result = Pop.execute(%{"name" => "nonexistent"}, %{project_id: project.id})

      # Since embeddings are disabled, semantic search returns error
      assert {:error, "Semantic search unavailable. Use exact name match."} = result
    end

    test "returns error when no stashes exist", %{project: project} do
      result = Pop.execute(%{"name" => "anything"}, %{project_id: project.id})

      assert {:error, "Semantic search unavailable. Use exact name match."} = result
    end
  end

  describe "execute/2 - result format" do
    test "formats stash with all expected fields", %{project: project} do
      {:ok, stash} =
        Memory.create_stash(project.id, "test-stash", "Test summary",
          files: ["file1.ex", "file2.ex"]
        )

      {:ok, %{results: [result]}} =
        Pop.execute(%{"name" => "test-stash"}, %{project_id: project.id})

      assert Map.has_key?(result, :id)
      assert Map.has_key?(result, :name)
      assert Map.has_key?(result, :summary)
      assert Map.has_key?(result, :files)
      assert Map.has_key?(result, :created_at)
      assert result.id == stash.id
      assert result.files == ["file1.ex", "file2.ex"]
    end

    test "handles stash without files", %{project: project} do
      {:ok, _stash} = Memory.create_stash(project.id, "no-files", "No files stash")

      {:ok, %{results: [result]}} =
        Pop.execute(%{"name" => "no-files"}, %{project_id: project.id})

      assert result.files == []
    end
  end
end
