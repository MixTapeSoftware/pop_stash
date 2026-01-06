defmodule PopStash.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Ecto repository
      PopStash.Repo
    ]

    # Add HTTP server in non-test environments
    children =
      if Application.get_env(:pop_stash, :start_server, true) do
        port = Application.get_env(:pop_stash, :mcp_port, 4001)
        children ++ [{Bandit, plug: PopStash.MCP.Router, port: port}]
      else
        children
      end

    Supervisor.start_link(children, strategy: :one_for_one, name: PopStash.Supervisor)
  end
end
