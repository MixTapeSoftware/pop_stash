defmodule PopStash.Activity do
  @moduledoc """
  Context for unified activity feed across stashes, decisions, and insights.
  """

  import Ecto.Query

  alias PopStash.Memory.{Context, Decision, Insight, SearchLog}
  alias PopStash.Projects.Project
  alias PopStash.Repo

  defmodule Item do
    @moduledoc "Unified activity item for the feed."
    defstruct [:id, :type, :title, :preview, :project_id, :project_name, :inserted_at, :source]

    @type t :: %__MODULE__{
            id: String.t(),
            type: :context | :decision | :insight | :search,
            title: String.t(),
            preview: String.t() | nil,
            project_id: String.t(),
            project_name: String.t() | nil,
            inserted_at: DateTime.t(),
            source: struct()
          }
  end

  @doc """
  Fetches the most recent activity items across all types.

  ## Options
    * `:limit` - Maximum items to return (default: 20)
    * `:project_id` - Filter by project (optional)
    * `:types` - List of types to include (default: all)
  """
  def list_recent(opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    project_id = Keyword.get(opts, :project_id)
    types = Keyword.get(opts, :types, [:context, :decision, :insight, :search])

    items = []

    items = if :context in types, do: items ++ fetch_contexts(project_id, limit), else: items
    items = if :decision in types, do: items ++ fetch_decisions(project_id, limit), else: items
    items = if :insight in types, do: items ++ fetch_insights(project_id, limit), else: items
    items = if :search in types, do: items ++ fetch_searches(project_id, limit), else: items

    items
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
    |> Enum.take(limit)
  end

  @doc """
  Converts a raw entity to an activity item.
  Used for real-time updates when a new item is created.
  """
  def to_item(%Context{} = context) do
    %Item{
      id: context.id,
      type: :context,
      title: context.name,
      preview: truncate(context.summary, 100),
      project_id: context.project_id,
      project_name: get_project_name(context.project_id),
      inserted_at: context.inserted_at,
      source: context
    }
  end

  def to_item(%Decision{} = decision) do
    %Item{
      id: decision.id,
      type: :decision,
      title: decision.topic,
      preview: truncate(decision.decision, 100),
      project_id: decision.project_id,
      project_name: get_project_name(decision.project_id),
      inserted_at: decision.inserted_at,
      source: decision
    }
  end

  def to_item(%Insight{} = insight) do
    %Item{
      id: insight.id,
      type: :insight,
      title: insight.key || "Insight",
      preview: truncate(insight.content, 100),
      project_id: insight.project_id,
      project_name: get_project_name(insight.project_id),
      inserted_at: insight.inserted_at,
      source: insight
    }
  end

  def to_item(%SearchLog{} = search) do
    preview = "#{search.collection} • #{search.search_type}"

    preview =
      if search.result_count, do: "#{preview} • #{search.result_count} results", else: preview

    %Item{
      id: search.id,
      type: :search,
      title: search.query,
      preview: preview,
      project_id: search.project_id,
      project_name: get_project_name(search.project_id),
      inserted_at: search.inserted_at,
      source: search
    }
  end

  # Private functions

  defp fetch_contexts(project_id, limit) do
    Context
    |> maybe_filter_project(project_id)
    |> where([s], is_nil(s.expires_at) or s.expires_at > ^DateTime.utc_now())
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> preload(:project)
    |> Repo.all()
    |> Enum.map(&to_item/1)
  end

  defp fetch_decisions(project_id, limit) do
    Decision
    |> maybe_filter_project(project_id)
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> preload(:project)
    |> Repo.all()
    |> Enum.map(&to_item/1)
  end

  defp fetch_insights(project_id, limit) do
    Insight
    |> maybe_filter_project(project_id)
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> preload(:project)
    |> Repo.all()
    |> Enum.map(&to_item/1)
  end

  defp fetch_searches(project_id, limit) do
    SearchLog
    |> maybe_filter_project(project_id)
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> preload(:project)
    |> Repo.all()
    |> Enum.map(&to_item/1)
  end

  defp maybe_filter_project(query, nil), do: query

  defp maybe_filter_project(query, project_id), do: where(query, [q], q.project_id == ^project_id)

  defp get_project_name(project_id) do
    case Repo.get(Project, project_id) do
      nil -> nil
      project -> project.name
    end
  end

  defp truncate(nil, _), do: nil
  defp truncate(text, max_length) when byte_size(text) <= max_length, do: text

  defp truncate(text, max_length) do
    String.slice(text, 0, max_length) <> "..."
  end
end
