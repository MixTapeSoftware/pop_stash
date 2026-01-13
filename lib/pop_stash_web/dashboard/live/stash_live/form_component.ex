defmodule PopStashWeb.Dashboard.StashLive.FormComponent do
  @moduledoc """
  Form component for creating and editing stashes.
  """

  use PopStashWeb.Dashboard, :live_component

  alias PopStash.Memory

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.form for={@form} id="stash-form" phx-target={@myself} phx-submit="save" phx-change="validate">
        <div class="space-y-4">
          <.select
            field={@form[:project_id]}
            label="Project"
            options={Enum.map(@projects, &{&1.name, &1.id})}
            prompt="Select a project"
          />

          <.input
            field={@form[:name]}
            label="Name"
            placeholder="e.g., auth-refactor-context"
          />

          <.textarea
            field={@form[:summary]}
            label="Summary"
            rows={6}
            placeholder="Describe the context, what files are involved, and key decisions..."
          />

          <.textarea
            field={@form[:files]}
            label="Files"
            rows={4}
            placeholder="lib/my_app/auth.ex&#10;lib/my_app_web/controllers/session_controller.ex"
          />

          <.tag_input
            field={@form[:tags]}
            label="Tags"
          />

          <.input
            field={@form[:expires_at]}
            type="datetime-local"
            label="Expires At (optional)"
          />
        </div>

        <div class="flex justify-end gap-2 mt-6 pt-4 border-t border-slate-100">
          <.button type="button" variant="secondary" phx-click="close_modal">
            Cancel
          </.button>
          <.button type="submit" variant="primary" phx-disable-with="Saving...">
            {if @action == :new, do: "Create Stash", else: "Update Stash"}
          </.button>
        </div>
      </.form>
    </div>
    """
  end

  @impl true
  def update(%{stash: stash} = assigns, socket) do
    # Convert files array to newline-separated string for editing
    files_string =
      case stash.files do
        nil -> ""
        files -> Enum.join(files, "\n")
      end

    # Convert tags array to comma-separated string
    tags_string =
      case stash.tags do
        nil -> ""
        tags -> Enum.join(tags, ", ")
      end

    # Format expires_at for datetime-local input
    expires_at_string =
      case stash.expires_at do
        nil -> nil
        %DateTime{} = dt -> Calendar.strftime(dt, "%Y-%m-%dT%H:%M")
        %NaiveDateTime{} = dt -> Calendar.strftime(dt, "%Y-%m-%dT%H:%M")
      end

    form_data = %{
      "project_id" => stash.project_id,
      "name" => stash.name,
      "summary" => stash.summary,
      "files" => files_string,
      "tags" => tags_string,
      "expires_at" => expires_at_string
    }

    form = to_form(form_data, as: "stash")

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:form, form)}
  end

  @impl true
  def handle_event("validate", %{"stash" => params}, socket) do
    form = to_form(params, as: "stash")
    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("save", %{"stash" => params}, socket) do
    save_stash(socket, socket.assigns.action, params)
  end

  defp save_stash(socket, :new, params) do
    project_id = params["project_id"]
    name = params["name"]
    summary = params["summary"]

    opts = [
      files: parse_files(params["files"]),
      tags: parse_tags(params["tags"]),
      expires_at: parse_expires_at(params["expires_at"])
    ]

    case Memory.create_stash(project_id, name, summary, opts) do
      {:ok, stash} ->
        {:noreply,
         socket
         |> put_flash(:info, "Stash created successfully")
         |> push_navigate(to: ~p"/pop_stash/stashes/#{stash.id}")}

      {:error, changeset} ->
        form =
          to_form(changeset_to_params(changeset, params),
            as: "stash",
            errors: format_errors(changeset)
          )

        {:noreply, assign(socket, :form, form)}
    end
  end

  defp save_stash(socket, :edit, params) do
    attrs = %{
      name: params["name"],
      summary: params["summary"],
      files: parse_files(params["files"]),
      tags: parse_tags(params["tags"]),
      expires_at: parse_expires_at(params["expires_at"])
    }

    case Memory.update_stash(socket.assigns.stash, attrs) do
      {:ok, stash} ->
        {:noreply,
         socket
         |> put_flash(:info, "Stash updated successfully")
         |> push_navigate(to: ~p"/pop_stash/stashes/#{stash.id}")}

      {:error, changeset} ->
        form =
          to_form(changeset_to_params(changeset, params),
            as: "stash",
            errors: format_errors(changeset)
          )

        {:noreply, assign(socket, :form, form)}
    end
  end

  defp parse_files(nil), do: []
  defp parse_files(""), do: []

  defp parse_files(files_string) do
    files_string
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_tags(nil), do: []
  defp parse_tags(""), do: []

  defp parse_tags(tags_string) do
    tags_string
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_expires_at(nil), do: nil
  defp parse_expires_at(""), do: nil

  defp parse_expires_at(datetime_string) do
    case NaiveDateTime.from_iso8601(datetime_string <> ":00") do
      {:ok, naive} -> DateTime.from_naive!(naive, "Etc/UTC")
      _ -> nil
    end
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
