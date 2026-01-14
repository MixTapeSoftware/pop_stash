defmodule PopStashWeb.Plugs.CheckLocalhost do
  @moduledoc """
  Security plug that restricts MCP endpoints to specific IP addresses.

  ## Configuration

  You can configure allowed IPs in your config files:

      config :pop_stash, :allowed_ips, [
        {127, 0, 0, 1},                    # IPv4 localhost
        {0, 0, 0, 0, 0, 0, 0, 1},          # IPv6 localhost
        {:range, {10, 0, 0, 0}},           # 10.x.x.x range
        {:range, {172, 16, 0, 0}},         # 172.16.x.x - 172.31.x.x (Docker default)
        {:range, {192, 168, 0, 0}},        # 192.168.x.x range
        {160, 79, 104, 10}                 # Specific IP
      ]

  Or disable the check entirely:

      config :pop_stash, :skip_localhost_check, true

  ## Default Allowed IPs

  By default, allows requests from:
  - 127.0.0.1 (IPv4 localhost)
  - ::1 (IPv6 localhost)
  - 10.x.x.x (Docker/private network)
  - 172.16.x.x - 172.31.x.x (Docker bridge network)
  - 192.168.x.x (Local network)
  """
  import Plug.Conn
  require Logger

  @behaviour Plug

  @default_allowed_ips [
    # Localhost
    {127, 0, 0, 1},
    {0, 0, 0, 0, 0, 0, 0, 1},
    # Common Docker and private network ranges
    {:range, {10, 0, 0, 0}},
    {:range, {172, 16, 0, 0}},
    {:range, {172, 17, 0, 0}},
    {:range, {172, 18, 0, 0}},
    {:range, {172, 19, 0, 0}},
    {:range, {172, 20, 0, 0}},
    {:range, {172, 21, 0, 0}},
    {:range, {172, 22, 0, 0}},
    {:range, {172, 23, 0, 0}},
    {:range, {172, 24, 0, 0}},
    {:range, {172, 25, 0, 0}},
    {:range, {172, 26, 0, 0}},
    {:range, {172, 27, 0, 0}},
    {:range, {172, 28, 0, 0}},
    {:range, {172, 29, 0, 0}},
    {:range, {172, 30, 0, 0}},
    {:range, {172, 31, 0, 0}},
    {:range, {192, 168, 0, 0}}
  ]

  def init(opts), do: opts

  def call(conn, _opts) do
    if skip_check?() or ip_allowed?(conn.remote_ip) do
      conn
    else
      ip_string = format_ip(conn.remote_ip)
      Logger.warning("Rejected request from non-allowed IP: #{ip_string}")

      conn
      |> send_resp(403, "Access denied - IP not allowed")
      |> halt()
    end
  end

  defp skip_check? do
    Application.get_env(:pop_stash, :skip_localhost_check, false)
  end

  defp ip_allowed?(ip) do
    allowed_ips = Application.get_env(:pop_stash, :allowed_ips, @default_allowed_ips)
    Enum.any?(allowed_ips, &ip_matches?(&1, ip))
  end

  # Match exact IP
  defp ip_matches?(allowed_ip, request_ip) when allowed_ip == request_ip, do: true

  # Match IPv4 range (first octet)
  defp ip_matches?({:range, {a, _, _, _}}, {a, _, _, _}), do: true

  # Match IPv4 range (first two octets)
  defp ip_matches?({:range, {a, b, _, _}}, {a, b, _, _}), do: true

  # Match IPv4 range (first three octets)
  defp ip_matches?({:range, {a, b, c, _}}, {a, b, c, _}), do: true

  # Match IPv6 range (simplified - first segment)
  defp ip_matches?({:range, {a, _, _, _, _, _, _, _}}, {a, _, _, _, _, _, _, _}), do: true

  # No match
  defp ip_matches?(_, _), do: false

  defp format_ip(ip) when is_tuple(ip) and tuple_size(ip) == 4 do
    ip
    |> Tuple.to_list()
    |> Enum.join(".")
  end

  defp format_ip(ip) when is_tuple(ip) and tuple_size(ip) == 8 do
    ip
    |> Tuple.to_list()
    |> Enum.map_join(":", &Integer.to_string(&1, 16))
  end

  defp format_ip(ip), do: inspect(ip)
end
