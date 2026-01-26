defmodule PopStashWeb.Router do
  use PopStashWeb, :router

  import PopStashWeb.Dashboard.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PopStashWeb.Layouts, :root}
    plug :protect_from_forgery

    plug :put_secure_browser_headers, %{
      "content-security-policy" =>
        "default-src 'self'; " <>
          "script-src 'self' 'unsafe-inline' 'unsafe-eval'; " <>
          "style-src 'self' 'unsafe-inline'; " <>
          "img-src 'self' data: https:; " <>
          "font-src 'self' data:; " <>
          "connect-src 'self' ws://localhost:* wss://localhost:*"
    }
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :mcp do
    plug :accepts, ["json"]
    plug PopStashWeb.Plugs.CheckLocalhost
  end

  scope "/", PopStashWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # MCP JSON-RPC endpoint (localhost only)
  scope "/mcp", PopStashWeb do
    pipe_through :mcp

    get "/", MCPController, :index
    get "/:project_id", MCPController, :show
    post "/:project_id", MCPController, :handle
  end

  # Info page for MCP setup
  scope "/", PopStashWeb do
    pipe_through :browser

    get "/mcp-info", MCPController, :info
  end

  # PopStash Dashboard - mount with your own authentication!
  # ⚠️  WARNING: No authentication by default. Secure this route!
  scope "/pop_stash" do
    pipe_through :browser
    pop_stash_dashboard("/")
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:pop_stash, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: PopStashWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
