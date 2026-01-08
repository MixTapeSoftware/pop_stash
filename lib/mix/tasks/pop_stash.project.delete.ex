defmodule Mix.Tasks.PopStash.Project.Delete do
  @moduledoc """
  Deletes a PopStash project and all associated data.

  ## Usage

      mix pop_stash.project.delete a1b2c3d4-e5f6-7890-abcd-ef1234567890
      mix pop_stash.project.delete a1b2c3d4-e5f6-7890-abcd-ef1234567890 --yes  # Skip confirmation
  """

  use Mix.Task

  @shortdoc "Deletes a PopStash project"

  @impl Mix.Task
  def run(args) do
    {:ok, _} = Application.ensure_all_started(:postgrex)
    {:ok, _} = Application.ensure_all_started(:ecto)
    {:ok, _} = PopStash.Repo.start_link()

    {opts, args, _} = OptionParser.parse(args, strict: [yes: :boolean])

    case args do
      [project_id] ->
        delete_project(project_id, opts)

      [] ->
        Mix.shell().error("Usage: mix pop_stash.project.delete PROJECT_ID [--yes]")

      _ ->
        Mix.shell().error("Too many arguments.")
    end
  end

  defp delete_project(project_id, opts) do
    case PopStash.Projects.get(project_id) do
      {:ok, project} -> maybe_delete(project, opts)
      {:error, :not_found} -> Mix.shell().error("Project not found: #{project_id}")
    end
  end

  defp maybe_delete(project, opts) do
    if opts[:yes] || confirm_delete(project) do
      do_delete(project.id)
    else
      Mix.shell().info("Cancelled.")
    end
  end

  defp do_delete(project_id) do
    case PopStash.Projects.delete(project_id) do
      {:ok, _} -> Mix.shell().info("✓ Deleted project: #{project_id}")
      {:error, reason} -> Mix.shell().error("Failed to delete project: #{inspect(reason)}")
    end
  end

  defp confirm_delete(project) do
    Mix.shell().yes?("""

    Are you sure you want to delete project "#{project.name}" (#{project.id})?

    This will permanently delete all:
      • Stashes
      • Insights
      • Decisions
      • Locks
      • Sessions
      • Activity logs

    Delete this project?
    """)
  end
end
