# PubSub Activity Feed Plan

## Overview

Add a real-time activity feed to the dashboard that displays the 20 most recent stashes, decisions, and insights. The feed should update live as new items are created, leveraging Phoenix PubSub for real-time streaming.

## Current State

### Existing Infrastructure

The project already has PubSub infrastructure in place:

1. **PubSub Server**: `{Phoenix.PubSub, name: PopStash.PubSub}` in `application.ex`
2. **Broadcasting**: The `PopStash.Memory` context already broadcasts events:
   - `:stash_created`, `:stash_updated`, `:stash_deleted`
   - `:insight_created`, `:insight_updated`, `:insight_deleted`
   - `:decision_created`, `:decision_deleted`
3. **Topic**: Events broadcast to `"memory:events"` topic
4. **Subscriptions**: Some LiveViews (e.g., `StashLive.Index`) already subscribe to events

### Existing Broadcast Code (memory.ex)

```elixir
defp broadcast(event, payload) do
  Phoenix.PubSub.broadcast(PopStash.PubSub, "memory:events", {event, payload})
end

defp tap_ok({:ok, value} = result, fun) do
  fun.(value)
  result
end
```

## Requirements

### Functional Requirements

1. Display a unified activity feed showing the 20 most recent items (stashes, decisions, insights combined)
2. Items should be sorted by creation time (newest first)
3. Each item should display:
   - Type indicator (icon/badge)
   - Title/name/topic
   - Preview of content (truncated)
   - Timestamp
   - Project association
4. New items should stream in real-time (prepend to top, remove oldest if > 20)
5. Clicking an item navigates to its detail view
6. Optional: Filter by type or project

### Non-Functional Requirements

1. Smooth animations for new items appearing
2. No page refresh required for updates
3. Handle disconnection/reconnection gracefully
4. Minimal performance impact on dashboard load

---

## Architecture

### Data Flow

```
┌─────────────────┐     ┌──────────────────┐     ┌────────────────────┐
│  Memory Context │────▶│  Phoenix PubSub  │────▶│  HomeLive / Feed   │
│  (create_*)     │     │  "memory:events" │     │  LiveComponent     │
└─────────────────┘     └──────────────────┘     └────────────────────┘
                                                           │
                                                           ▼
                                                 ┌────────────────────┐
                                                 │  Activity Feed UI  │
                                                 │  (20 recent items) │
                                                 └────────────────────┘
```

### Unified Activity Item Structure

Create a common struct for activity feed items:

```elixir
defmodule PopStash.Activity.Item do
  @type t :: %__MODULE__{
    id: String.t(),
    type: :stash | :decision | :insight,
    title: String.t(),
    preview: String.t() | nil,
    project_id: String.t(),
    project_name: String.t() | nil,
    inserted_at: DateTime.t(),
    source: struct()
  }
  
  defstruct [:id, :type, :title, :preview, :project_id, :project_name, :inserted_at, :source]
end
```

---

## Implementation Phases

### Phase 1: Activity Context Module

Create a new module to handle activity feed logic.

**File**: `lib/pop_stash/activity.ex`

