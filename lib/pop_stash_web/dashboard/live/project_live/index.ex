defmodule PopStashWeb.Dashboard.ProjectLive.Index do
  @moduledoc """
  LiveView for listing and managing projects.
  """

  use PopStashWeb.Dashboard, :live_view

  alias PopStash.Memory
  alias PopStash.Projects

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Projects")
      |> assign(:current_path, "/pop_stash/projects")
      |> assign(:search_query, "")
      |> load_projects()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:show_modal, false)
    |> assign(:project, nil)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:show_modal, true)
    |> assign(:project, %Projects.Project{})
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    socket =
      socket
      |> assign(:search_query, query)
      |> load_projects()

    {:noreply, socket}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    case Projects.delete(id) do
      {:ok, _project} ->
        {:noreply,
         socket
         |> put_flash(:info, "Project deleted successfully")
         |> load_projects()}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to delete project")}
    end
  end

  def handle_event("close_modal", _, socket) do
    {:noreply, push_patch(socket, to: ~p"/pop_stash/projects")}
  end

  defp load_projects(socket) do
    projects =
      Projects.list()
      |> filter_projects_by_search(socket.assigns.search_query)
      |> Enum.map(&enrich_project_with_stats/1)

    assign(socket, :projects, projects)
  end

  defp filter_projects_by_search(projects, ""), do: projects

  defp filter_projects_by_search(projects, query) do
    query = String.downcase(query)
    Enum.filter(projects, &project_matches_query?(&1, query))
  end

  defp project_matches_query?(project, query) do
    matches_field?(project.name, query) ||
      matches_field?(project.description, query) ||
      matches_tags?(project.tags, query)
  end

  defp matches_field?(nil, _query), do: false
  defp matches_field?(value, query), do: String.contains?(String.downcase(value), query)

  defp matches_tags?(nil, _query), do: false
  defp matches_tags?(tags, query), do: Enum.any?(tags, &matches_field?(&1, query))

  defp enrich_project_with_stats(project) do
    contexts_count = length(Memory.list_contexts(project.id))
    insights_count = length(Memory.list_insights(project.id))
    decisions_count = length(Memory.list_decisions(project.id))

    Map.merge(project, %{
      contexts_count: contexts_count,
      insights_count: insights_count,
      decisions_count: decisions_count
    })
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.page_header title="Projects" subtitle="Manage your PopStash projects">
        <:actions>
          <.link_button navigate={~p"/pop_stash/projects/new"} variant="primary">
            <.icon name="hero-plus" class="size-4" /> New Project
          </.link_button>
        </:actions>
      </.page_header>
      
    <!-- Search -->
      <div class="mb-6">
        <form phx-change="search">
          <div class="relative">
            <.icon
              name="hero-magnifying-glass"
              class="absolute left-3 top-1/2 -translate-y-1/2 size-4 text-slate-400"
            />
            <input
              type="text"
              name="query"
              value={@search_query}
              placeholder="Search projects..."
              class="w-full pl-10 pr-3 py-2 text-sm bg-white border border-slate-200 rounded focus:outline-none focus:ring-2 focus:ring-violet-500/20 focus:border-violet-500"
              phx-debounce="300"
            />
          </div>
        </form>
      </div>
      
    <!-- Project List -->
      <%= if @projects == [] do %>
        <.empty_state
          title="No projects found"
          description={
            if @search_query != "",
              do: "Try adjusting your search",
              else: "Create your first project to get started"
          }
        >
          <:action>
            <.link_button
              :if={@search_query == ""}
              navigate={~p"/pop_stash/projects/new"}
              variant="primary"
            >
              <.icon name="hero-plus" class="size-4" /> New Project
            </.link_button>
          </:action>
        </.empty_state>
      <% else %>
        <.data_table id="projects-table" rows={@projects} row_id={&"project-#{&1.id}"}>
          <:col :let={project} label="Name" class="font-medium">
            <.link navigate={~p"/pop_stash/projects/#{project.id}"} class="hover:text-violet-600">
              {project.name}
            </.link>
          </:col>
          <:col :let={project} label="Description">
            <div class="text-sm text-slate-600 max-w-md truncate">
              {project.description || "—"}
            </div>
          </:col>
          <:col :let={project} label="Stats">
            <div class="flex gap-3 text-xs text-slate-600">
              <span title="Stashes">
                {project.stashes_count} <.icon name="hero-archive-box" class="size-3 inline" />
              </span>
              <span title="Insights">
                {project.insights_count} <.icon name="hero-light-bulb" class="size-3 inline" />
              </span>
              <span title="Decisions">
                {project.decisions_count} <.icon name="hero-check-badge" class="size-3 inline" />
              </span>
            </div>
          </:col>
          <:col :let={project} label="Tags">
            <.tag_badges tags={project.tags || []} />
          </:col>
          <:col :let={project} label="Created" mono>
            <.timestamp datetime={project.inserted_at} />
          </:col>
          <:col :let={project} label="Actions" class="text-right">
            <div class="flex items-center justify-end gap-2">
              <.link_button navigate={~p"/pop_stash/projects/#{project.id}"} variant="ghost" size="sm">
                View
              </.link_button>
              <.button
                variant="ghost"
                size="sm"
                phx-click="delete"
                phx-value-id={project.id}
                data-confirm="Are you sure you want to delete this project? This will delete all associated stashes, insights, and decisions."
              >
                <.icon name="hero-trash" class="size-4 text-red-500" />
              </.button>
            </div>
          </:col>
        </.data_table>
      <% end %>
      
    <!-- New Project Modal -->
      <.modal
        :if={@show_modal}
        id="project-modal"
        show={@show_modal}
        on_cancel={JS.push("close_modal")}
        title="New Project"
      >
        <.live_component
          module={PopStashWeb.Dashboard.ProjectLive.FormComponent}
          id={:new}
          project={@project}
          action={:new}
          return_to={~p"/pop_stash/projects"}
        />
      </.modal>
    </div>
    """
  end
end
