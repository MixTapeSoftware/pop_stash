defmodule PopStashWeb.MCPController do
  use PopStashWeb, :controller

  require Logger

  alias PopStash.MCP.Server
  alias PopStash.Projects

  @doc """
  Main MCP endpoint — project_id required and validated.
  Handles JSON-RPC 2.0 requests for a specific project.
  """
  def handle(conn, %{"project_id" => project_id}) do
    case Projects.get(project_id) do
      {:ok, project} ->
        context = %{
          project_id: project.id,
          project_name: project.name
        }

        case Server.handle_message(conn.body_params, context) do
          {:ok, :notification} ->
            send_resp(conn, 204, "")

          {:ok, response} ->
            json(conn, response)

          {:error, response} ->
            json(conn, response)
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

        conn
        |> put_status(404)
        |> json(error_response)
    end
  end

  @doc """
  GET request to /mcp — helpful message about requiring project ID.
  """
  def index(conn, _params) do
    conn
    |> put_resp_content_type("text/plain")
    |> put_status(400)
    |> text("""
    MCP endpoint requires a project ID.

    Usage: POST /mcp/:project_id with JSON-RPC 2.0 payload

    Create a project with: mix pop_stash.project.new "Your Project Name"
    """)
  end

  @doc """
  GET request to /mcp/:project_id — helpful message about POST-only endpoint.
  """
  def show(conn, %{"project_id" => project_id}) do
    conn
    |> put_resp_content_type("text/plain")
    |> put_status(405)
    |> text("""
    MCP endpoint accepts POST requests only.

    Usage: POST /mcp/#{project_id} with JSON-RPC 2.0 payload

    Example:
      curl -X POST http://localhost:4001/mcp/#{project_id} \\
        -H "Content-Type: application/json" \\
        -d '{"jsonrpc":"2.0","id":1,"method":"ping"}'
    """)
  end

  @doc """
  Info page showing available tools, projects, and setup instructions.
  """
  def info(conn, _params) do
    tools = Server.tools()
    projects = Projects.list()
    port = Application.get_env(:pop_stash, :mcp_port, 4001)

    render(conn, :info,
      tools: tools,
      projects: projects,
      port: port
    )
  end
end
