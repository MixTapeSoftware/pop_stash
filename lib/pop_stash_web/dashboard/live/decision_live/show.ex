defmodule PopStashWeb.Dashboard.DecisionLive.Show do
  @moduledoc """
  LiveView for viewing a single decision with topic history.
  """

  use PopStashWeb.Dashboard, :live_view

  alias PopStash.Memory
  alias PopStash.Projects
  alias PopStash.Repo

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(PopStash.PubSub, "memory:events")
    end

    {:ok, assign(socket, :current_path, "/pop_stash/decisions")}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    decision = Repo.get!(Memory.Decision, id)
    project = Projects.get!(decision.project_id)

    # Get all decisions for this title (history)
    title_history =
      Memory.get_decisions_by_title(decision.project_id, decision.title)
      |> Enum.reject(&(&1.id == decision.id))

    socket =
      socket
      |> assign(:page_title, decision.title)
      |> assign(:decision, decision)
      |> assign(:project, project)
      |> assign(:projects, Projects.list())
      |> assign(:title_history, title_history)
      |> apply_action(socket.assigns.live_action)

    {:noreply, socket}
  end

  defp apply_action(socket, :show) do
    assign(socket, :show_modal, false)
  end

  defp apply_action(socket, :edit) do
    # Decisions are immutable, but we allow the edit route for consistency
    # The edit will create a new decision instead
    assign(socket, :show_modal, true)
  end

  @impl true
  def handle_event("delete", _, socket) do
    case Memory.delete_decision(socket.assigns.decision.id) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Decision deleted successfully")
         |> push_navigate(to: ~p"/pop_stash/decisions")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to delete decision")}
    end
  end

  def handle_event("close_modal", _, socket) do
    {:noreply, push_patch(socket, to: ~p"/pop_stash/decisions/#{socket.assigns.decision.id}")}
  end

  @impl true
  def handle_info({:decision_created, decision}, socket) do
    # If a new decision was created for the same title, update the history
    if decision.title == socket.assigns.decision.title &&
         decision.project_id == socket.assigns.decision.project_id do
      title_history =
        Memory.get_decisions_by_title(decision.project_id, decision.title)
        |> Enum.reject(&(&1.id == socket.assigns.decision.id))

      {:noreply, assign(socket, :title_history, title_history)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:decision_deleted, id}, socket) do
    if id == socket.assigns.decision.id do
      {:noreply,
       socket
       |> put_flash(:info, "This decision was deleted")
       |> push_navigate(to: ~p"/pop_stash/decisions")}
    else
      # Update history if a related decision was deleted
      title_history =
        Enum.reject(socket.assigns.title_history, &(&1.id == id))

      {:noreply, assign(socket, :title_history, title_history)}
    end
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.back_link navigate={~p"/pop_stash/decisions"} label="Back to decisions" />

      <div class="mt-4">
        <.page_header title={@decision.title} subtitle={"Project: #{@project.name}"}>
          <:actions>
            <.link_button navigate={~p"/pop_stash/decisions/new"} variant="secondary">
              <.icon name="hero-plus" class="size-4" /> New Decision
            </.link_button>
            <.button
              variant="danger"
              phx-click="delete"
              data-confirm="Are you sure you want to delete this decision? Decisions are meant to be immutable records."
            >
              <.icon name="hero-trash" class="size-4" /> Delete
            </.button>
          </:actions>
        </.page_header>
      </div>

      <div class="max-w-5xl">
        <!-- Main Content -->
        <div class="space-y-6">
          <.card>
            <.section_header title="Decision" />
            <.markdown content={@decision.body} />
          </.card>

          <%= if @decision.reasoning do %>
            <.card>
              <.section_header title="Reasoning" />
              <.markdown content={@decision.reasoning} />
            </.card>
          <% end %>
          
    <!-- Title History -->
          <%= if @title_history != [] do %>
            <.card>
              <.section_header title="Title History">
                <:actions>
                  <span class="text-xs text-slate-500">
                    {length(@title_history)} previous decision(s)
                  </span>
                </:actions>
              </.section_header>
              <div class="space-y-4">
                <div
                  :for={historical <- @title_history}
                  class="border-l-2 border-slate-200 pl-4 py-2"
                >
                  <div class="flex items-center gap-2 mb-2">
                    <.timestamp datetime={historical.inserted_at} />
                    <.link
                      navigate={~p"/pop_stash/decisions/#{historical.id}"}
                      class="text-xs text-violet-600 hover:text-violet-700"
                    >
                      View
                    </.link>
                  </div>
                  <.markdown_preview content={historical.body} max_length={150} />
                </div>
              </div>
            </.card>
          <% end %>
        </div>
        
    <!-- Details -->
        <.card class="mt-6">
          <dl class="divide-y divide-slate-100">
            <.detail_row label="ID">
              <span class="font-mono text-xs">{@decision.id}</span>
            </.detail_row>

            <.detail_row label="Title">
              <span class="font-mono">{@decision.title}</span>
            </.detail_row>

            <.detail_row label="Project">
              {@project.name}
            </.detail_row>

            <.detail_row label="Tags">
              <%= if @decision.tags && @decision.tags != [] do %>
                <.tag_badges tags={@decision.tags} />
              <% else %>
                <span class="text-slate-400 text-sm">No tags</span>
              <% end %>
            </.detail_row>

            <.detail_row label="Created">
              <.timestamp datetime={@decision.inserted_at} />
            </.detail_row>
          </dl>
        </.card>
        
    <!-- Immutability Notice -->
        <.card class="bg-amber-50 border-amber-200">
          <div class="flex gap-3">
            <.icon name="hero-information-circle" class="size-5 text-amber-600 flex-shrink-0" />
            <div>
              <h3 class="text-sm font-medium text-amber-800">Immutable Record</h3>
              <p class="text-xs text-amber-700 mt-1">
                Decisions are immutable by design. To update a decision, create a new one with the same topic.
                The history will be preserved.
              </p>
            </div>
          </div>
        </.card>
      </div>
    </div>
    """
  end
end
