defmodule PopStash.Memory.Stash do
  @moduledoc """
  Schema for stashes (saved agent context).

  A stash is like `git stash` - saves current work state for later retrieval.
  """

  use PopStash.Schema

  schema "stashes" do
    field(:name, :string)
    field(:summary, :string)
    field(:files, {:array, :string}, default: [])
    field(:metadata, :map, default: %{})
    field(:expires_at, :utc_datetime_usec)

    belongs_to(:project, PopStash.Projects.Project)
    belongs_to(:agent, PopStash.Agents.Agent, foreign_key: :created_by)

    timestamps()
  end
end
