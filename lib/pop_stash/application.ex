defmodule PopStash.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        PopStash.Repo,
        {Phoenix.PubSub, name: PopStash.PubSub},
        {Task.Supervisor, name: PopStash.TaskSupervisor, max_children: 50}
      ]
      |> maybe_add(typesense_enabled?(), {TypesenseEx, typesense_config()})
      |> maybe_add(embeddings_enabled?(), embeddings_child_spec())
      |> maybe_add(typesense_enabled?() and embeddings_enabled?(), PopStash.Search.Indexer)
      |> maybe_add(start_server?(), {Bandit, plug: PopStash.MCP.Router, port: mcp_port()})

    Supervisor.start_link(children, strategy: :one_for_one, name: PopStash.Supervisor)
  end

  defp maybe_add(children, true, child), do: children ++ [child]
  defp maybe_add(children, false, _child), do: children

  defp typesense_enabled? do
    Application.get_env(:pop_stash, :typesense, [])[:enabled] || false
  end

  defp embeddings_enabled? do
    Application.get_env(:pop_stash, PopStash.Embeddings, [])[:enabled] || false
  end

  defp start_server?, do: Application.get_env(:pop_stash, :start_server, true)
  defp mcp_port, do: Application.get_env(:pop_stash, :mcp_port, 4001)

  defp typesense_config do
    Application.get_env(:pop_stash, :typesense, [])
    |> Keyword.delete(:enabled)
    |> Map.new()
  end

  defp embeddings_child_spec do
    {Nx.Serving,
     serving: PopStash.Embeddings.serving(), name: PopStash.Embeddings, batch_timeout: 100}
  end
end
