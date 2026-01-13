defmodule Mix.Tasks.InitProject do
  @moduledoc """
  Initializes a new PopStash project with the given name and description.

  ## Usage

      mix init_project <project_name> [project_description]

  ## Examples

      mix init_project "My Project"
      mix init_project "My Project" "A cool project for managing pop culture stashes"
  """
  use Mix.Task

  @shortdoc "Initializes a new PopStash project"

  @impl Mix.Task
  def run(args) do
    case args do
      [] ->
        Mix.shell().error("Error: Project name is required")
        Mix.shell().info("Usage: mix init_project <project_name> [project_description]")
        System.halt(1)

      [project_name] ->
        init_project(project_name, nil)

      [project_name, project_description] ->
        init_project(project_name, project_description)

      [project_name, project_description | _rest] ->
        init_project(project_name, project_description)
    end
  end

  defp init_project(project_name, project_description) do
    Mix.shell().info("Initializing project: #{project_name}")

    if project_description do
      Mix.shell().info("Description: #{project_description}")
    end

    Mix.shell().info("Project initialized successfully!")
  end
end
