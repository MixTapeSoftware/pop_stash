defmodule PopStashWeb.Dashboard.ContextLive.Index do
  @moduledoc """
  LiveView for listing and managing contexts.
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
      |> assign(:page_title, "Contexts")
      |> assign(:current_path, "/pop_stash/contexts")
      |> assign(:projects, projects)
      |> assign(:selected_project_id, nil)
      |> assign(:search_query, "")
      |> load_contexts()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:show_modal, false)
    |> assign(:context, nil)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:show_modal, true)
    |> assign(:context, %Memory.Context{})
  end

  @impl true
  def handle_event("select_project", %{"project_id" => project_id}, socket) do
    project_id = if project_id == "", do: nil, else: project_id

    socket =
      socket
      |> assign(:selected_project_id, project_id)
      |> load_contexts()

    {:noreply, socket}
  end

  def handle_event("search", %{"query" => query}, socket) do
    socket =
      socket
      |> assign(:search_query, query)
      |> load_contexts()

    {:noreply, socket}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    case Memory.delete_context(id) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Context deleted successfully")
         |> load_contexts()}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to delete context")}
    end
  end

  def handle_event("close_modal", _, socket) do
    {:noreply, push_patch(socket, to: ~p"/pop_stash/contexts")}
  end

  @impl true
  def handle_info({:context_created, _context}, socket) do
    {:noreply, load_contexts(socket)}
  end

  def handle_info({:context_updated, _context}, socket) do
    {:noreply, load_contexts(socket)}
  end

  def handle_info({:context_deleted, _id}, socket) do
    {:noreply, load_contexts(socket)}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  defp load_contexts(socket) do
    contexts =
      socket
      |> fetch_contexts()
      |> filter_contexts_by_search(socket.assigns.search_query)

    assign(socket, :contexts, contexts)
  end

  defp fetch_contexts(socket) do
    case socket.assigns.selected_project_id do
      nil ->
        socket.assigns.projects
        |> Enum.flat_map(&Memory.list_contexts(&1.id))
        |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})

      project_id ->
        Memory.list_contexts(project_id)
    end
  end

  defp filter_contexts_by_search(contexts, ""), do: contexts

  defp filter_contexts_by_search(contexts, query) do
    query = String.downcase(query)
    Enum.filter(contexts, &context_matches_query?(&1, query))
  end

  defp context_matches_query?(context, query) do
    matches_field?(context.name, query) ||
      matches_field?(context.summary, query) ||
      matches_tags?(context.tags, query)
  end

  defp matches_field?(nil, _query), do: false
  defp matches_field?(value, query), do: String.contains?(String.downcase(value), query)

  defp matches_tags?(nil, _query), do: false
  defp matches_tags?(tags, query), do: Enum.any?(tags, &matches_field?(&1, query))

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.page_header title="Contexts" subtitle="Working state snapshots for AI sessions">
        <:actions>
          <.link_button navigate={~p"/pop_stash/contexts/new"} variant="primary">
            <.icon name="hero-plus" class="size-4" /> New Context
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
              placeholder="Search contexts..."
              class="w-full pl-10 pr-3 py-2 text-sm bg-white border border-slate-200 rounded focus:outline-none focus:ring-2 focus:ring-violet-500/20 focus:border-violet-500"
              phx-debounce="300"
            />
          </div>
        </form>
      </div>
      
    <!-- Context List -->
      <%= if @contexts == [] do %>
        <.empty_state
          title="No contexts found"
          description={
            if @search_query != "",
              do: "Try adjusting your search",
              else: "Create your first context to get started"
          }
        >
          <:action>
            <.link_button
              :if={@search_query == ""}
              navigate={~p"/pop_stash/contexts/new"}
              variant="primary"
            >
              <.icon name="hero-plus" class="size-4" /> New Context
            </.link_button>
          </:action>
        </.empty_state>
      <% else %>
        <.data_table id="contexts-table" rows={@contexts} row_id={&"context-#{&1.id}"}>
          <:col :let={context} label="Title" class="font-medium">
            <.link navigate={~p"/pop_stash/contexts/#{context.id}"} class="hover:text-violet-600">
              {context.title}
            </.link>
          </:col>
          <:col :let={context} label="Body">
            <.markdown_preview content={context.body} max_length={100} />
          </:col>
          <:col :let={context} label="Tags">
            <.tag_badges tags={context.tags || []} />
          </:col>
          <:col :let={context} label="Thread" mono>
            <span class="text-xs text-slate-500 font-mono">{context.thread_id}</span>
          </:col>
          <:col :let={context} label="Created" mono>
            <.timestamp datetime={context.inserted_at} />
          </:col>
          <:col :let={context} label="Actions" class="text-right">
            <div class="flex items-center justify-end gap-2">
              <.link_button navigate={~p"/pop_stash/contexts/#{context.id}"} variant="ghost" size="sm">
                View
              </.link_button>
              <.button
                variant="ghost"
                size="sm"
                phx-click="delete"
                phx-value-id={context.id}
                data-confirm="Are you sure you want to delete this context?"
              >
                <.icon name="hero-trash" class="size-4 text-red-500" />
              </.button>
            </div>
          </:col>
        </.data_table>
      <% end %>
      
    <!-- New Context Modal -->
      <.modal
        :if={@show_modal}
        id="context-modal"
        show={@show_modal}
        on_cancel={JS.push("close_modal")}
        title="New Context"
      >
        <.live_component
          module={PopStashWeb.Dashboard.ContextLive.FormComponent}
          id={:new}
          context={@context}
          projects={@projects}
          action={:new}
          return_to={~p"/pop_stash/contexts"}
        />
      </.modal>
    </div>
    """
  end
end
