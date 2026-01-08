defmodule PopStash.CLI do
  @moduledoc """
  CLI commands for release eval.

  Usage:
    bin/pop_stash eval "PopStash.CLI.project_new(\"My Project\")"
    bin/pop_stash eval "PopStash.CLI.project_new(\"My Project\", \"Optional description\")"
    bin/pop_stash eval "PopStash.CLI.project_list()"
  """

  def project_new(name, description \\ nil) do
    start_app_without_server()

    opts = if description, do: [description: description], else: []

    case PopStash.Projects.create(name, opts) do
      {:ok, project} ->
        IO.puts("Created project: #{project.id}")
        IO.puts("")
        IO.puts("Claude Code config (.claude/mcp_servers.json):")
        IO.puts(~s|  {"pop_stash": {"url": "http://localhost:4001/mcp/#{project.id}"}}|)
        IO.puts("")
        IO.puts("Zed/Claude Desktop config (via mcp-proxy):")

        IO.puts(
          ~s|  mcp-proxy --transport streamablehttp http://localhost:4001/mcp/#{project.id}|
        )

      {:error, changeset} ->
        errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
        IO.puts(:stderr, "Error creating project: #{inspect(errors)}")
        System.halt(1)
    end
  end

  def project_list do
    start_app_without_server()

    projects = PopStash.Projects.list()

    if projects == [] do
      IO.puts("No projects yet.")
      IO.puts("")
      IO.puts("Create one with:")
      IO.puts(~s|  bin/pop_stash eval 'PopStash.CLI.project_new("My Project")'|)
    else
      IO.puts("Projects:")
      IO.puts("")

      for project <- projects do
        IO.puts("  #{project.id}")
        IO.puts("    Name: #{project.name}")

        if project.description do
          IO.puts("    Description: #{project.description}")
        end

        IO.puts("")
      end
    end
  end

  defp start_app_without_server do
    Application.put_env(:pop_stash, :start_server, false)
    {:ok, _} = Application.ensure_all_started(:pop_stash)
  end
end
