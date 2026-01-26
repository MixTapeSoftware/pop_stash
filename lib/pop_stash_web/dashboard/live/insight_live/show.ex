defmodule PopStashWeb.Dashboard.InsightLive.Show do
  @moduledoc """
  LiveView for viewing a single insight.
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

    {:ok, assign(socket, :current_path, "/insights")}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    insight = Repo.get!(Memory.Insight, id)
    project = Projects.get!(insight.project_id)

    socket =
      socket
      |> assign(:page_title, insight.key || "Insight")
      |> assign(:insight, insight)
      |> assign(:project, project)
      |> assign(:projects, Projects.list())
      |> apply_action(socket.assigns.live_action)

    {:noreply, socket}
  end

  defp apply_action(socket, :show) do
    assign(socket, :show_modal, false)
  end

  defp apply_action(socket, :edit) do
    assign(socket, :show_modal, true)
  end

  @impl true
  def handle_event("delete", _, socket) do
    case Memory.delete_insight(socket.assigns.insight.id) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Insight deleted successfully")
         |> push_navigate(to: ~p"/insights")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to delete insight")}
    end
  end

  def handle_event("close_modal", _, socket) do
    {:noreply, push_patch(socket, to: ~p"/insights/#{socket.assigns.insight.id}")}
  end

  @impl true
  def handle_info({:insight_updated, insight}, socket) do
    if insight.id == socket.assigns.insight.id do
      {:noreply, assign(socket, :insight, insight)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:insight_deleted, id}, socket) do
    if id == socket.assigns.insight.id do
      {:noreply,
       socket
       |> put_flash(:info, "This insight was deleted")
       |> push_navigate(to: ~p"/insights")}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.back_link navigate={~p"/insights"} label="Back to insights" />

      <div class="mt-4">
        <.page_header title={@insight.key || "Insight"} subtitle={"Project: #{@project.name}"}>
          <:actions>
            <.link_button navigate={~p"/insights/#{@insight.id}/edit"} variant="secondary">
              <.icon name="hero-pencil" class="size-4" /> Edit
            </.link_button>
            <.button
              variant="danger"
              phx-click="delete"
              data-confirm="Are you sure you want to delete this insight? This action cannot be undone."
            >
              <.icon name="hero-trash" class="size-4" /> Delete
            </.button>
          </:actions>
        </.page_header>
      </div>

      <div class="max-w-5xl">
        <!-- Main Content -->
        <.card>
          <.section_header title="Content" />
          <.markdown content={@insight.content} />
        </.card>
        
    <!-- Details -->
        <.card class="mt-6">
          <dl class="divide-y divide-slate-100">
            <.detail_row label="ID">
              <span class="font-mono text-xs">{@insight.id}</span>
            </.detail_row>

            <.detail_row label="Key">
              <%= if @insight.key do %>
                <span class="font-mono">{@insight.key}</span>
              <% else %>
                <span class="text-slate-400 text-sm">No key</span>
              <% end %>
            </.detail_row>

            <.detail_row label="Project">
              {@project.name}
            </.detail_row>

            <.detail_row label="Tags">
              <%= if @insight.tags && @insight.tags != [] do %>
                <.tag_badges tags={@insight.tags} />
              <% else %>
                <span class="text-slate-400 text-sm">No tags</span>
              <% end %>
            </.detail_row>

            <.detail_row label="Created">
              <.timestamp datetime={@insight.inserted_at} />
            </.detail_row>

            <.detail_row label="Updated">
              <.timestamp datetime={@insight.updated_at} />
            </.detail_row>
          </dl>
        </.card>
      </div>
      
    <!-- Edit Modal -->
      <.modal
        :if={@show_modal}
        id="insight-edit-modal"
        show={@show_modal}
        on_cancel={JS.push("close_modal")}
        title="Edit Insight"
      >
        <.live_component
          module={PopStashWeb.Dashboard.InsightLive.FormComponent}
          id={@insight.id}
          insight={@insight}
          projects={@projects}
          action={:edit}
          return_to={~p"/insights/#{@insight.id}"}
        />
      </.modal>
    </div>
    """
  end
end
