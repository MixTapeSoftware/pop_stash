defmodule PopStashWeb.Dashboard.ProjectLive.Index do
  @moduledoc """
  LiveView for listing and managing projects.
  """

  use PopStashWeb.Dashboard, :live_view

  alias PopStash.Memory
  alias PopStash.Plans
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

    stats_summary = calculate_stats_summary(projects)

    socket
    |> assign(:projects, projects)
    |> assign(:stats_summary, stats_summary)
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
    plans_count = length(Plans.list_plans(project.id))

    Map.merge(project, %{
      contexts_count: contexts_count,
      insights_count: insights_count,
      decisions_count: decisions_count,
      plans_count: plans_count
    })
  end

  defp calculate_stats_summary(projects) do
    %{
      total_projects: length(projects),
      total_contexts: Enum.sum(Enum.map(projects, & &1.contexts_count)),
      total_insights: Enum.sum(Enum.map(projects, & &1.insights_count)),
      total_decisions: Enum.sum(Enum.map(projects, & &1.decisions_count)),
      total_plans: Enum.sum(Enum.map(projects, & &1.plans_count)),
      active_projects:
        Enum.count(projects, fn p ->
          p.contexts_count > 0 || p.insights_count > 0 || p.decisions_count > 0 ||
            p.plans_count > 0
        end)
    }
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
      
    <!-- Stats Summary -->
      <%= if @projects != [] do %>
        <div class="mb-6 grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-4">
          <div class="bg-white rounded-lg border border-slate-200 p-4">
            <div class="flex items-center gap-2 text-slate-500 text-xs font-medium mb-1">
              <.icon name="hero-folder" class="size-4" /> Projects
            </div>
            <div class="text-2xl font-bold text-slate-900">
              {@stats_summary.total_projects}
            </div>
            <div class="text-xs text-slate-500 mt-1">
              {@stats_summary.active_projects} active
            </div>
          </div>

          <div class="bg-white rounded-lg border border-slate-200 p-4">
            <div class="flex items-center gap-2 text-blue-600 text-xs font-medium mb-1">
              <.icon name="hero-archive-box" class="size-4" /> Contexts
            </div>
            <div class="text-2xl font-bold text-slate-900">
              {@stats_summary.total_contexts}
            </div>
            <div class="text-xs text-slate-500 mt-1">
              across all projects
            </div>
          </div>

          <div class="bg-white rounded-lg border border-slate-200 p-4">
            <div class="flex items-center gap-2 text-amber-600 text-xs font-medium mb-1">
              <.icon name="hero-light-bulb" class="size-4" /> Insights
            </div>
            <div class="text-2xl font-bold text-slate-900">
              {@stats_summary.total_insights}
            </div>
            <div class="text-xs text-slate-500 mt-1">
              across all projects
            </div>
          </div>

          <div class="bg-white rounded-lg border border-slate-200 p-4">
            <div class="flex items-center gap-2 text-green-600 text-xs font-medium mb-1">
              <.icon name="hero-check-badge" class="size-4" /> Decisions
            </div>
            <div class="text-2xl font-bold text-slate-900">
              {@stats_summary.total_decisions}
            </div>
            <div class="text-xs text-slate-500 mt-1">
              across all projects
            </div>
          </div>

          <div class="bg-white rounded-lg border border-slate-200 p-4">
            <div class="flex items-center gap-2 text-purple-600 text-xs font-medium mb-1">
              <.icon name="hero-map" class="size-4" /> Plans
            </div>
            <div class="text-2xl font-bold text-slate-900">
              {@stats_summary.total_plans}
            </div>
            <div class="text-xs text-slate-500 mt-1">
              across all projects
            </div>
          </div>

          <div class="bg-gradient-to-br from-violet-50 to-purple-50 rounded-lg border border-violet-200 p-4">
            <div class="flex items-center gap-2 text-violet-600 text-xs font-medium mb-1">
              <.icon name="hero-chart-bar" class="size-4" /> Total Items
            </div>
            <div class="text-2xl font-bold text-violet-900">
              {@stats_summary.total_contexts + @stats_summary.total_insights +
                @stats_summary.total_decisions + @stats_summary.total_plans}
            </div>
            <div class="text-xs text-violet-600 mt-1">
              knowledge items
            </div>
          </div>
        </div>
      <% end %>
      
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
          <:col :let={project} label="Contexts" class="text-center">
            <span class={[
              "inline-flex items-center gap-1 px-2 py-1 rounded text-xs font-medium",
              if(project.contexts_count > 0,
                do: "bg-blue-50 text-blue-700",
                else: "bg-slate-50 text-slate-400"
              )
            ]}>
              <.icon name="hero-archive-box" class="size-3" />
              {project.contexts_count}
            </span>
          </:col>
          <:col :let={project} label="Insights" class="text-center">
            <span class={[
              "inline-flex items-center gap-1 px-2 py-1 rounded text-xs font-medium",
              if(project.insights_count > 0,
                do: "bg-amber-50 text-amber-700",
                else: "bg-slate-50 text-slate-400"
              )
            ]}>
              <.icon name="hero-light-bulb" class="size-3" />
              {project.insights_count}
            </span>
          </:col>
          <:col :let={project} label="Decisions" class="text-center">
            <span class={[
              "inline-flex items-center gap-1 px-2 py-1 rounded text-xs font-medium",
              if(project.decisions_count > 0,
                do: "bg-green-50 text-green-700",
                else: "bg-slate-50 text-slate-400"
              )
            ]}>
              <.icon name="hero-check-badge" class="size-3" />
              {project.decisions_count}
            </span>
          </:col>
          <:col :let={project} label="Plans" class="text-center">
            <span class={[
              "inline-flex items-center gap-1 px-2 py-1 rounded text-xs font-medium",
              if(project.plans_count > 0,
                do: "bg-purple-50 text-purple-700",
                else: "bg-slate-50 text-slate-400"
              )
            ]}>
              <.icon name="hero-map" class="size-3" />
              {project.plans_count}
            </span>
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
