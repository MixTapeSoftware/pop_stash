defmodule PopStash.MCP.Server do
  @moduledoc """
  MCP server implementing JSON-RPC 2.0.

  Tool modules implement a `tools/0` callback returning a list of tool definitions.
  Each definition is a map with `:name`, `:description`, `:inputSchema`, and `:callback`.
  """

  require Logger

  @tool_modules [
    PopStash.MCP.Tools.SaveContext,
    PopStash.MCP.Tools.RestoreContext,
    PopStash.MCP.Tools.Insight,
    PopStash.MCP.Tools.Recall,
    PopStash.MCP.Tools.Decide,
    PopStash.MCP.Tools.GetDecisions
  ]

  @type message :: map()
  @type response :: map()

  ## Public API

  @doc "Returns available tools (without callbacks, safe for JSON serialization)."
  @spec tools() :: [map()]
  def tools do
    @tool_modules
    |> Enum.flat_map(& &1.tools())
    |> Enum.map(&Map.drop(&1, [:callback]))
  end

  @doc """
  Handles a JSON-RPC 2.0 message.

  Returns `{:ok, response}`, `{:error, response}`, or `{:ok, :notification}`.
  Context map must include :project_id.
  """
  def handle_message(message, %{project_id: project_id} = context) do
    start_time = System.monotonic_time()

    result =
      with {:ok, msg} <- validate_jsonrpc(message) do
        route(msg, context)
      end

    emit_telemetry(message, result, start_time, project_id)
    result
  end

  ## Routing
  # All routes receive context map with project_id and project

  defp route(%{"method" => "initialize", "id" => id, "params" => params}, context) do
    version = protocol_version()

    case validate_protocol_version(params["protocolVersion"]) do
      :ok ->
        {:ok,
         success(id, %{
           protocolVersion: version,
           capabilities: %{tools: %{listChanged: false}},
           serverInfo: %{name: "PopStash", version: app_version()},
           projectId: context.project_id,
           projectName: context.project_name,
           tools: tools()
         })}

      {:error, reason} ->
        {:error, error(id, -32_602, reason)}
    end
  end

  defp route(%{"method" => "tools/list", "id" => id}, _context) do
    {:ok, success(id, %{tools: tools()})}
  end

  defp route(%{"method" => "tools/call", "id" => id, "params" => params}, context) do
    call_tool(id, params, context)
  end

  defp route(%{"method" => method, "id" => id}, _context) do
    {:error, error(id, -32_601, "Method not found: #{method}")}
  end

  defp route(%{"method" => _method}, _context) do
    {:ok, :notification}
  end

  ## Tool Dispatch

  defp call_tool(id, %{"name" => name, "arguments" => args}, context) do
    with {:ok, callback} <- find_tool(id, name) do
      execute_tool(id, name, callback, args, context)
    end
  end

  defp call_tool(id, _, _context) do
    {:error, error(id, -32_602, "Missing 'name' or 'arguments'")}
  end

  defp find_tool(id, name) do
    @tool_modules
    |> Enum.flat_map(& &1.tools())
    |> Enum.find(&(&1.name == name))
    |> case do
      %{callback: cb} -> {:ok, cb}
      nil -> {:error, error(id, -32_601, "Unknown tool: #{name}")}
    end
  end

  defp execute_tool(id, name, callback, args, context) do
    case callback.(args, context) do
      {:ok, text} when is_binary(text) ->
        {:ok, success(id, %{content: [%{type: "text", text: text}]})}

      {:ok, data} when is_map(data) ->
        {:ok, success(id, data)}

      {:error, msg} when is_binary(msg) ->
        {:error, error(id, -32_603, msg)}

      other ->
        Logger.warning("Tool #{name} returned invalid result: #{inspect(other)}")
        {:error, error(id, -32_603, "Invalid tool response")}
    end
  catch
    kind, reason ->
      Logger.error("Tool #{name} crashed: #{Exception.format(kind, reason, __STACKTRACE__)}")
      {:error, error(id, -32_603, "Tool execution failed")}
  end

  ## Validation

  defp validate_jsonrpc(%{"jsonrpc" => "2.0", "method" => m} = msg) when is_binary(m) do
    {:ok, msg}
  end

  defp validate_jsonrpc(_) do
    {:error, error(nil, -32_600, "Invalid JSON-RPC 2.0 request")}
  end

  # Protocol versions are date-formatted strings. Lexicographic comparison works.
  defp validate_protocol_version(nil), do: {:error, "protocolVersion required"}

  defp validate_protocol_version(v) when is_binary(v) do
    if v >= protocol_version(), do: :ok, else: {:error, "Protocol version #{v} not supported"}
  end

  defp validate_protocol_version(_), do: {:error, "protocolVersion must be a string"}

  ## Response Builders

  defp success(id, result), do: %{jsonrpc: "2.0", id: id, result: result}

  defp error(id, code, message),
    do: %{jsonrpc: "2.0", id: id, error: %{code: code, message: message}}

  ## Config

  defp protocol_version, do: Application.get_env(:pop_stash, :mcp_protocol_version, "2025-03-26")

  defp app_version, do: Application.spec(:pop_stash, :vsn) |> to_string()

  ## Telemetry

  defp emit_telemetry(message, result, start_time, project_id) do
    :telemetry.execute(
      [:pop_stash, :mcp, :request],
      %{duration: System.monotonic_time() - start_time},
      %{
        method: message["method"],
        tool: get_in(message, ["params", "name"]),
        project_id: project_id,
        success: match?({:ok, _}, result)
      }
    )
  end
end