```elixir
defmodule PopStash.Activity do
  @moduledoc """
  Context for unified activity feed across stashes, decisions, and insights.
  """
  
  import Ecto.Query
  
  alias PopStash.Repo
  alias PopStash.Memory.{Stash, Decision, Insight}
  alias PopStash.Projects.Project
  
  defmodule Item do
    @moduledoc "Unified activity item for the feed."
    defstruct [:id, :type, :title, :preview, :project_id, :project_name, :inserted_at, :source]
  end
  
  @doc """
  Fetches the most recent activity items across all types.
  
  ## Options
    * `:limit` - Maximum items to return (default: 20)
    * `:project_id` - Filter by project (optional)
    * `:types` - List of types to include (default: all)
  """
  def list_recent(opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    project_id = Keyword.get(opts, :project_id)
    types = Keyword.get(opts, :types, [:stash, :decision, :insight])
    
    items = []
    
    items = if :stash in types, do: items ++ fetch_stashes(project_id, limit), else: items
    items = if :decision in types, do: items ++ fetch_decisions(project_id, limit), else: items
    items = if :insight in types, do: items ++ fetch_insights(project_id, limit), else: items
    
    items
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
    |> Enum.take(limit)
  end
  
  @doc """
  Converts a raw entity to an activity item.
  Used for real-time updates when a new item is created.
  """
  def to_item(%Stash{} = stash) do
    %Item{
      id: stash.id,
      type: :stash,
      title: stash.name,
      preview: truncate(stash.summary, 100),
      project_id: stash.project_id,
      project_name: get_project_name(stash.project_id),
      inserted_at: stash.inserted_at,
      source: stash
    }
  end
  
  def to_item(%Decision{} = decision) do
    %Item{
      id: decision.id,
      type: :decision,
      title: decision.topic,
      preview: truncate(decision.decision, 100),
      project_id: decision.project_id,
      project_name: get_project_name(decision.project_id),
      inserted_at: decision.inserted_at,
      source: decision
    }
  end
  
  def to_item(%Insight{} = insight) do
    %Item{
      id: insight.id,
      type: :insight,
      title: insight.key || "Insight",
      preview: truncate(insight.content, 100),
      project_id: insight.project_id,
      project_name: get_project_name(insight.project_id),
      inserted_at: insight.inserted_at,
      source: insight
    }
  end
  
  # Private functions
  
  defp fetch_stashes(project_id, limit) do
    Stash
    |> maybe_filter_project(project_id)
    |> where([s], is_nil(s.expires_at) or s.expires_at > ^DateTime.utc_now())
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> preload(:project)
    |> Repo.all()
    |> Enum.map(&to_item/1)
  end
  
  defp fetch_decisions(project_id, limit) do
    Decision
    |> maybe_filter_project(project_id)
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> preload(:project)
    |> Repo.all()
    |> Enum.map(&to_item/1)
  end
  
  defp fetch_insights(project_id, limit) do
    Insight
    |> maybe_filter_project(project_id)
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> preload(:project)
    |> Repo.all()
    |> Enum.map(&to_item/1)
  end
  
  defp maybe_filter_project(query, nil), do: query
  defp maybe_filter_project(query, project_id), do: where(query, [q], q.project_id == ^project_id)
  
  defp get_project_name(project_id) do
    case Repo.get(Project, project_id) do
      nil -> nil
      project -> project.name
    end
  end
  
  defp truncate(nil, _), do: nil
  defp truncate(text, max_length) when byte_size(text) <= max_length, do: text
  defp truncate(text, max_length) do
    String.slice(text, 0, max_length) <> "..."
  end
end
```

### Phase 2: Activity Feed LiveComponent

Create a reusable LiveComponent for the activity feed.

**File**: `lib/pop_stash_web/dashboard/live/activity_feed_component.ex`

```elixir
defmodule PopStashWeb.Dashboard.ActivityFeedComponent do
  @moduledoc """
  LiveComponent for displaying real-time activity feed.
  """
  
  use PopStashWeb.Dashboard, :live_component
  
  alias PopStash.Activity
  
  @impl true
  def mount(socket) do
    {:ok, assign(socket, items: [], loading: true)}
  end
  
  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:limit, fn -> 20 end)
      |> assign_new(:project_id, fn -> nil end)
      |> assign_new(:show_project, fn -> true end)
      |> load_items()
    
    {:ok, socket}
  end
  
  defp load_items(socket) do
    items = Activity.list_recent(
      limit: socket.assigns.limit,
      project_id: socket.assigns.project_id
    )
    
    assign(socket, items: items, loading: false)
  end
  
  @doc """
  Called by parent LiveView when a new item is created.
  Prepends the item and removes oldest if over limit.
  """
  def prepend_item(socket, item) do
    items = [item | socket.assigns.items]
    items = Enum.take(items, socket.assigns.limit)
    assign(socket, :items, items)
  end
  
  @doc """
  Called by parent LiveView when an item is deleted.
  """
  def remove_item(socket, item_id) do
    items = Enum.reject(socket.assigns.items, &(&1.id == item_id))
    assign(socket, :items, items)
  end
  
  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-1" id={@id}>
      <div :if={@loading} class="py-8 text-center text-slate-400 text-sm">
        Loading activity...
      </div>
      
      <div :if={!@loading && @items == []} class="py-8 text-center text-slate-400 text-sm">
        No recent activity
      </div>
      
      <div
        :for={item <- @items}
        id={"activity-#{item.id}"}
        class="group flex items-start gap-3 p-3 rounded hover:bg-slate-50 transition-colors"
        phx-mounted={JS.transition("animate-slide-in")}
      >
        <!-- Type Icon -->
        <div class={[
          "flex-shrink-0 w-8 h-8 rounded flex items-center justify-center",
          type_bg_class(item.type)
        ]}>
          <.icon name={type_icon(item.type)} class={["size-4", type_icon_class(item.type)]} />
        </div>
        
        <!-- Content -->
        <div class="flex-1 min-w-0">
          <.link
            navigate={item_path(item)}
            class="block text-sm font-medium text-slate-900 hover:text-violet-600 truncate"
          >
            {item.title}
          </.link>
          
          <p :if={item.preview} class="text-xs text-slate-500 truncate mt-0.5">
            {item.preview}
          </p>
          
          <div class="flex items-center gap-2 mt-1">
            <.badge :if={@show_project && item.project_name} variant="subtle" size="xs">
              {item.project_name}
            </.badge>
            <span class="text-xs text-slate-400 font-mono">
              <.relative_time datetime={item.inserted_at} />
            </span>
          </div>
        </div>
        
        <!-- Type Badge -->
        <.badge variant={type_variant(item.type)} size="xs" class="flex-shrink-0">
          {type_label(item.type)}
        </.badge>
      </div>
    </div>
    """
  end
  
  # Helper functions
  
  defp type_icon(:stash), do: "hero-archive-box"
  defp type_icon(:decision), do: "hero-check-badge"
  defp type_icon(:insight), do: "hero-light-bulb"
  
  defp type_bg_class(:stash), do: "bg-blue-50"
  defp type_bg_class(:decision), do: "bg-green-50"
  defp type_bg_class(:insight), do: "bg-amber-50"
  
  defp type_icon_class(:stash), do: "text-blue-500"
  defp type_icon_class(:decision), do: "text-green-500"
  defp type_icon_class(:insight), do: "text-amber-500"
  
  defp type_variant(:stash), do: "blue"
  defp type_variant(:decision), do: "green"
  defp type_variant(:insight), do: "amber"
  
  defp type_label(:stash), do: "Stash"
  defp type_label(:decision), do: "Decision"
  defp type_label(:insight), do: "Insight"
  
  defp item_path(%{type: :stash, id: id}), do: ~p"/pop_stash/stashes/#{id}"
  defp item_path(%{type: :decision, id: id}), do: ~p"/pop_stash/decisions/#{id}"
  defp item_path(%{type: :insight, id: id}), do: ~p"/pop_stash/insights/#{id}"
end
```

