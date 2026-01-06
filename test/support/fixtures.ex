defmodule PopStash.Fixtures do
  @moduledoc """
  Test fixtures for PopStash.
  """

  alias PopStash.Projects

  def project_fixture(attrs \\ []) do
    name = Keyword.get(attrs, :name, "Test Project #{System.unique_integer()}")
    opts = Keyword.delete(attrs, :name)

    {:ok, project} = Projects.create(name, opts)
    project
  end
end
