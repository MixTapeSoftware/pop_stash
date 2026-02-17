defmodule PopStashWeb.Dashboard.InsightLive.FormComponent do
  @moduledoc """
  Form component for creating and editing insights.
  """

  use PopStashWeb.Dashboard, :live_component

  alias PopStash.Memory

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.form
        for={@form}
        id="insight-form"
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

          <.input
            field={@form[:title]}
            label="Title (optional)"
            placeholder="e.g., testing-strategy, code-style-preferences"
          />

          <.textarea
            field={@form[:body]}
            label="Body"
            rows={8}
            placeholder="Describe the insight, pattern, or learned knowledge..."
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
            {if @action == :new, do: "Create Insight", else: "Update Insight"}
          </.button>
        </div>
      </.form>
    </div>
    """
  end

  @impl true
  def update(%{insight: insight} = assigns, socket) do
    # Convert tags array to comma-separated string
    tags_string =
      case insight.tags do
        nil -> ""
        tags -> Enum.join(tags, ", ")
      end

    form_data = %{
      "project_id" => insight.project_id,
      "title" => insight.title,
      "body" => insight.body,
      "tags" => tags_string
    }

    form = to_form(form_data, as: "insight")

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:form, form)}
  end

  @impl true
  def handle_event("validate", %{"insight" => params}, socket) do
    form = to_form(params, as: "insight")
    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("save", %{"insight" => params}, socket) do
    save_insight(socket, socket.assigns.action, params)
  end

  defp save_insight(socket, :new, params) do
    project_id = params["project_id"]
    body = params["body"]

    opts =
      [
        title: normalize_title(params["title"]),
        tags: parse_tags(params["tags"])
      ]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    case Memory.create_insight(project_id, body, opts) do
      {:ok, insight} ->
        {:noreply,
         socket
         |> put_flash(:info, "Insight created successfully")
         |> push_navigate(to: ~p"/insights/#{insight.id}")}

      {:error, changeset} ->
        form =
          to_form(changeset_to_params(changeset, params),
            as: "insight",
            errors: format_errors(changeset)
          )

        {:noreply, assign(socket, :form, form)}
    end
  end

  defp save_insight(socket, :edit, params) do
    body = params["body"]

    case Memory.update_insight(socket.assigns.insight.id, body) do
      {:ok, insight} ->
        {:noreply,
         socket
         |> put_flash(:info, "Insight updated successfully")
         |> push_navigate(to: ~p"/insights/#{insight.id}")}

      {:error, changeset} ->
        form =
          to_form(changeset_to_params(changeset, params),
            as: "insight",
            errors: format_errors(changeset)
          )

        {:noreply, assign(socket, :form, form)}
    end
  end

  defp normalize_title(nil), do: nil
  defp normalize_title(""), do: nil
  defp normalize_title(title), do: String.trim(title)

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