### Phase 3: Update HomeLive with Activity Feed

Modify the dashboard home page to include the activity feed with real-time updates.

**File**: `lib/pop_stash_web/dashboard/live/home_live.ex` (modified)

```elixir
defmodule PopStashWeb.Dashboard.HomeLive do
  @moduledoc """
  Dashboard home/overview page showing memory statistics and recent activity.
  """

  use PopStashWeb.Dashboard, :live_view

  alias PopStash.Projects
  alias PopStash.Memory
  alias PopStash.Activity

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

  # ... existing handle_params and handle_event callbacks ...

  @impl true
  def handle_info({:stash_created, stash}, socket) do
    item = Activity.to_item(stash)
    {:noreply, prepend_activity_item(socket, item)}
  end

  def handle_info({:decision_created, decision}, socket) do
    item = Activity.to_item(decision)
    {:noreply, prepend_activity_item(socket, item)}
  end

  def handle_info({:insight_created, insight}, socket) do
    item = Activity.to_item(insight)
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

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  defp load_activity(socket) do
    items = Activity.list_recent(
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

  # ... existing load_stats/1 ...

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <!-- ... existing header and stats ... -->

      <div class="mt-8 grid grid-cols-1 lg:grid-cols-3 gap-6">
        <!-- Activity Feed (spans 2 columns) -->
        <div class="lg:col-span-2">
          <.card>
            <.section_header title="Recent Activity">
              <:actions>
                <span class="text-xs text-slate-400">Live updates enabled</span>
                <span class="relative flex h-2 w-2 ml-2">
                  <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-green-400 opacity-75"></span>
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

        <!-- Quick Actions (sidebar) -->
        <div class="space-y-6">
          <.card>
            <.section_header title="Quick Actions" />
            <!-- ... existing quick actions ... -->
          </.card>

          <.card>
            <.section_header title="Navigation" />
            <!-- ... existing navigation ... -->
          </.card>
        </div>
      </div>
    </div>
    """
  end
end
```

### Phase 4: Add CSS Animation

Add slide-in animation for new activity items.

**File**: `assets/css/app.css` (add to existing)

```css
/* Activity Feed Animations */
@keyframes slide-in {
  from {
    opacity: 0;
    transform: translateY(-10px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

.animate-slide-in {
  animation: slide-in 0.3s ease-out;
}

/* Optional: Highlight new items briefly */
@keyframes highlight-new {
  0% {
    background-color: rgb(245 243 255); /* violet-50 */
  }
  100% {
    background-color: transparent;
  }
}

.highlight-new {
  animation: highlight-new 2s ease-out;
}
```

### Phase 5: Add Helper Components

Add any missing helper components to the dashboard components module.

**File**: `lib/pop_stash_web/dashboard/components.ex` (additions)

