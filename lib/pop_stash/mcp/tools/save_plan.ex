defmodule PopStash.MCP.Tools.SavePlan do
  @moduledoc """
  MCP tool for saving plans.
  """

  @behaviour PopStash.MCP.ToolBehaviour

  alias PopStash.Memory

  @impl true
  def tools do
    [
      %{
        name: "save_plan",
        description: """
        Save a project plan or roadmap with versioning.

        Plans are versioned documents that capture project roadmaps, architecture designs,
        or implementation strategies. Each plan has a title and version, allowing you to
        track changes over time.

        Use this to:
        - Document project roadmaps and milestones
        - Save architecture design documents
        - Track implementation plans across iterations
        - Version project documentation

        The combination of title + version must be unique within a project.
        """,
        inputSchema: %{
          type: "object",
          properties: %{
            title: %{
              type: "string",
              description: "Plan title (e.g., 'Q1 2024 Roadmap', 'Authentication Architecture')"
            },
            version: %{
              type: "string",
              description: "Version identifier (e.g., 'v1.0', '2024-01-15', 'draft')"
            },
            body: %{
              type: "string",
              description: "Plan content (supports markdown)"
            },
            tags: %{
              type: "array",
              items: %{type: "string"},
              description: "Optional tags for categorization"
            },
            thread_id: %{
              type: "string",
              description:
                "Optional thread ID to connect revisions (omit for new, pass back for revisions)"
            }
          },
          required: ["title", "version", "body"]
        },
        callback: &__MODULE__.execute/2
      }
    ]
  end

  def execute(args, %{project_id: project_id}) do
    opts =
      [tags: Map.get(args, "tags", [])]
      |> maybe_add_thread_id(args["thread_id"])

    case Memory.create_plan(project_id, args["title"], args["version"], args["body"], opts) do
      {:ok, plan} ->
        {:ok,
         """
         ✓ Saved plan "#{plan.title}" (#{plan.version})

         Use `get_plan` with title "#{plan.title}" to retrieve it.
         Use `search_plans` to find plans by content.
         (thread_id: #{plan.thread_id})
         """}

      {:error, %Ecto.Changeset{errors: [project_id: _]}} ->
        {:error, "Project not found"}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, format_errors(changeset)}

      {:error, reason} ->
        {:error, "Failed to save plan: #{inspect(reason)}"}
    end
  end

  defp maybe_add_thread_id(opts, nil), do: opts
  defp maybe_add_thread_id(opts, thread_id), do: Keyword.put(opts, :thread_id, thread_id)

  defp format_errors(changeset) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
      |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)

    if String.contains?(errors, "has already been taken") do
      "A plan with this title and version already exists. Use a different version number or update the existing plan."
    else
      errors
    end
  end
end
