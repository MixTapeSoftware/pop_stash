defmodule PopStashWeb.Dashboard.SearchLive.Index do
  @moduledoc """
  LiveView for listing search logs.
  """

  use PopStashWeb.Dashboard, :live_view

  alias PopStash.Memory
  alias PopStash.Projects

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(PopStash.PubSub, "memory:events")
    end

    projects = Projects.list()

    socket =
      socket
      |> assign(:page_title, "Searches")
      |> assign(:current_path, "/pop_stash/searches")
      |> assign(:projects, projects)
      |> assign(:selected_project_id, nil)
      |> assign(:search_query, "")
      |> load_searches()

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
      |> load_searches()

    {:noreply, socket}
  end

  def handle_event("search", %{"query" => query}, socket) do
    socket =
      socket
      |> assign(:search_query, query)
      |> load_searches()

    {:noreply, socket}
  end

  @impl true
  def handle_info({:search_logged, _search_log}, socket) do
    {:noreply, load_searches(socket)}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  defp load_searches(socket) do
    searches =
      socket
      |> fetch_searches()
      |> filter_searches_by_query(socket.assigns.search_query)

    assign(socket, :searches, searches)
  end

  defp fetch_searches(socket) do
    case socket.assigns.selected_project_id do
      nil ->
        Memory.list_all_search_logs(limit: 100)

      project_id ->
        Memory.list_search_logs(project_id, limit: 100)
    end
  end

  defp filter_searches_by_query(searches, ""), do: searches

  defp filter_searches_by_query(searches, query) do
    query = String.downcase(query)

    Enum.filter(searches, fn search ->
      matches_field?(search.query, query) ||
        matches_field?(search.collection, query) ||
        matches_field?(search.tool, query)
    end)
  end

  defp matches_field?(nil, _query), do: false
  defp matches_field?(value, query), do: String.contains?(String.downcase(value), query)

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.page_header title="Searches" subtitle="Search query history and analytics" />
      
    <!-- Filters -->
      <div class="flex flex-col sm:flex-row gap-3 mb-6">
        <form phx-change="select_project" class="flex-shrink-0">
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

        <form phx-change="search" class="flex-1">
          <div class="relative">
            <.icon
              name="hero-magnifying-glass"
              class="absolute left-3 top-1/2 -translate-y-1/2 size-4 text-slate-400"
            />
            <input
              type="text"
              name="query"
              value={@search_query}
              placeholder="Filter searches..."
              class="w-full pl-10 pr-3 py-2 text-sm bg-white border border-slate-200 rounded focus:outline-none focus:ring-2 focus:ring-violet-500/20 focus:border-violet-500"
              phx-debounce="300"
            />
          </div>
        </form>
      </div>
      
    <!-- Search List -->
      <%= if @searches == [] do %>
        <.empty_state
          title="No searches found"
          description={
            if @search_query != "",
              do: "Try adjusting your filter",
              else: "Search logs will appear here as agents query the system"
          }
        />
      <% else %>
        <.data_table id="searches-table" rows={@searches} row_id={&"search-#{&1.id}"}>
          <:col :let={search} label="Query" class="font-medium max-w-md">
            <div class="truncate" title={search.query}>{search.query}</div>
          </:col>
          <:col :let={search} label="Collection">
            <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-mono bg-slate-100 text-slate-600 border border-slate-200">
              {search.collection}
            </span>
          </:col>
          <:col :let={search} label="Tool">
            <span :if={search.tool} class="text-xs text-slate-500">{search.tool}</span>
            <span :if={!search.tool} class="text-xs text-slate-400">-</span>
          </:col>
          <:col :let={search} label="Results" mono>
            <span class={[
              "inline-flex items-center gap-1",
              search.found && "text-green-600",
              !search.found && "text-slate-400"
            ]}>
              {search.result_count || 0}
              <.icon
                :if={search.found}
                name="hero-check-circle"
                class="size-3.5"
              />
            </span>
          </:col>
          <:col :let={search} label="Duration" mono>
            <span :if={search.duration_ms} class="text-slate-500">{search.duration_ms}ms</span>
            <span :if={!search.duration_ms} class="text-slate-400">-</span>
          </:col>
          <:col :let={search} label="Project">
            <span :if={search.project} class="text-xs text-slate-500">
              {search.project.name}
            </span>
          </:col>
          <:col :let={search} label="Time" mono>
            <.timestamp datetime={search.inserted_at} />
          </:col>
        </.data_table>
      <% end %>
    </div>
    """
  end
end
