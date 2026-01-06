defmodule PopStash.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children =
      if Application.get_env(:pop_stash, :start_server, true) do
        port = Application.get_env(:pop_stash, :mcp_port, 4001)
        [{Bandit, plug: PopStash.MCP.Router, port: port}]
      else
        []
      end

    Supervisor.start_link(children, strategy: :one_for_one, name: PopStash.Supervisor)
  end
end
