defmodule PopStashWeb.Plugs.CheckLocalhost do
  @moduledoc """
  Security plug that restricts MCP endpoints to localhost only.

  Allows requests from:
  - 127.x.x.x (IPv4 localhost)
  - ::1 (IPv6 localhost)
  - 172.x.x.x (Docker bridge network)

  Can be disabled via config: `config :pop_stash, :skip_localhost_check, true`
  """
  import Plug.Conn
  require Logger

  @behaviour Plug

  def init(opts), do: opts

  def call(conn, _opts) do
    if skip_localhost_check?() or localhost?(conn.remote_ip) or docker_network?(conn.remote_ip) do
      conn
    else
      Logger.warning("Rejected non-localhost request from #{:inet.ntoa(conn.remote_ip)}")

      conn
      |> send_resp(403, "Localhost only")
      |> halt()
    end
  end

  defp skip_localhost_check? do
    Application.get_env(:pop_stash, :skip_localhost_check, false)
  end

  defp localhost?({127, _, _, _}), do: true
  defp localhost?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  defp localhost?(_), do: false

  # Docker bridge network typically uses 172.x.x.x
  defp docker_network?({172, _, _, _}), do: true
  defp docker_network?(_), do: false
end
