defmodule PopStash.Agents.Agent do
  @moduledoc """
  Schema for agents (connected MCP clients).

  An agent represents a connected editor instance (Claude Code, Cursor, etc.)
  working within a project. Agents create stashes and insights.
  """

  use PopStash.Schema

  @statuses ~w(active idle disconnected)

  schema "agents" do
    field :name, :string
    field :current_task, :string
    field :status, :string, default: "active"
    field :connected_at, :utc_datetime_usec
    field :last_seen_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :project, PopStash.Projects.Project

    timestamps()
  end

  def statuses, do: @statuses
end
