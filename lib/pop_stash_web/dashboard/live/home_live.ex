defmodule PopStashWeb.Dashboard.HomeLive do
  @moduledoc """
  Dashboard home/overview page showing memory statistics and recent activity.
  """

  use PopStashWeb.Dashboard, :live_view

  alias PopStash.Activity
  alias PopStash.Memory
  alias PopStash.Projects

  @impl true
  def mount(_params, _session, socket) do
    # Subscribe to real-time updates
    if connected?(socket) do
      Phoenix.PubSub.subscribe(PopStash.PubSub, "memory:events")
    end

    projects = Projects.list()

    socket =
      socket
      |> assign(:page_title, "Overview")
      |> assign(:current_path, "/pop_stash")
      |> assign(:projects, projects)
      |> assign(:selected_project_id, nil)
      |> assign(:activity_items, [])
      |> assign(:recent_searches, [])
      |> load_stats()
      |> load_activity()
      |> load_recent_searches()

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
      |> load_activity()
      |> load_recent_searches()

    {:noreply, socket}
  end

  # Real-time event handlers
  @impl true
  def handle_info({:stash_created, stash}, socket) do
    item = Activity.to_item(stash)
    {:noreply, prepend_activity_item(socket, item)}
  end

  def handle_info({:stash_updated, _stash}, socket) do
    # Optionally refresh the activity feed on updates
    {:noreply, socket}
  end

  def handle_info({:decision_created, decision}, socket) do
    item = Activity.to_item(decision)
    {:noreply, prepend_activity_item(socket, item)}
  end

  def handle_info({:insight_created, insight}, socket) do
    item = Activity.to_item(insight)
    {:noreply, prepend_activity_item(socket, item)}
  end

  def handle_info({:insight_updated, _insight}, socket) do
    # Optionally refresh the activity feed on updates
    {:noreply, socket}
  end

  def handle_info({:search_logged, search_log}, socket) do
    item = Activity.to_item(search_log)

    socket =
      socket
      |> prepend_activity_item(item)
      |> load_recent_searches()

    {:noreply, socket}
  end

  def handle_info({:stash_deleted, id}, socket) do
    {:noreply, remove_activity_item(socket, id)}
  end

  def handle_info({:decision_deleted, id}, socket) do
    {:noreply, remove_activity_item(socket, id)}
  end

  def handle_info({:insight_deleted, id}, socket) do
    {:noreply, remove_activity_item(socket, id)}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  defp load_activity(socket) do
    items =
      Activity.list_recent(
        limit: 20,
        project_id: socket.assigns.selected_project_id
      )

    assign(socket, :activity_items, items)
  end

  defp load_recent_searches(socket) do
    searches =
      case socket.assigns.selected_project_id do
        nil -> []
        project_id -> Memory.list_search_logs(project_id, limit: 5)
      end

    assign(socket, :recent_searches, searches)
  end

  defp prepend_activity_item(socket, item) do
    # Check if item matches current project filter
    if matches_project_filter?(socket, item) do
      items = [item | socket.assigns.activity_items]
      items = Enum.take(items, 20)
      assign(socket, :activity_items, items)
    else
      socket
    end
  end

  defp remove_activity_item(socket, item_id) do
    items = Enum.reject(socket.assigns.activity_items, &(&1.id == item_id))
    assign(socket, :activity_items, items)
  end

  defp matches_project_filter?(socket, item) do
    case socket.assigns.selected_project_id do
      nil -> true
      project_id -> item.project_id == project_id
    end
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

        total_searches =
          projects
          |> Enum.map(& &1.id)
          |> Enum.map(&Memory.count_searches(&1))
          |> Enum.sum()

        stats = [
          %{
            title: "Projects",
            value: length(projects),
            desc: "Total projects",
            link: ~p"/pop_stash/projects"
          },
          %{
            title: "Stashes",
            value: total_stashes,
            desc: "Across all projects",
            link: ~p"/pop_stash/stashes"
          },
          %{
            title: "Insights",
            value: total_insights,
            desc: "Across all projects",
            link: ~p"/pop_stash/insights"
          },
          %{
            title: "Decisions",
            value: total_decisions,
            desc: "Across all projects",
            link: ~p"/pop_stash/decisions"
          },
          %{
            title: "Searches",
            value: total_searches,
            desc: "Total queries",
            link: nil
          }
        ]

        assign(socket, :stats, stats)

      project_id ->
        stashes = Memory.list_stashes(project_id)
        insights = Memory.list_insights(project_id)
        decisions = Memory.list_decisions(project_id)
        searches_count = Memory.count_searches(project_id)

        stats = [
          %{title: "Stashes", value: length(stashes), link: ~p"/pop_stash/stashes"},
          %{title: "Insights", value: length(insights), link: ~p"/pop_stash/insights"},
          %{title: "Decisions", value: length(decisions), link: ~p"/pop_stash/decisions"},
          %{title: "Searches", value: searches_count, link: nil}
        ]

        assign(socket, :stats, stats)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.page_header title="Dashboard" subtitle="All the things">
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

      <div class="mt-8 grid grid-cols-1 lg:grid-cols-3 gap-6">
        <!-- Activity Feed (spans 2 columns) -->
        <div class="lg:col-span-2">
          <.card>
            <.section_header title="Recent Activity">
              <:actions>
                <span class="text-xs text-slate-400">Live updates enabled</span>
                <span class="relative flex h-2 w-2 ml-2">
                  <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-green-400 opacity-75">
                  </span>
                  <span class="relative inline-flex rounded-full h-2 w-2 bg-green-500"></span>
                </span>
              </:actions>
            </.section_header>

            <.live_component
              module={PopStashWeb.Dashboard.ActivityFeedComponent}
              id="activity-feed"
              items={@activity_items}
              limit={20}
              project_id={@selected_project_id}
              show_project={is_nil(@selected_project_id)}
            />
          </.card>
        </div>
        
    <!-- Sidebar -->
        <div class="space-y-6">
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
          
    <!-- Recent Searches -->
          <.card>
            <.section_header title="Recent Searches" />
            <div class="space-y-1 max-h-64 overflow-y-auto">
              <%= if @recent_searches == [] && @selected_project_id do %>
                <div class="text-sm text-slate-400 text-center py-4">
                  No recent searches
                </div>
              <% else %>
                <%= if @selected_project_id do %>
                  <%= for search <- @recent_searches do %>
                    <div class="flex items-start gap-2 p-2 rounded hover:bg-slate-50 transition-colors">
                      <.icon
                        name="hero-magnifying-glass"
                        class="size-4 text-purple-400 mt-0.5 flex-shrink-0"
                      />
                      <div class="min-w-0 flex-1">
                        <div class="text-sm text-slate-900 truncate" title={search.query}>
                          {search.query}
                        </div>
                        <div class="text-xs text-slate-500">
                          {search.collection} • {if search.result_count,
                            do: "#{search.result_count} results",
                            else: "0 results"}
                        </div>
                      </div>
                    </div>
                  <% end %>
                <% else %>
                  <div class="text-sm text-slate-400 text-center py-4">
                    Select a project to view searches
                  </div>
                <% end %>
              <% end %>
            </div>
          </.card>
          
    <!-- Navigation -->
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
    </div>
    """
  end
end
