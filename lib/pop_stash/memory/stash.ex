defmodule PopStash.Memory.Stash do
  @moduledoc """
  Schema for stashes (saved context).

  A stash is like `git stash` - saves current work state for later retrieval.
  """

  use PopStash.Schema

  schema "stashes" do
    field(:name, :string)
    field(:summary, :string)
    field(:files, {:array, :string}, default: [])
    field(:tags, {:array, :string}, default: [])
    field(:expires_at, :utc_datetime_usec)
    field(:embedding, Pgvector.Ecto.Vector)

    belongs_to(:project, PopStash.Projects.Project)

    timestamps()
  end
end
