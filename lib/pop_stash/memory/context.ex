defmodule PopStash.Memory.Context do
  @moduledoc """
  Schema for contexts (saved working state).

  A context is like `git stash` - saves current work state for later retrieval.
  """

  use PopStash.Schema

  @thread_prefix "cthr"

  def thread_prefix, do: @thread_prefix

  schema "contexts" do
    field(:title, :string)
    field(:body, :string)
    field(:files, {:array, :string}, default: [])
    field(:tags, {:array, :string}, default: [])
    field(:thread_id, :string)
    field(:expires_at, :utc_datetime_usec)
    field(:embedding, Pgvector.Ecto.Vector)

    belongs_to(:project, PopStash.Projects.Project)

    timestamps()
  end
end
