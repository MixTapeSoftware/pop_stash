defmodule PopStash.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      PopStashWeb.Telemetry,
      PopStash.Repo,
      {DNSCluster, query: Application.get_env(:pop_stash, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: PopStash.PubSub},
      # Start a worker by calling: PopStash.Worker.start_link(arg)
      # {PopStash.Worker, arg},
      # Start to serve requests, typically the last entry
      PopStashWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: PopStash.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PopStashWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
