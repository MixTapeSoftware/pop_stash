defmodule PopStashWeb.Dashboard.DecisionLive.FormComponent do
  @moduledoc """
  Form component for creating decisions.

  Note: Decisions are immutable by design. This form only supports
  creating new decisions, not editing existing ones.
  """

  use PopStashWeb.Dashboard, :live_component

  alias PopStash.Memory

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.form
        for={@form}
        id="decision-form"
        phx-target={@myself}
        phx-submit="save"
        phx-change="validate"
      >
        <div class="space-y-4">
          <.select
            field={@form[:project_id]}
            label="Project"
            options={Enum.map(@projects, &{&1.name, &1.id})}
            prompt="Select a project"
          />

          <div>
            <label for={@form[:title].id} class="block text-xs font-medium text-slate-600 mb-1">
              Title
            </label>
            <input
              type="text"
              name={@form[:title].name}
              id={@form[:title].id}
              value={Phoenix.HTML.Form.normalize_value("text", @form[:title].value)}
              list="title-suggestions"
              placeholder="e.g., database-choice, auth-strategy, api-design"
              class={[
                "w-full px-3 py-2 text-sm text-slate-900 font-mono",
                "bg-white border border-slate-200 rounded",
                "focus:outline-none focus:ring-2 focus:ring-violet-500/20 focus:border-violet-500",
                "placeholder:text-slate-400"
              ]}
            />
            <datalist id="title-suggestions">
              <option :for={title <- @titles} value={title} />
            </datalist>
            <p class="text-xs text-slate-400 mt-1">
              Titles are normalized (lowercased, trimmed) for consistent matching
            </p>
          </div>

          <.textarea
            field={@form[:body]}
            label="Body"
            rows={4}
            placeholder="What was decided? Be specific and clear..."
          />

          <.textarea
            field={@form[:reasoning]}
            label="Reasoning (optional)"
            rows={4}
            placeholder="Why was this decision made? What alternatives were considered?"
          />

          <.tag_input
            field={@form[:tags]}
            label="Tags"
          />
        </div>

        <div class="flex justify-end gap-2 mt-6 pt-4 border-t border-slate-100">
          <.button type="button" variant="secondary" phx-click="close_modal">
            Cancel
          </.button>
          <.button type="submit" variant="primary" phx-disable-with="Saving...">
            Record Decision
          </.button>
        </div>
      </.form>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    decision = assigns.decision

    # Convert tags array to comma-separated string
    tags_string =
      case decision.tags do
        nil -> ""
        tags -> Enum.join(tags, ", ")
      end

    form_data = %{
      "project_id" => decision.project_id,
      "title" => decision.title,
      "body" => decision.body,
      "reasoning" => decision.reasoning,
      "tags" => tags_string
    }

    form = to_form(form_data, as: "decision")

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:form, form)}
  end

  @impl true
  def handle_event("validate", %{"decision" => params}, socket) do
    form = to_form(params, as: "decision")
    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("save", %{"decision" => params}, socket) do
    save_decision(socket, params)
  end

  defp save_decision(socket, params) do
    project_id = params["project_id"]
    title = params["title"]
    body = params["body"]

    opts =
      [
        reasoning: normalize_reasoning(params["reasoning"]),
        tags: parse_tags(params["tags"])
      ]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    case Memory.create_decision(project_id, title, body, opts) do
      {:ok, created_decision} ->
        {:noreply,
         socket
         |> put_flash(:info, "Decision recorded successfully")
         |> push_navigate(to: ~p"/decisions/#{created_decision.id}")}

      {:error, changeset} ->
        form =
          to_form(changeset_to_params(changeset, params),
            as: "decision",
            errors: format_errors(changeset)
          )

        {:noreply, assign(socket, :form, form)}
    end
  end

  defp normalize_reasoning(nil), do: nil
  defp normalize_reasoning(""), do: nil
  defp normalize_reasoning(reasoning), do: String.trim(reasoning)

  defp parse_tags(nil), do: []
  defp parse_tags(""), do: []

  defp parse_tags(tags_string) do
    tags_string
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp changeset_to_params(_changeset, params), do: params

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
