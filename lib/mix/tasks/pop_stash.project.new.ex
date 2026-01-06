defmodule Mix.Tasks.PopStash.Project.New do
  @moduledoc """
  Creates a new PopStash project.

  ## Usage

      mix pop_stash.project.new "My Project Name"
      mix pop_stash.project.new "My Project" --description "Optional description"
  """

  use Mix.Task

  @shortdoc "Creates a new PopStash project"

  @impl Mix.Task
  def run(args) do
    {:ok, _} = Application.ensure_all_started(:postgrex)
    {:ok, _} = Application.ensure_all_started(:ecto)
    {:ok, _} = PopStash.Repo.start_link()

    {opts, args, _} = OptionParser.parse(args, strict: [description: :string])

    case args do
      [name] ->
        create_project(name, opts)

      [] ->
        Mix.shell().error("Usage: mix pop_stash.project.new \"Project Name\" [--description \"desc\"]")

      _ ->
        Mix.shell().error("Too many arguments. Project name should be quoted if it contains spaces.")
    end
  end

  defp create_project(name, opts) do
    case PopStash.Projects.create(name, opts) do
      {:ok, project} -> print_success(project)
      {:error, changeset} -> print_error(changeset)
    end
  end

  defp print_success(project) do
    port = Application.get_env(:pop_stash, :mcp_port, 4001)

    Mix.shell().info("""

    ✓ Created project: #{project.id}

    Add to your workspace .claude/mcp_servers.json:

    {
      "pop_stash": {
        "url": "http://localhost:#{port}/mcp/#{project.id}"
      }
    }

    Note: If your app runs inside Docker, use host.docker.internal instead of localhost:

    {
      "pop_stash": {
        "url": "http://host.docker.internal:#{port}/mcp/#{project.id}"
      }
    }
    """)
  end

  defp print_error(changeset) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
          opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
        end)
      end)

    Mix.shell().error("Failed to create project: #{inspect(errors)}")
  end
end
