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
      |> load_stats()
      |> load_activity()

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

  def handle_info({:plan_created, plan}, socket) do
    item = Activity.to_item(plan)
    {:noreply, prepend_activity_item(socket, item)}
  end

  def handle_info({:plan_updated, _plan}, socket) do
    # Optionally refresh the activity feed on updates
    {:noreply, socket}
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

    {:noreply, prepend_activity_item(socket, item)}
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

  def handle_info({:plan_deleted, id}, socket) do
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
          |> Enum.map(&length(Memory.list_contexts(&1)))
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

        total_plans =
          projects
          |> Enum.map(& &1.id)
          |> Enum.map(&length(Memory.list_plans(&1)))
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
            icon: "hero-folder",
            link: ~p"/pop_stash/projects"
          },
          %{
            title: "Contexts",
            value: total_stashes,
            desc: "Across all projects",
            icon: "hero-archive-box",
            link: ~p"/pop_stash/contexts"
          },
          %{
            title: "Insights",
            value: total_insights,
            desc: "Across all projects",
            icon: "hero-light-bulb",
            link: ~p"/pop_stash/insights"
          },
          %{
            title: "Decisions",
            value: total_decisions,
            desc: "Across all projects",
            icon: "hero-check-badge",
            link: ~p"/pop_stash/decisions"
          },
          %{
            title: "Plans",
            value: total_plans,
            desc: "Across all projects",
            icon: "hero-map",
            link: ~p"/pop_stash/plans"
          },
          %{
            title: "Searches",
            value: total_searches,
            desc: "Total queries",
            icon: "hero-magnifying-glass",
            link: ~p"/pop_stash/searches"
          }
        ]

        assign(socket, :stats, stats)

      project_id ->
        contexts = Memory.list_contexts(project_id)
        insights = Memory.list_insights(project_id)
        decisions = Memory.list_decisions(project_id)
        plans = Memory.list_plans(project_id)
        searches_count = Memory.count_searches(project_id)

        stats = [
          %{
            title: "Contexts",
            value: length(contexts),
            icon: "hero-archive-box",
            link: ~p"/pop_stash/contexts"
          },
          %{
            title: "Insights",
            value: length(insights),
            icon: "hero-light-bulb",
            link: ~p"/pop_stash/insights"
          },
          %{
            title: "Decisions",
            value: length(decisions),
            icon: "hero-check-badge",
            link: ~p"/pop_stash/decisions"
          },
          %{title: "Plans", value: length(plans), icon: "hero-map", link: ~p"/pop_stash/plans"},
          %{
            title: "Searches",
            value: searches_count,
            icon: "hero-magnifying-glass",
            link: ~p"/pop_stash/searches"
          }
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
                navigate={~p"/pop_stash/contexts/new"}
                variant="secondary"
                class="w-full justify-start"
              >
                <.icon name="hero-plus" class="size-4" /> New Context
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
              <.link_button
                navigate={~p"/pop_stash/plans/new"}
                variant="secondary"
                class="w-full justify-start"
              >
                <.icon name="hero-plus" class="size-4" /> New Plan
              </.link_button>
            </div>
          </.card>
        </div>
      </div>
    </div>
    """
  end
end
