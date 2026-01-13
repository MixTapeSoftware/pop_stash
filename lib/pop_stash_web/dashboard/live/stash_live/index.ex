defmodule PopStashWeb.Dashboard.StashLive.Index do
  @moduledoc """
  LiveView for listing and managing stashes.
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
      |> assign(:page_title, "Stashes")
      |> assign(:current_path, "/pop_stash/stashes")
      |> assign(:projects, projects)
      |> assign(:selected_project_id, nil)
      |> assign(:search_query, "")
      |> load_stashes()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:show_modal, false)
    |> assign(:stash, nil)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:show_modal, true)
    |> assign(:stash, %Memory.Stash{})
  end

  @impl true
  def handle_event("select_project", %{"project_id" => project_id}, socket) do
    project_id = if project_id == "", do: nil, else: project_id

    socket =
      socket
      |> assign(:selected_project_id, project_id)
      |> load_stashes()

    {:noreply, socket}
  end

  def handle_event("search", %{"query" => query}, socket) do
    socket =
      socket
      |> assign(:search_query, query)
      |> load_stashes()

    {:noreply, socket}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    case Memory.delete_stash(id) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Stash deleted successfully")
         |> load_stashes()}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to delete stash")}
    end
  end

  def handle_event("close_modal", _, socket) do
    {:noreply, push_patch(socket, to: ~p"/pop_stash/stashes")}
  end

  @impl true
  def handle_info({:stash_created, _stash}, socket) do
    {:noreply, load_stashes(socket)}
  end

  def handle_info({:stash_updated, _stash}, socket) do
    {:noreply, load_stashes(socket)}
  end

  def handle_info({:stash_deleted, _id}, socket) do
    {:noreply, load_stashes(socket)}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  defp load_stashes(socket) do
    stashes =
      socket
      |> fetch_stashes()
      |> filter_stashes_by_search(socket.assigns.search_query)

    assign(socket, :stashes, stashes)
  end

  defp fetch_stashes(socket) do
    case socket.assigns.selected_project_id do
      nil ->
        socket.assigns.projects
        |> Enum.flat_map(&Memory.list_stashes(&1.id))
        |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})

      project_id ->
        Memory.list_stashes(project_id)
    end
  end

  defp filter_stashes_by_search(stashes, ""), do: stashes

  defp filter_stashes_by_search(stashes, query) do
    query = String.downcase(query)
    Enum.filter(stashes, &stash_matches_query?(&1, query))
  end

  defp stash_matches_query?(stash, query) do
    matches_field?(stash.name, query) ||
      matches_field?(stash.summary, query) ||
      matches_tags?(stash.tags, query)
  end

  defp matches_field?(nil, _query), do: false
  defp matches_field?(value, query), do: String.contains?(String.downcase(value), query)

  defp matches_tags?(nil, _query), do: false
  defp matches_tags?(tags, query), do: Enum.any?(tags, &matches_field?(&1, query))

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.page_header title="Stashes" subtitle="Context snapshots for AI sessions">
        <:actions>
          <.link_button navigate={~p"/pop_stash/stashes/new"} variant="primary">
            <.icon name="hero-plus" class="size-4" /> New Stash
          </.link_button>
        </:actions>
      </.page_header>
      
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
              placeholder="Search stashes..."
              class="w-full pl-10 pr-3 py-2 text-sm bg-white border border-slate-200 rounded focus:outline-none focus:ring-2 focus:ring-violet-500/20 focus:border-violet-500"
              phx-debounce="300"
            />
          </div>
        </form>
      </div>
      
    <!-- Stash List -->
      <%= if @stashes == [] do %>
        <.empty_state
          title="No stashes found"
          description={
            if @search_query != "",
              do: "Try adjusting your search",
              else: "Create your first stash to get started"
          }
        >
          <:action>
            <.link_button
              :if={@search_query == ""}
              navigate={~p"/pop_stash/stashes/new"}
              variant="primary"
            >
              <.icon name="hero-plus" class="size-4" /> New Stash
            </.link_button>
          </:action>
        </.empty_state>
      <% else %>
        <.data_table id="stashes-table" rows={@stashes} row_id={&"stash-#{&1.id}"}>
          <:col :let={stash} label="Name" class="font-medium">
            <.link navigate={~p"/pop_stash/stashes/#{stash.id}"} class="hover:text-violet-600">
              {stash.name}
            </.link>
          </:col>
          <:col :let={stash} label="Summary">
            <.markdown_preview content={stash.summary} max_length={100} />
          </:col>
          <:col :let={stash} label="Tags">
            <.tag_badges tags={stash.tags || []} />
          </:col>
          <:col :let={stash} label="Created" mono>
            <.timestamp datetime={stash.inserted_at} />
          </:col>
          <:col :let={stash} label="Actions" class="text-right">
            <div class="flex items-center justify-end gap-2">
              <.link_button navigate={~p"/pop_stash/stashes/#{stash.id}"} variant="ghost" size="sm">
                View
              </.link_button>
              <.button
                variant="ghost"
                size="sm"
                phx-click="delete"
                phx-value-id={stash.id}
                data-confirm="Are you sure you want to delete this stash?"
              >
                <.icon name="hero-trash" class="size-4 text-red-500" />
              </.button>
            </div>
          </:col>
        </.data_table>
      <% end %>
      
    <!-- New Stash Modal -->
      <.modal
        :if={@show_modal}
        id="stash-modal"
        show={@show_modal}
        on_cancel={JS.push("close_modal")}
        title="New Stash"
      >
        <.live_component
          module={PopStashWeb.Dashboard.StashLive.FormComponent}
          id={:new}
          stash={@stash}
          projects={@projects}
          action={:new}
          return_to={~p"/pop_stash/stashes"}
        />
      </.modal>
    </div>
    """
  end
end
