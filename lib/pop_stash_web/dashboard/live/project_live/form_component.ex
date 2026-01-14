defmodule PopStashWeb.Dashboard.ProjectLive.FormComponent do
  @moduledoc """
  LiveComponent for creating and editing projects.
  """

  use PopStashWeb.Dashboard, :live_component

  alias PopStash.Projects

  @impl true
  def mount(socket) do
    {:ok, socket}
  end

  @impl true
  def update(%{project: project} = assigns, socket) do
    changeset = Projects.Project.changeset(project, %{})

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:form, to_form(changeset))
     |> assign(:tags_input, Enum.join(project.tags || [], ", "))}
  end

  @impl true
  def handle_event("validate", %{"project" => project_params}, socket) do
    project_params = parse_tags(project_params)

    changeset =
      socket.assigns.project
      |> Projects.Project.changeset(project_params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:form, to_form(changeset))
     |> assign(:tags_input, project_params["tags_input"] || "")}
  end

  def handle_event("save", %{"project" => project_params}, socket) do
    project_params = parse_tags(project_params)
    save_project(socket, socket.assigns.action, project_params)
  end

  defp save_project(socket, :new, params) do
    name = params["name"]

    opts = [
      description: params["description"],
      tags: params["tags"] || []
    ]

    case Projects.create(name, opts) do
      {:ok, _project} ->
        {:noreply,
         socket
         |> put_flash(:info, "Project created successfully")
         |> push_navigate(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp parse_tags(%{"tags_input" => tags_input} = params) when is_binary(tags_input) do
    tags =
      tags_input
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    Map.put(params, "tags", tags)
  end

  defp parse_tags(params), do: Map.put(params, "tags", [])

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.form
        for={@form}
        id="project-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <div class="space-y-4">
          <.input
            field={@form[:name]}
            type="text"
            label="Name"
            placeholder="My Project"
          />

          <.textarea
            field={@form[:description]}
            label="Description"
            placeholder="A brief description of this project..."
            rows={3}
          />

          <div>
            <label class="block text-sm font-medium text-slate-700 mb-1">
              Tags
            </label>
            <input
              type="text"
              name="project[tags_input]"
              value={@tags_input}
              placeholder="tag1, tag2, tag3"
              class="w-full px-3 py-2 text-sm border border-slate-200 rounded focus:outline-none focus:ring-2 focus:ring-violet-500/20 focus:border-violet-500"
            />
            <p class="mt-1 text-xs text-slate-500">Separate tags with commas</p>
          </div>

          <div class="flex justify-end gap-3 pt-4">
            <.button type="button" variant="secondary" phx-click="close_modal">
              Cancel
            </.button>
            <.button type="submit" variant="primary" phx-disable-with="Saving...">
              {if @action == :new, do: "Create Project", else: "Update Project"}
            </.button>
          </div>
        </div>
      </.form>
    </div>
    """
  end
end
