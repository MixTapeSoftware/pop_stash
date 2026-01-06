defmodule Mix.Tasks.PopStash.Project.List do
  @moduledoc """
  Lists all PopStash projects.

  ## Usage

      mix pop_stash.project.list
  """

  use Mix.Task

  @shortdoc "Lists all PopStash projects"

  @impl Mix.Task
  def run(_args) do
    {:ok, _} = Application.ensure_all_started(:postgrex)
    {:ok, _} = Application.ensure_all_started(:ecto)
    {:ok, _} = PopStash.Repo.start_link()

    projects = PopStash.Projects.list()

    if Enum.empty?(projects) do
      Mix.shell().info("No projects found. Create one with: mix pop_stash.project.new \"Project Name\"")
    else
      Mix.shell().info("\nProjects:\n")

      for project <- projects do
        age = format_age(project.inserted_at)
        desc = if project.description, do: " - #{project.description}", else: ""
        Mix.shell().info("  #{project.id}  #{project.name}#{desc}  (#{age})")
      end

      Mix.shell().info("")
    end
  end

  defp format_age(datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3_600 -> "#{div(diff, 60)} minutes ago"
      diff < 86_400 -> "#{div(diff, 3_600)} hours ago"
      diff < 604_800 -> "#{div(diff, 86_400)} days ago"
      true -> "#{div(diff, 604_800)} weeks ago"
    end
  end
end
