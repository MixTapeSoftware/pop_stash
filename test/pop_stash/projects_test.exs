defmodule PopStash.ProjectsTest do
  use PopStash.DataCase, async: true

  alias PopStash.Projects

  describe "create/2" do
    test "creates a project with auto-generated UUID" do
      assert {:ok, project} = Projects.create("My Project")
      assert project.name == "My Project"
      assert is_binary(project.id)
      # UUID format: 8-4-4-4-12 hex chars
      assert String.match?(
               project.id,
               ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
             )
    end

    test "creates a project with description" do
      assert {:ok, project} = Projects.create("My Project", description: "A test project")
      assert project.description == "A test project"
    end

    test "rejects duplicate project name" do
      {:ok, _} = Projects.create("Duplicate Name")
      # Names can be duplicated, IDs are unique
      assert {:ok, _} = Projects.create("Duplicate Name")
    end
  end

  describe "get/1" do
    test "returns project when it exists" do
      {:ok, created} = Projects.create("Test Project")
      assert {:ok, found} = Projects.get(created.id)
      assert found.id == created.id
      assert found.name == "Test Project"
    end

    test "returns error when project doesn't exist" do
      assert {:error, :not_found} = Projects.get(Ecto.UUID.generate())
    end
  end

  describe "list/0" do
    test "returns empty list when no projects" do
      assert [] = Projects.list()
    end

    test "returns projects ordered by creation date (newest first)" do
      {:ok, p1} = Projects.create("First")
      {:ok, p2} = Projects.create("Second")
      {:ok, p3} = Projects.create("Third")

      projects = Projects.list()
      assert length(projects) == 3
      assert [^p3, ^p2, ^p1] = projects
    end
  end

  describe "delete/1" do
    test "deletes existing project" do
      {:ok, project} = Projects.create("To Delete")
      assert {:ok, _} = Projects.delete(project.id)
      assert {:error, :not_found} = Projects.get(project.id)
    end

    test "returns error when project doesn't exist" do
      assert {:error, :not_found} = Projects.delete(Ecto.UUID.generate())
    end
  end

  describe "exists?/1" do
    test "returns true for existing project" do
      {:ok, project} = Projects.create("Exists")
      assert Projects.exists?(project.id)
    end

    test "returns false for non-existing project" do
      refute Projects.exists?(Ecto.UUID.generate())
    end
  end
end
