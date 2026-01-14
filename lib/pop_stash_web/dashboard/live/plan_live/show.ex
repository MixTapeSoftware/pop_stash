defmodule PopStashWeb.Dashboard.PlanLive.Show do
  @moduledoc """
  LiveView for viewing and editing individual plans.
  """

  use PopStashWeb.Dashboard, :live_view

  alias PopStash.Memory
  alias PopStash.Memory.Plan
  alias PopStash.Projects
  alias PopStash.Repo

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(PopStash.PubSub, "memory:events")
    end

    projects = Projects.list()

    socket =
      socket
      |> assign(:current_path, "/pop_stash/plans")
      |> assign(:projects, projects)
      |> assign(:versions, [])
      |> assign(:editing, false)

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id} = params, _url, socket) do
    case Repo.get(Plan, id) do
      nil ->
        socket =
          socket
          |> put_flash(:error, "Plan not found")
          |> push_navigate(to: ~p"/pop_stash/plans")

        {:noreply, socket}

      plan ->
        plan = Repo.preload(plan, :project)

        socket =
          socket
          |> assign(:page_title, "Plan: #{plan.title}")
          |> assign(:plan, plan)
          |> assign(:project, plan.project)
          |> load_versions()
          |> apply_action(socket.assigns.live_action, params)

        {:noreply, socket}
    end
  end

  defp apply_action(socket, :show, _params) do
    assign(socket, :editing, false)
  end

  defp apply_action(socket, :edit, _params) do
    assign(socket, :editing, true)
  end

  @impl true
  def handle_event("edit", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/pop_stash/plans/#{socket.assigns.plan.id}/edit")}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/pop_stash/plans/#{socket.assigns.plan.id}")}
  end

  def handle_event("save", %{"plan" => plan_params}, socket) do
    case Memory.update_plan(socket.assigns.plan.id, plan_params["body"]) do
      {:ok, updated_plan} ->
        updated_plan = Repo.preload(updated_plan, :project)

        socket =
          socket
          |> assign(:plan, updated_plan)
          |> assign(:editing, false)
          |> put_flash(:info, "Plan updated successfully")
          |> push_patch(to: ~p"/pop_stash/plans/#{updated_plan.id}")

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  def handle_event("delete", _params, socket) do
    case Memory.delete_plan(socket.assigns.plan.id) do
      :ok ->
        socket =
          socket
          |> put_flash(:info, "Plan deleted successfully")
          |> push_navigate(to: ~p"/pop_stash/plans")

        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to delete plan")}
    end
  end

  def handle_event("create_version", _params, socket) do
    {:noreply,
     push_navigate(socket, to: ~p"/pop_stash/plans/new?base_plan_id=#{socket.assigns.plan.id}")}
  end

  @impl true
  def handle_info({:plan_updated, %{id: id}}, socket) do
    if socket.assigns.plan.id == id do
      plan = Repo.get!(Plan, id) |> Repo.preload(:project)
      {:noreply, assign(socket, :plan, plan)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:plan_deleted, id}, socket) do
    if socket.assigns.plan.id == id do
      socket =
        socket
        |> put_flash(:info, "This plan has been deleted")
        |> push_navigate(to: ~p"/pop_stash/plans")

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  defp load_versions(socket) do
    versions =
      Memory.list_plan_versions(socket.assigns.plan.project_id, socket.assigns.plan.title)
      |> Enum.reject(&(&1.id == socket.assigns.plan.id))

    assign(socket, :versions, versions)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.page_header
        title={@plan.title}
        subtitle={"Version #{@plan.version} • #{@project.name}"}
      >
        <:actions>
          <.button
            :if={!@editing}
            phx-click="create_version"
            variant="secondary"
            size="sm"
          >
            <.icon name="hero-document-duplicate" class="size-4" /> New Version
          </.button>
          <.button
            :if={!@editing}
            phx-click="edit"
            variant="secondary"
            size="sm"
          >
            <.icon name="hero-pencil" class="size-4" /> Edit
          </.button>
          <.button
            :if={!@editing}
            phx-click="delete"
            variant="ghost"
            size="sm"
            data-confirm="Are you sure you want to delete this plan version?"
          >
            <.icon name="hero-trash" class="size-4 text-red-500" />
          </.button>
        </:actions>
      </.page_header>
      
    <!-- Edit Form -->
      <div :if={@editing} class="mb-6">
        <form phx-submit="save">
          <div class="space-y-4">
            <div>
              <label class="block text-sm font-medium text-slate-700 mb-2">
                Body
              </label>
              <textarea
                name="plan[body]"
                class="w-full px-3 py-2 text-sm bg-white border border-slate-200 rounded focus:outline-none focus:ring-2 focus:ring-violet-500/20 focus:border-violet-500"
                rows="20"
                placeholder="Enter plan content (Markdown supported)..."
                required
              >{@plan.body}</textarea>
            </div>
            <div class="flex gap-3">
              <.button type="submit" variant="primary">
                Save Changes
              </.button>
              <.button type="button" phx-click="cancel_edit" variant="secondary">
                Cancel
              </.button>
            </div>
          </div>
        </form>
      </div>
      
    <!-- Plan Content -->
      <div :if={!@editing} class="bg-white rounded-lg shadow-sm border border-slate-200">
        <div class="p-6">
          <!-- Metadata -->
          <div class="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6 text-sm">
            <div>
              <span class="text-slate-500">Version:</span>
              <span class="ml-2 font-mono bg-slate-100 px-1.5 py-0.5 rounded">
                {@plan.version}
              </span>
            </div>
            <div>
              <span class="text-slate-500">Project:</span>
              <.link
                navigate={~p"/pop_stash/projects/#{@project.id}"}
                class="ml-2 text-violet-600 hover:text-violet-700"
              >
                {@project.name}
              </.link>
            </div>
            <div>
              <span class="text-slate-500">Created:</span>
              <span class="ml-2">
                <.timestamp datetime={@plan.inserted_at} />
              </span>
            </div>
            <div>
              <span class="text-slate-500">Updated:</span>
              <span class="ml-2">
                <.timestamp datetime={@plan.updated_at} />
              </span>
            </div>
          </div>
          
    <!-- Tags -->
          <div :if={@plan.tags && @plan.tags != []} class="mb-6">
            <span class="text-sm text-slate-500 mr-2">Tags:</span>
            <.tag_badges tags={@plan.tags} />
          </div>
          
    <!-- Body Content -->
          <div class="prose prose-slate max-w-none">
            <.markdown content={@plan.body} />
          </div>
        </div>
      </div>
      
    <!-- Version History -->
      <div :if={@versions != []} class="mt-8">
        <h3 class="text-lg font-semibold text-slate-900 mb-4">Other Versions</h3>
        <div class="bg-white rounded-lg shadow-sm border border-slate-200 divide-y divide-slate-200">
          <div :for={version <- @versions} class="p-4 hover:bg-slate-50 transition-colors">
            <div class="flex items-center justify-between">
              <div class="flex items-center gap-3">
                <span class="font-mono text-sm bg-slate-100 px-1.5 py-0.5 rounded">
                  {version.version}
                </span>
                <span class="text-sm text-slate-600">
                  <.timestamp datetime={version.inserted_at} />
                </span>
                <div :if={version.tags && version.tags != []}>
                  <.tag_badges tags={version.tags} />
                </div>
              </div>
              <.link_button
                navigate={~p"/pop_stash/plans/#{version.id}"}
                variant="ghost"
                size="sm"
              >
                View
              </.link_button>
            </div>
            <div class="mt-2 text-sm text-slate-600">
              <.markdown_preview content={version.body} max_length={200} />
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
