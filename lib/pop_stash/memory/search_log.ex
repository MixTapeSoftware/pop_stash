defmodule PopStash.Memory.SearchLog do
  @moduledoc """
  Schema for search logs.

  Tracks agent searches to analyze search patterns and query trends over time.
  """

  use PopStash.Schema

  schema "search_logs" do
    field(:query, :string)
    field(:collection, :string)
    field(:search_type, :string)
    field(:tool, :string)
    field(:result_count, :integer)
    field(:found, :boolean)
    field(:duration_ms, :integer)

    belongs_to(:project, PopStash.Projects.Project)

    timestamps(updated_at: false)
  end
end
