defmodule PopStashWeb.Dashboard.HomeLive do
  @moduledoc """
  Dashboard home/overview page showing memory statistics.
  """

  use PopStashWeb.Dashboard, :live_view

  alias PopStash.Memory
  alias PopStash.Projects

  @impl true
  def mount(_params, _session, socket) do
    projects = Projects.list()

    socket =
      socket
      |> assign(:page_title, "Overview")
      |> assign(:current_path, "/pop_stash")
      |> assign(:projects, projects)
      |> assign(:selected_project_id, nil)
      |> load_stats()

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("select_project", %{"project_id" => project_id}, socket) do
    project_id = if project_id == "", do: nil, else: project_id

    socket =
      socket
      |> assign(:selected_project_id, project_id)
      |> load_stats()

    {:noreply, socket}
  end

  defp load_stats(socket) do
    case socket.assigns.selected_project_id do
      nil ->
        # Show aggregate stats across all projects
        projects = socket.assigns.projects

        total_stashes =
          projects
          |> Enum.map(& &1.id)
          |> Enum.map(&length(Memory.list_stashes(&1)))
          |> Enum.sum()

        total_insights =
          projects
          |> Enum.map(& &1.id)
          |> Enum.map(&length(Memory.list_insights(&1)))
          |> Enum.sum()

        total_decisions =
          projects
          |> Enum.map(& &1.id)
          |> Enum.map(&length(Memory.list_decisions(&1)))
          |> Enum.sum()

        stats = [
          %{title: "Projects", value: length(projects), desc: "Total projects"},
          %{title: "Stashes", value: total_stashes, desc: "Across all projects"},
          %{title: "Insights", value: total_insights, desc: "Across all projects"},
          %{title: "Decisions", value: total_decisions, desc: "Across all projects"}
        ]

        assign(socket, :stats, stats)

      project_id ->
        stashes = Memory.list_stashes(project_id)
        insights = Memory.list_insights(project_id)
        decisions = Memory.list_decisions(project_id)

        stats = [
          %{title: "Stashes", value: length(stashes)},
          %{title: "Insights", value: length(insights)},
          %{title: "Decisions", value: length(decisions)}
        ]

        assign(socket, :stats, stats)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.page_header title="Overview" subtitle="PopStash memory dashboard">
        <:actions>
          <form phx-change="select_project">
            <select
              name="project_id"
              class="px-3 py-2 text-sm bg-white border border-slate-200 rounded focus:outline-none focus:ring-2 focus:ring-violet-500/20 focus:border-violet-500"
            >
              <option value="">All Projects</option>
              <option
                :for={project <- @projects}
                value={project.id}
                selected={@selected_project_id == project.id}
              >
                {project.name}
              </option>
            </select>
          </form>
        </:actions>
      </.page_header>

      <.stats_row stats={@stats} />

      <div class="mt-8 grid grid-cols-1 lg:grid-cols-2 gap-6">
        <!-- Quick Actions -->
        <.card>
          <.section_header title="Quick Actions" />
          <div class="space-y-2">
            <.link_button
              navigate={~p"/pop_stash/stashes/new"}
              variant="secondary"
              class="w-full justify-start"
            >
              <.icon name="hero-plus" class="size-4" /> New Stash
            </.link_button>
            <.link_button
              navigate={~p"/pop_stash/insights/new"}
              variant="secondary"
              class="w-full justify-start"
            >
              <.icon name="hero-plus" class="size-4" /> New Insight
            </.link_button>
            <.link_button
              navigate={~p"/pop_stash/decisions/new"}
              variant="secondary"
              class="w-full justify-start"
            >
              <.icon name="hero-plus" class="size-4" /> New Decision
            </.link_button>
          </div>
        </.card>
        
    <!-- Recent Activity -->
        <.card>
          <.section_header title="Navigation" />
          <div class="space-y-2">
            <.link
              navigate={~p"/pop_stash/stashes"}
              class="flex items-center gap-3 p-3 rounded hover:bg-slate-50 transition-colors"
            >
              <.icon name="hero-archive-box" class="size-5 text-slate-400" />
              <div>
                <div class="text-sm font-medium text-slate-900">Stashes</div>
                <div class="text-xs text-slate-500">Context snapshots for AI sessions</div>
              </div>
            </.link>
            <.link
              navigate={~p"/pop_stash/insights"}
              class="flex items-center gap-3 p-3 rounded hover:bg-slate-50 transition-colors"
            >
              <.icon name="hero-light-bulb" class="size-5 text-slate-400" />
              <div>
                <div class="text-sm font-medium text-slate-900">Insights</div>
                <div class="text-xs text-slate-500">Learned knowledge and patterns</div>
              </div>
            </.link>
            <.link
              navigate={~p"/pop_stash/decisions"}
              class="flex items-center gap-3 p-3 rounded hover:bg-slate-50 transition-colors"
            >
              <.icon name="hero-check-badge" class="size-5 text-slate-400" />
              <div>
                <div class="text-sm font-medium text-slate-900">Decisions</div>
                <div class="text-xs text-slate-500">Immutable decision records</div>
              </div>
            </.link>
          </div>
        </.card>
      </div>
    </div>
    """
  end
end
