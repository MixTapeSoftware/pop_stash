defmodule PopStash.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  alias PopStash.Embeddings
  alias PopStash.Search.Indexer
  alias PopStash.Search.Typesense

  @impl true
  def start(_type, _args) do
    children =
      [
        PopStashWeb.Telemetry,
        PopStash.Repo,
        {DNSCluster, query: Application.get_env(:pop_stash, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: PopStash.PubSub},
        {Task.Supervisor, name: PopStash.TaskSupervisor},
        # Start a worker by calling: PopStash.Worker.start_link(arg)
        # {PopStash.Worker, arg},
        # Start to serve requests, typically the last entry
        PopStashWeb.Endpoint
      ]
      |> maybe_add_typesense()
      |> maybe_add_embeddings()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: PopStash.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp maybe_add_typesense(children) do
    if Typesense.enabled?() do
      # Convert keyword list to map for TypesenseEx, excluding :enabled key
      typesense_config =
        :pop_stash
        |> Application.get_env(:typesense, [])
        |> Keyword.delete(:enabled)
        |> Enum.into(%{})

      # Add TypesenseEx and Indexer before the endpoint
      children
      |> List.insert_at(-1, {TypesenseEx, typesense_config})
      |> List.insert_at(-1, Indexer)
    else
      children
    end
  end

  defp maybe_add_embeddings(children) do
    if Embeddings.enabled?() do
      embeddings_spec =
        {Nx.Serving, name: Embeddings, serving: Embeddings.serving()}

      # Add embeddings before the endpoint so it's ready before requests come in
      List.insert_at(children, -1, embeddings_spec)
    else
      children
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PopStashWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