```elixir
# Add to existing components

@doc """
Renders a relative timestamp that updates.
"""
attr :datetime, :any, required: true

def relative_time(assigns) do
  ~H"""
  <time datetime={DateTime.to_iso8601(@datetime)} title={format_datetime(@datetime)}>
    {relative_time_string(@datetime)}
  </time>
  """
end

defp relative_time_string(datetime) do
  now = DateTime.utc_now()
  diff = DateTime.diff(now, datetime, :second)
  
  cond do
    diff < 60 -> "just now"
    diff < 3600 -> "#{div(diff, 60)}m ago"
    diff < 86400 -> "#{div(diff, 3600)}h ago"
    diff < 604800 -> "#{div(diff, 86400)}d ago"
    true -> Calendar.strftime(datetime, "%b %d")
  end
end

defp format_datetime(datetime) do
  Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S UTC")
end

@doc """
Badge component with color variants.
"""
attr :variant, :string, default: "default"
attr :size, :string, default: "sm"
attr :class, :any, default: nil
slot :inner_block, required: true

def badge(assigns) do
  ~H"""
  <span class={[
    "inline-flex items-center font-medium rounded",
    badge_size_class(@size),
    badge_variant_class(@variant),
    @class
  ]}>
    {render_slot(@inner_block)}
  </span>
  """
end

defp badge_size_class("xs"), do: "px-1.5 py-0.5 text-xs"
defp badge_size_class("sm"), do: "px-2 py-0.5 text-xs"
defp badge_size_class("md"), do: "px-2.5 py-1 text-sm"

defp badge_variant_class("default"), do: "bg-slate-100 text-slate-700"
defp badge_variant_class("subtle"), do: "bg-slate-50 text-slate-600"
defp badge_variant_class("blue"), do: "bg-blue-100 text-blue-700"
defp badge_variant_class("green"), do: "bg-green-100 text-green-700"
defp badge_variant_class("amber"), do: "bg-amber-100 text-amber-700"
defp badge_variant_class("violet"), do: "bg-violet-100 text-violet-700"
```

---

## Implementation Checklist

### Phase 1: Activity Context
- [x] Create `lib/pop_stash/activity.ex`
- [x] Add `Item` struct definition
- [x] Implement `list_recent/1` function
- [x] Implement `to_item/1` for each entity type
- [x] Write unit tests for Activity module

### Phase 2: Activity Feed Component
- [x] Create `lib/pop_stash_web/dashboard/live/activity_feed_component.ex`
- [x] Implement `mount/1` and `update/2`
- [x] Implement `render/1` with item display
- [x] Add helper functions for type-specific styling
- [x] Add navigation paths for each type

### Phase 3: HomeLive Integration
- [x] Update `home_live.ex` with PubSub subscription
- [x] Add `handle_info/2` for all event types
- [x] Implement `load_activity/1`
- [x] Implement `prepend_activity_item/2` and `remove_activity_item/2`
- [x] Update render to include activity feed
- [x] Handle project filter changes (reload activity)

### Phase 4: CSS & Animations
- [x] Add slide-in animation keyframes
- [x] Add highlight-new animation (optional)
- [ ] Test animations in browser

### Phase 5: Helper Components
- [x] Add `relative_time/1` component (implemented inline as `relative_time_string/1`)
- [x] Add `badge/1` component with variants (implemented inline in component)
- [x] Ensure all required components exist

### Phase 6: Testing
- [x] Unit tests for `PopStash.Activity`
- [ ] LiveView tests for activity feed subscription
- [ ] Integration test for real-time updates

---

## File Checklist

| File | Status | Description |
|------|--------|-------------|
| `lib/pop_stash/activity.ex` | ✅ Done | Activity context module |
| `lib/pop_stash_web/dashboard/live/activity_feed_component.ex` | ✅ Done | Activity feed LiveComponent |
| `lib/pop_stash_web/dashboard/live/home_live.ex` | ✅ Done | Add feed integration |
| `lib/pop_stash_web/dashboard/components.ex` | Skipped | Helper components implemented inline |
| `assets/css/app.css` | ✅ Done | Add animations |
| `test/pop_stash/activity_test.exs` | ✅ Done | Activity context tests |
| `test/pop_stash_web/dashboard/live/home_live_test.exs` | Pending | Add feed tests |

---

## Future Enhancements

1. **Filtering**: Add buttons to filter by type (stashes only, decisions only, etc.)
2. **Infinite Scroll**: Load more items as user scrolls down
3. **Notifications**: Show toast notification when new items arrive (when not focused)
4. **Sound**: Optional subtle sound for new items
5. **Read State**: Track which items user has seen
6. **Activity by User**: If multi-user support is added, show who created each item
7. **Undo Actions**: Show undo option in feed for recently deleted items

---

## Notes

- The existing PubSub infrastructure is well-designed and requires minimal changes
- The `Memory` context already broadcasts all necessary events
- Consider rate-limiting the UI updates if many items are created rapidly (debounce)
- The activity feed should gracefully handle disconnection (show reconnecting state)
- Consider adding a "catch up" mechanism when reconnecting to fetch any missed items