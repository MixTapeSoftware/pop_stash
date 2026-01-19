defmodule PopStash.MCP.Tools.Decide do
  @moduledoc """
  MCP tool for recording architectural decisions.
  """

  @behaviour PopStash.MCP.ToolBehaviour

  alias PopStash.Memory

  @impl true
  def tools do
    [
      %{
        name: "decide",
        description: """
        Record architectural and important technical decisions with rationale.

        WHEN TO USE:
        - Making significant technical choices (framework, database, architecture)
        - Choosing between valid approaches (REST vs GraphQL, sync vs async)
        - Establishing patterns for the codebase (error handling, testing strategy)
        - Rejecting alternatives (document why X was NOT chosen)

        WHAT MAKES A GOOD DECISION:
        - "We chose Phoenix LiveView over React for the admin UI"
        - "Using PostgreSQL JSONB for flexible schema instead of EAV tables"
        - "Rate limiting at nginx level, not application level"
        - "Event sourcing for audit trail, traditional CRUD for reporting"

        THREAD_ID MECHANICS:
        - Omit thread_id for NEW decisions (system generates one)
        - Pass back thread_id to create a REVISION (decision evolved/changed)
        - All revisions share the same thread_id
        - Use timestamps to determine latest version

        BEST PRACTICES:
        - Use clear titles that describe the decision area (e.g., "authentication", "api-design")
        - Explain WHAT was decided in the body
        - Explain WHY in reasoning (this is the most valuable part!)
        - Link to relevant code, docs, or tickets
        - Document rejected alternatives and why they were rejected

        TYPICAL WORKFLOW:
        1. decide(title: "auth-method", body: "Use JWT with refresh tokens", reasoning: "Stateless, scales horizontally...")
        2. ... later, requirements change ...
        3. decide(title: "auth-method", body: "Switch to session tokens", reasoning: "Need to revoke immediately...", thread_id: "dthr_xyz")

        Returns thread_id for creating revisions.
        """,
        inputSchema: %{
          type: "object",
          properties: %{
            title: %{
              type: "string",
              description:
                "What area this decision affects (e.g., 'authentication', 'database', 'api-design')"
            },
            body: %{
              type: "string",
              description: "What was decided"
            },
            reasoning: %{
              type: "string",
              description: "Why this decision was made (optional but recommended)"
            },
            tags: %{
              type: "array",
              items: %{type: "string"},
              description: "Optional tags for categorization (e.g., ['api', 'breaking-change'])"
            },
            thread_id: %{
              type: "string",
              description:
                "Optional thread ID to connect revisions (omit for new, pass back for revisions)"
            }
          },
          required: ["title", "body"]
        },
        callback: &__MODULE__.execute/2
      }
    ]
  end

  def execute(args, %{project_id: project_id}) do
    opts =
      []
      |> maybe_add_opt(:reasoning, args["reasoning"])
      |> maybe_add_opt(:tags, args["tags"])
      |> maybe_add_opt(:thread_id, args["thread_id"])

    case Memory.create_decision(project_id, args["title"], args["body"], opts) do
      {:ok, decision} ->
        {:ok,
         """
         Decision recorded for title "#{decision.title}".
         Use `get_decisions` to retrieve decisions by title.
         (thread_id: #{decision.thread_id})
         """}

      {:error, changeset} ->
        {:error, format_errors(changeset)}
    end
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
    |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)
  end

  defp maybe_add_opt(opts, _key, nil), do: opts
  defp maybe_add_opt(opts, key, value), do: Keyword.put(opts, key, value)
end
