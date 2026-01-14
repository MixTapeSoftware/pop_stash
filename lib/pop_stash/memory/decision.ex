defmodule PopStash.Memory.Decision do
  @moduledoc """
  Schema for decisions (immutable decision log).

  Decisions record architectural choices, technical decisions, and project direction.
  They are append-only - new decisions on the same title create new entries,
  preserving full history.
  """

  use PopStash.Schema

  @thread_prefix "dthr"

  def thread_prefix, do: @thread_prefix

  schema "decisions" do
    field(:title, :string)
    field(:body, :string)
    field(:reasoning, :string)
    field(:files, {:array, :string}, default: [])
    field(:tags, {:array, :string}, default: [])
    field(:thread_id, :string)
    field(:embedding, Pgvector.Ecto.Vector)

    belongs_to(:project, PopStash.Projects.Project)

    timestamps()
  end

  @doc """
  Normalizes a title string for consistent matching.
  Trims whitespace and converts to lowercase.
  """
  def normalize_title(title) when is_binary(title) do
    title
    |> String.trim()
    |> String.downcase()
  end

  def normalize_title(nil), do: nil
end
