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
        Mix.shell().error(
          ~s(Usage: mix pop_stash.project.new "Project Name" [--description "desc"])
        )

      _ ->
        Mix.shell().error(
          "Too many arguments. Project name should be quoted if it contains spaces."
        )
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

    ─────────────────────────────────────────────────────────────────────────────
    RECOMMENDED HOOKS CONFIGURATION
    ─────────────────────────────────────────────────────────────────────────────

    Add to your project's .claude/settings.json to ensure agents use PopStash:

    {
      "hooks": {
        "SessionStart": [
          {
            "hooks": [
              {
                "type": "prompt",
                "prompt": "Before starting work, search for previous decisions, insights or current plans that might apply to this task."
              }
            ]
          }
        ],
        "Stop": [
          {
            "hooks": [
              {
                "type": "prompt",
                "prompt": "If meaningful work occurred: save plans, record insights, document decisions, and/or save a compacted current context."
              }
            ]
          }
        ]
      }
    }

    ─────────────────────────────────────────────────────────────────────────────
    AGENTS.md PROMPT
    ─────────────────────────────────────────────────────────────────────────────

    Add the following to your project's AGENTS.md file so AI agents know when
    to use PopStash:

    #{agents_md_prompt()}
    ─────────────────────────────────────────────────────────────────────────────
    """)
  end

  @doc """
  Returns the AGENTS.md prompt for PopStash integration.
  """
  def agents_md_prompt do
    """
    ## Memory & Context Management (PopStash)

    You have access to PopStash, a persistent memory system via MCP. Use it to maintain
    context across sessions and preserve important knowledge about this codebase.

    ### When to Use Each Tool

    **`stash` / `pop` - Working Context**
    - STASH when: switching tasks, context is getting long, before exploring tangents
    - POP when: resuming work, need previous context, starting a related task
    - Use short descriptive names like "auth-refactor", "bug-123-investigation"

    **`insight` / `recall` - Persistent Knowledge**
    - INSIGHT when: you discover something non-obvious about the codebase, learn how
      components interact, find undocumented behavior, identify patterns or conventions
    - RECALL when: starting work in an unfamiliar area, before making architectural
      changes, when something "should work" but doesn't
    - Good insights: "The auth middleware silently converts guest users to anonymous
      sessions", "API rate limits reset at UTC midnight, not rolling 24h"

    **`decide` / `get_decisions` - Architectural Decisions**
    - DECIDE when: making or encountering significant technical choices, choosing between
      approaches, establishing patterns for the codebase
    - GET_DECISIONS when: about to make changes in an area, wondering "why is it done
      this way?", onboarding to a new part of the codebase
    - Decisions are immutable - new decisions on the same topic preserve history

    ### Best Practices

    1. **Be proactive**: Don't wait to be asked. Stash context before it's lost.
    2. **Search first**: Before diving into unfamiliar code, recall/get_decisions for that area.
    3. **Atomic insights**: One concept per insight. Easier to find and stays relevant.
    4. **Descriptive keys**: Use hierarchical keys like "auth/session-handling" or "api/rate-limits".
    5. **Link decisions to code**: Reference specific files/functions when documenting decisions.
    """
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
