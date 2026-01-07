defmodule PopStash.MCP.Router do
  @moduledoc """
  HTTP router for MCP server.

  - `POST /mcp/:project_id` — JSON-RPC endpoint, scoped to project
  - `GET /` — Info page

  Localhost-only for security.
  """

  use Plug.Router
  require Logger

  alias PopStash.Agents
  alias PopStash.MCP.Server
  alias PopStash.Projects

  plug(:match)
  plug(:check_localhost)
  plug(Plug.Parsers, parsers: [:json], pass: ["application/json"], json_decoder: Jason)
  plug(:dispatch)

  # Main MCP endpoint — project_id required and validated
  post "/mcp/:project_id" do
    project_id = conn.path_params["project_id"]

    case Projects.get(project_id) do
      {:ok, project} ->
        {:ok, agent} = get_or_create_agent(project.id)

        context = %{
          project_id: project.id,
          project_name: project.name,
          agent_id: agent.id
        }

        case Server.handle_message(conn.body_params, context) do
          {:ok, :notification} -> send_resp(conn, 204, "")
          {:ok, response} -> json(conn, 200, response)
          {:error, response} -> json(conn, 200, response)
        end

      {:error, :not_found} ->
        Logger.warning("Request for unknown project: #{project_id}")

        error_response = %{
          jsonrpc: "2.0",
          id: conn.body_params["id"],
          error: %{
            code: -32_001,
            message: "Project not found: #{project_id}",
            data: %{
              hint: "Create a project with: mix pop_stash.project.new \"Your Project Name\""
            }
          }
        }

        json(conn, 404, error_response)
    end
  end

  # Temporary: Phase 3 will replace with session-based agent management
  defp get_or_create_agent(project_id) do
    Agents.connect(project_id, name: "mcp-client")
  end

  # Helpful messages for GET requests to MCP endpoints
  get "/mcp" do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(400, """
    MCP endpoint requires a project ID.

    Usage: POST /mcp/:project_id with JSON-RPC 2.0 payload

    Create a project with: mix pop_stash.project.new "Your Project Name"
    """)
  end

  get "/mcp/:project_id" do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(405, """
    MCP endpoint accepts POST requests only.

    Usage: POST /mcp/#{conn.path_params["project_id"]} with JSON-RPC 2.0 payload

    Example:
      curl -X POST http://localhost:4001/mcp/#{conn.path_params["project_id"]} \\
        -H "Content-Type: application/json" \\
        -d '{"jsonrpc":"2.0","id":1,"method":"ping"}'
    """)
  end

  get "/" do
    tools = Server.tools()
    projects = Projects.list()
    port = Application.get_env(:pop_stash, :mcp_port, 4001)

    projects_html =
      if projects === [] do
        "<p><em>No projects yet. Create one with <code>mix pop_stash.project.new \"My Project\"</code></em></p>"
      else
        "<ul>" <>
          Enum.map_join(projects, fn p ->
            "<li><code>#{p.id}</code> — #{p.name}</li>"
          end) <> "</ul>"
      end

    html = """
    <!DOCTYPE html>
    <html>
    <head><title>PopStash MCP</title>
    <style>body{font-family:system-ui;max-width:700px;margin:40px auto;padding:0 20px}
    code{background:#f4f4f4;padding:2px 6px;border-radius:3px}
    pre{background:#f4f4f4;padding:12px;border-radius:4px;overflow-x:auto}
    .note{background:#fffbeb;border:1px solid #f59e0b;padding:12px;border-radius:4px;margin:12px 0}</style>
    </head>
    <body>
    <h1>PopStash MCP Server</h1>
    <p>POST JSON-RPC 2.0 to <code>/mcp/:project_id</code></p>

    <div class="note">
      <strong>Project ID Required:</strong> Each workspace needs its own project ID in the URL.
      <br>Create one with: <code>mix pop_stash.project.new "My Project"</code>
    </div>

    <h2>Projects (#{length(projects)})</h2>
    #{projects_html}

    <h2>Tools (#{length(tools)})</h2>
    <ul>#{Enum.map_join(tools, fn t -> "<li><b>#{t.name}</b> — #{t.description}</li>" end)}</ul>

    <h2>Claude Code Setup</h2>
    <p>Add to your workspace <code>.claude/mcp_servers.json</code>:</p>
    <pre>{
      "pop_stash": {
        "url": "http://localhost:#{port}/mcp/YOUR_PROJECT_ID"
      }
    }</pre>
    </body></html>
    """

    conn |> put_resp_content_type("text/html") |> send_resp(200, html)
  end

  match(_, do: send_resp(conn, 404, "Not found"))

  ## Security

  defp check_localhost(conn, _opts) do
    if localhost?(conn.remote_ip) do
      conn
    else
      Logger.warning("Rejected non-localhost request from #{:inet.ntoa(conn.remote_ip)}")
      conn |> send_resp(403, "Localhost only") |> halt()
    end
  end

  defp localhost?({127, _, _, _}), do: true
  defp localhost?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  defp localhost?(_), do: false

  ## Helpers

  defp json(conn, status, data) do
    conn |> put_resp_content_type("application/json") |> send_resp(status, Jason.encode!(data))
  end
end
