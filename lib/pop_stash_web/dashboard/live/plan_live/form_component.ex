defmodule PopStashWeb.Dashboard.PlanLive.FormComponent do
  @moduledoc """
  Form component for creating and editing plans.
  """

  use PopStashWeb.Dashboard, :live_component

  alias PopStash.Memory
  alias PopStash.Memory.Plan

  @impl true
  def mount(socket) do
    {:ok, socket}
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_changeset()

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"plan" => plan_params}, socket) do
    changeset =
      %Plan{}
      |> Ecto.Changeset.cast(plan_params, [:title, :version, :body, :tags, :project_id])
      |> Ecto.Changeset.validate_required([:title, :version, :body, :project_id])
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  def handle_event("save", %{"plan" => plan_params}, socket) do
    save_plan(socket, socket.assigns.action, plan_params)
  end

  def handle_event("select_existing_title", %{"title" => title}, socket) do
    changeset =
      socket.assigns.changeset
      |> Ecto.Changeset.put_change(:title, title)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  defp save_plan(socket, :new, plan_params) do
    # Parse tags from comma-separated string
    tags = parse_tags(plan_params["tags"])

    case Memory.create_plan(
           plan_params["project_id"],
           plan_params["title"],
           plan_params["body"],
           tags: tags
         ) do
      {:ok, _plan} ->
        {:noreply,
         socket
         |> put_flash(:info, "Plan created successfully")
         |> push_navigate(to: socket.assigns.return_to)}

      {:error, changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  defp save_plan(socket, :edit, plan_params) do
    case Memory.update_plan(socket.assigns.plan.id, plan_params["body"]) do
      {:ok, _plan} ->
        {:noreply,
         socket
         |> put_flash(:info, "Plan updated successfully")
         |> push_navigate(to: socket.assigns.return_to)}

      {:error, changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  defp assign_changeset(socket) do
    changeset =
      %Plan{}
      |> Ecto.Changeset.cast(%{}, [:title, :version, :body, :tags, :project_id])
      |> Map.put(:action, :validate)

    assign(socket, :changeset, changeset)
  end

  defp parse_tags(nil), do: []
  defp parse_tags(""), do: []

  defp parse_tags(tags_string) when is_binary(tags_string) do
    tags_string
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_tags(tags) when is_list(tags), do: tags

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.form
        for={@changeset}
        id="plan-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <div class="space-y-4">
          <!-- Project Selection -->
          <div>
            <label for="plan_project_id" class="block text-sm font-medium text-slate-700 mb-1">
              Project <span class="text-red-500">*</span>
            </label>
            <select
              name="plan[project_id]"
              id="plan_project_id"
              class="w-full px-3 py-2 text-sm bg-white border border-slate-200 rounded focus:outline-none focus:ring-2 focus:ring-violet-500/20 focus:border-violet-500"
              required
            >
              <option value="">Select a project...</option>
              <option :for={project <- @projects} value={project.id}>
                {project.name}
              </option>
            </select>
            <.input_error field={@changeset[:project_id]} />
          </div>
          
    <!-- Title -->
          <div>
            <label for="plan_title" class="block text-sm font-medium text-slate-700 mb-1">
              Title <span class="text-red-500">*</span>
            </label>
            
    <!-- Existing Titles Dropdown (optional) -->
            <div :if={@titles && @titles != []} class="mb-2">
              <label class="text-xs text-slate-500">Or select existing title:</label>
              <select
                phx-change="select_existing_title"
                phx-target={@myself}
                name="existing_title"
                class="w-full mt-1 px-3 py-2 text-sm bg-slate-50 border border-slate-200 rounded focus:outline-none focus:ring-2 focus:ring-violet-500/20 focus:border-violet-500"
              >
                <option value="">-- Select existing title --</option>
                <option :for={title <- @titles} value={title}>
                  {title}
                </option>
              </select>
            </div>

            <input
              type="text"
              name="plan[title]"
              id="plan_title"
              value={Ecto.Changeset.get_field(@changeset, :title)}
              class="w-full px-3 py-2 text-sm bg-white border border-slate-200 rounded focus:outline-none focus:ring-2 focus:ring-violet-500/20 focus:border-violet-500"
              placeholder="e.g., Development Roadmap, Architecture Plan"
              required
            />
            <.input_error field={@changeset[:title]} />
          </div>
          
    <!-- Version -->
          <div>
            <label for="plan_version" class="block text-sm font-medium text-slate-700 mb-1">
              Version <span class="text-red-500">*</span>
            </label>
            <input
              type="text"
              name="plan[version]"
              id="plan_version"
              value={Ecto.Changeset.get_field(@changeset, :version)}
              class="w-full px-3 py-2 text-sm bg-white border border-slate-200 rounded focus:outline-none focus:ring-2 focus:ring-violet-500/20 focus:border-violet-500"
              placeholder="e.g., v1.0, v2.0, draft-1"
              required
            />
            <p class="mt-1 text-xs text-slate-500">
              Use any versioning scheme you prefer (v1.0, 2024-01, draft-1, etc.)
            </p>
            <.input_error field={@changeset[:version]} />
          </div>
          
    <!-- Body -->
          <div>
            <label for="plan_body" class="block text-sm font-medium text-slate-700 mb-1">
              Content <span class="text-red-500">*</span>
            </label>
            <textarea
              name="plan[body]"
              id="plan_body"
              class="w-full px-3 py-2 text-sm bg-white border border-slate-200 rounded focus:outline-none focus:ring-2 focus:ring-violet-500/20 focus:border-violet-500"
              rows="15"
              placeholder="Enter plan content (Markdown supported)..."
              required
            >{Ecto.Changeset.get_field(@changeset, :body)}</textarea>
            <p class="mt-1 text-xs text-slate-500">
              Supports Markdown formatting. Use headers, lists, code blocks, etc.
            </p>
            <.input_error field={@changeset[:body]} />
          </div>
          
    <!-- Tags -->
          <div>
            <label for="plan_tags" class="block text-sm font-medium text-slate-700 mb-1">
              Tags
            </label>
            <input
              type="text"
              name="plan[tags]"
              id="plan_tags"
              value={format_tags(Ecto.Changeset.get_field(@changeset, :tags))}
              class="w-full px-3 py-2 text-sm bg-white border border-slate-200 rounded focus:outline-none focus:ring-2 focus:ring-violet-500/20 focus:border-violet-500"
              placeholder="e.g., roadmap, architecture, q1-2024"
            />
            <p class="mt-1 text-xs text-slate-500">
              Comma-separated list of tags for categorization
            </p>
            <.input_error field={@changeset[:tags]} />
          </div>
        </div>
        
    <!-- Form Actions -->
        <div class="mt-6 flex gap-3">
          <.button type="submit" variant="primary">
            {if @action == :new, do: "Create Plan", else: "Update Plan"}
          </.button>
          <.link_button navigate={@return_to} variant="secondary">
            Cancel
          </.link_button>
        </div>
      </.form>
    </div>
    """
  end

  defp format_tags(nil), do: ""
  defp format_tags([]), do: ""
  defp format_tags(tags) when is_list(tags), do: Enum.join(tags, ", ")
  defp format_tags(tags), do: tags

  defp input_error(assigns) do
    ~H"""
    <div :if={@field && @field.errors != []} class="mt-1">
      <span :for={error <- @field.errors} class="text-xs text-red-600">
        {elem(error, 0)}
      </span>
    </div>
    """
  end
end
