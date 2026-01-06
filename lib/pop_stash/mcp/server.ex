defmodule PopStash.MCP.Server do
  @moduledoc """
  MCP server implementing JSON-RPC 2.0.

  Tool modules implement a `tools/0` callback returning a list of tool definitions.
  Each definition is a map with `:name`, `:description`, `:inputSchema`, and `:callback`.
  """

  require Logger

  @tool_modules [
    PopStash.MCP.Tools.Ping
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
  The project_id is passed from the router (/mcp/:project_id).
  """
  @spec handle_message(message(), String.t()) :: {:ok, response() | :notification} | {:error, response()}
  def handle_message(message, project_id) do
    start_time = System.monotonic_time()

    result =
      with {:ok, msg} <- validate_jsonrpc(message) do
        route(msg, project_id)
      end

    emit_telemetry(message, result, start_time, project_id)
    result
  end

  ## Routing
  # All routes receive project_id for future use (Phase 1.5+)

  defp route(%{"method" => "ping", "id" => id}, _project_id) do
    {:ok, success(id, %{})}
  end

  defp route(%{"method" => "initialize", "id" => id, "params" => params}, project_id) do
    version = protocol_version()

    case validate_protocol_version(params["protocolVersion"]) do
      :ok ->
        {:ok,
         success(id, %{
           protocolVersion: version,
           capabilities: %{tools: %{listChanged: false}},
           serverInfo: %{name: "PopStash", version: app_version()},
           projectId: project_id,
           tools: tools()
         })}

      {:error, reason} ->
        {:error, error(id, -32_602, reason)}
    end
  end

  defp route(%{"method" => "tools/list", "id" => id}, _project_id) do
    {:ok, success(id, %{tools: tools()})}
  end

  defp route(%{"method" => "tools/call", "id" => id, "params" => params}, project_id) do
    call_tool(id, params, project_id)
  end

  defp route(%{"method" => method, "id" => id}, _project_id) do
    {:error, error(id, -32_601, "Method not found: #{method}")}
  end

  defp route(%{"method" => _method}, _project_id) do
    {:ok, :notification}
  end

  ## Tool Dispatch

  defp call_tool(id, %{"name" => name, "arguments" => args}, project_id) do
    case find_tool(name) do
      {:ok, callback} -> execute_tool(id, name, callback, args, project_id)
      :error -> {:error, error(id, -32_601, "Unknown tool: #{name}")}
    end
  end

  defp call_tool(id, _, _project_id) do
    {:error, error(id, -32_602, "Missing 'name' or 'arguments'")}
  end

  defp find_tool(name) do
    @tool_modules
    |> Enum.flat_map(& &1.tools())
    |> Enum.find(&(&1.name == name))
    |> case do
      %{callback: cb} -> {:ok, cb}
      nil -> :error
    end
  end

  defp execute_tool(id, name, callback, args, project_id) do
    result =
      try do
        # Phase 1: callback.(args)
        # Phase 1.5+: callback.(args, project_id) — tools will be project-aware
        callback.(args)
      catch
        kind, reason ->
          Logger.error("Tool #{name} crashed: #{Exception.format(kind, reason, __STACKTRACE__)}")
          {:error, "Tool execution failed"}
      end

    # Suppress unused warning until Phase 1.5
    _ = project_id

    case result do
      {:ok, text} when is_binary(text) ->
        {:ok, success(id, %{content: [%{type: "text", text: text}]})}

      {:ok, data} when is_map(data) ->
        {:ok, success(id, data)}

      {:error, msg} when is_binary(msg) ->
        {:ok, success(id, %{content: [%{type: "text", text: msg}], isError: true})}

      other ->
        Logger.warning("Tool #{name} returned invalid result: #{inspect(other)}")

        {:ok,
         success(id, %{content: [%{type: "text", text: "Invalid tool response"}], isError: true})}
    end
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
