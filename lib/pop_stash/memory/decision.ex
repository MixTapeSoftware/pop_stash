defmodule PopStash.Memory.Decision do
  @moduledoc """
  Schema for decisions (immutable decision log).

  Decisions record architectural choices, technical decisions, and project direction.
  They are append-only - new decisions on the same topic create new entries,
  preserving full history.
  """

  use PopStash.Schema

  schema "decisions" do
    field(:topic, :string)
    field(:decision, :string)
    field(:reasoning, :string)
    field(:metadata, :map, default: %{})

    belongs_to(:project, PopStash.Projects.Project)
    belongs_to(:agent, PopStash.Agents.Agent, foreign_key: :created_by)

    timestamps()
  end

  @doc """
  Normalizes a topic string for consistent matching.
  Trims whitespace and converts to lowercase.
  """
  def normalize_topic(topic) when is_binary(topic) do
    topic
    |> String.trim()
    |> String.downcase()
  end

  def normalize_topic(nil), do: nil
end
