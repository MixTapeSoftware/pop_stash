defmodule PopStashWeb.Plugs.BasicAuth do
  @moduledoc """
  HTTP Basic Authentication plug with environment-aware behavior.

  Wraps Plug.BasicAuth with:
  - Skip auth when `:skip_basic_auth` config is true (dev/test)
  - Return 503 if credentials not configured (fail secure)
  - Configurable realm for browser auth dialogs

  ## Configuration

      # Production (runtime.exs)
      config :pop_stash, :basic_auth,
        username: System.get_env("BASIC_AUTH_USERNAME"),
        password: System.get_env("BASIC_AUTH_PASSWORD")

      # Dev/Test
      config :pop_stash, :skip_basic_auth, true
  """

  import Plug.Conn
  require Logger

  @behaviour Plug

  def init(opts), do: opts

  def call(conn, opts) do
    cond do
      skip_auth?() ->
        conn

      not credentials_configured?() ->
        Logger.error("Basic auth credentials not configured - returning 503")

        conn
        |> send_resp(503, "Service unavailable - authentication not configured")
        |> halt()

      true ->
        realm = Keyword.get(opts, :realm, "PopStash Dashboard")
        Plug.BasicAuth.basic_auth(conn, username: username(), password: password(), realm: realm)
    end
  end

  defp skip_auth?, do: Application.get_env(:pop_stash, :skip_basic_auth, false)

  defp credentials_configured? do
    config = Application.get_env(:pop_stash, :basic_auth, [])
    Keyword.get(config, :username) != nil and Keyword.get(config, :password) != nil
  end

  defp username, do: Application.get_env(:pop_stash, :basic_auth, []) |> Keyword.get(:username)
  defp password, do: Application.get_env(:pop_stash, :basic_auth, []) |> Keyword.get(:password)
end
