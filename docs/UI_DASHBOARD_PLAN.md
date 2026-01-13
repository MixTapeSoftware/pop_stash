# PopStash UI Dashboard Plan

## Overview

Build an optional, self-contained LiveView dashboard for managing PopStash memory (decisions, insights, stashes). Following the pattern of Phoenix LiveDashboard and Oban Web, the dashboard will be:

- **Optional** - Users mount it in their router if desired
- **Self-secured** - Users are responsible for authentication/authorization
- **Self-contained** - All components live under `PopStashWeb.Dashboard`

---

## Design Direction

Following the design-principles skill, we commit to a specific direction before writing any code.

### Context Analysis

- **What does PopStash do?** Memory/knowledge management for AI agents — storing decisions, insights, and context stashes
- **Who uses it?** Developers and power users who work with AI tools daily. They want efficiency and density.
- **Emotional job?** Trust (this stores important decisions), efficiency (quick CRUD), clarity (understand what's stored)
- **What makes it memorable?** A developer tool that feels as polished as Linear but purpose-built for AI memory

### Chosen Personality: **Precision & Density** with **Utility & Function**

This is a developer tool for managing AI context. Users live in terminals and code editors. They want:
- Information density over generous whitespace
- Fast scanning and navigation
- Technical aesthetic that feels at home alongside Linear, Raycast, GitHub

### Color Foundation

**Cool foundation** with pure neutrals:
- Background: Slate grays (`slate-50`, `slate-100` for light mode)
- Surfaces: White cards on subtle gray background
- Text hierarchy: `slate-900` → `slate-600` → `slate-400` → `slate-300`
- **Single accent: Violet** (`violet-600`) — creativity, AI/intelligence connotation
- Status colors: Muted versions (not traffic-light bright)

**Light mode default** — approachable for a dashboard, with dark mode as enhancement later.

### Layout Approach

- **Sidebar navigation** — multi-section app with clear destinations
- **Dense tables** — information-heavy lists for scanning stashes/insights/decisions
- **Split panels** — list-detail pattern for viewing individual items

### Typography

- **System fonts** (fast, native) with **monospace for data** (IDs, timestamps, tags)
- Tight hierarchy: 12px labels, 14px body, 16px headings, 24px page titles
- `tabular-nums` for any numeric data
- `-0.02em` letter-spacing on headings

### Depth Strategy: **Borders-only (flat)**

Following Linear/Raycast aesthetic:
- No layered shadows
- Subtle borders (`slate-200`, `0.5px` or `1px`) to define regions
- Surface color shifts for elevation (white on `slate-50`)
- This creates technical, dense, clean appearance

### Spacing (4px Grid)

```
4px   - icon gaps, micro spacing
8px   - within components (button padding, input padding)
12px  - between related elements
16px  - section padding, card padding
24px  - between sections
32px  - major page separation
```

### Border Radius: Sharp System

- `4px` - buttons, inputs, badges
- `6px` - cards, dropdowns
- `8px` - modals only

---

## Dependencies

Add to `mix.exs`:

```elixir
{:earmark, "~> 1.4"},
{:html_sanitize_ex, "~> 1.4"}
```

## Architecture

### Module Structure

```
lib/pop_stash_web/
├── dashboard/
│   ├── dashboard.ex              # Main LiveView entry point
│   ├── router.ex                 # Router helpers for mounting
│   ├── components/
│   │   ├── dashboard_components.ex  # Shared DaisyUI components
│   │   ├── markdown.ex              # Markdown rendering component
│   │   └── layouts.ex               # Dashboard-specific layouts
│   ├── live/
│   │   ├── home_live.ex          # Dashboard home/overview
│   │   ├── stash_live/
│   │   │   ├── index.ex          # List stashes
│   │   │   ├── show.ex           # View single stash
│   │   │   └── form_component.ex # Create/edit form
│   │   ├── insight_live/
│   │   │   ├── index.ex          # List insights
│   │   │   ├── show.ex           # View single insight
│   │   │   └── form_component.ex # Create/edit form
│   │   └── decision_live/
│   │       ├── index.ex          # List decisions
│   │       ├── show.ex           # View single decision
│   │       └── form_component.ex # Create/edit form
│   └── markdown_scrubber.ex      # HTML sanitization rules
```

### Router Integration

Users mount the dashboard in their router:

```elixir
# In router.ex
import PopStashWeb.Dashboard.Router

scope "/pop_stash" do
  pipe_through [:browser, :admin_auth]  # User provides auth
  pop_stash_dashboard "/"
end
```

The `pop_stash_dashboard/2` macro generates routes:

```elixir
defmodule PopStashWeb.Dashboard.Router do
  defmacro pop_stash_dashboard(path, opts \\ []) do
    quote bind_quoted: [path: path, opts: opts] do
      scope path, alias: false, as: false do
        import Phoenix.LiveView.Router, only: [live: 4, live_session: 3]

        live_session :pop_stash_dashboard,
          root_layout: {PopStashWeb.Dashboard.Layouts, :root},
          layout: {PopStashWeb.Dashboard.Layouts, :dashboard} do
          
          live "/", PopStashWeb.Dashboard.HomeLive, :index
          
          # Stashes
          live "/stashes", PopStashWeb.Dashboard.StashLive.Index, :index
          live "/stashes/new", PopStashWeb.Dashboard.StashLive.Index, :new
          live "/stashes/:id", PopStashWeb.Dashboard.StashLive.Show, :show
          live "/stashes/:id/edit", PopStashWeb.Dashboard.StashLive.Show, :edit
          
          # Insights
          live "/insights", PopStashWeb.Dashboard.InsightLive.Index, :index
          live "/insights/new", PopStashWeb.Dashboard.InsightLive.Index, :new
          live "/insights/:id", PopStashWeb.Dashboard.InsightLive.Show, :show
          live "/insights/:id/edit", PopStashWeb.Dashboard.InsightLive.Show, :edit
          
          # Decisions
          live "/decisions", PopStashWeb.Dashboard.DecisionLive.Index, :index
          live "/decisions/new", PopStashWeb.Dashboard.DecisionLive.Index, :new
          live "/decisions/:id", PopStashWeb.Dashboard.DecisionLive.Show, :show
          live "/decisions/:id/edit", PopStashWeb.Dashboard.DecisionLive.Show, :edit
        end
      end
    end
  end
end
```

---

## Phase 1: Foundation

### 1.1 Add Dependencies

```elixir
# mix.exs
{:earmark, "~> 1.4"},
{:html_sanitize_ex, "~> 1.4"}
```

### 1.2 Create Markdown Scrubber

```elixir
# lib/pop_stash_web/dashboard/markdown_scrubber.ex
defmodule PopStashWeb.Dashboard.MarkdownScrubber do
  @moduledoc """
  Allows basic HTML tags for Markdown rendering.
  Does not allow scripts, styles, or dangerous elements.
  """

  require HtmlSanitizeEx.Scrubber.Meta
  alias HtmlSanitizeEx.Scrubber.Meta

  Meta.remove_cdata_sections_before_scrub()
  Meta.strip_comments()

  # Text formatting
  Meta.allow_tag_with_these_attributes("b", [])
  Meta.allow_tag_with_these_attributes("strong", [])
  Meta.allow_tag_with_these_attributes("i", [])
  Meta.allow_tag_with_these_attributes("em", [])
  Meta.allow_tag_with_these_attributes("u", [])
  Meta.allow_tag_with_these_attributes("del", [])
  Meta.allow_tag_with_these_attributes("span", [])

  # Headings
  Meta.allow_tag_with_these_attributes("h1", [])
  Meta.allow_tag_with_these_attributes("h2", [])
  Meta.allow_tag_with_these_attributes("h3", [])
  Meta.allow_tag_with_these_attributes("h4", [])
  Meta.allow_tag_with_these_attributes("h5", [])
  Meta.allow_tag_with_these_attributes("h6", [])

  # Structure
  Meta.allow_tag_with_these_attributes("p", [])
  Meta.allow_tag_with_these_attributes("br", [])
  Meta.allow_tag_with_these_attributes("blockquote", [])
  Meta.allow_tag_with_these_attributes("pre", [])
  Meta.allow_tag_with_these_attributes("code", ["class"])

  # Lists
  Meta.allow_tag_with_these_attributes("ul", [])
  Meta.allow_tag_with_these_attributes("ol", [])
  Meta.allow_tag_with_these_attributes("li", [])

  # Tables
  Meta.allow_tag_with_these_attributes("table", [])
  Meta.allow_tag_with_these_attributes("thead", [])
  Meta.allow_tag_with_these_attributes("tbody", [])
  Meta.allow_tag_with_these_attributes("tr", [])
  Meta.allow_tag_with_these_attributes("th", [])
  Meta.allow_tag_with_these_attributes("td", [])

  # Links (href only, no javascript:)
  Meta.allow_tag_with_uri_attributes("a", ["href"], ["http", "https"])

  Meta.strip_everything_not_covered()
end
```

### 1.3 Create Markdown Rendering Helper

```elixir
# lib/pop_stash_web/dashboard/markdown.ex
defmodule PopStashWeb.Dashboard.Markdown do
  @moduledoc """
  Safe Markdown rendering for the dashboard.
  """

  @doc """
  Converts markdown to sanitized HTML.
  Returns a Phoenix.HTML.safe tuple.
  """
  def render(nil), do: {:safe, ""}
  def render(""), do: {:safe, ""}

  def render(markdown) when is_binary(markdown) do
    markdown
    |> Earmark.as_html!(code_class_prefix: "language-")
    |> HtmlSanitizeEx.Scrubber.scrub(PopStashWeb.Dashboard.MarkdownScrubber)
    |> Phoenix.HTML.raw()
  end

  @doc """
  Renders a truncated preview of markdown content.
  """
  def preview(markdown, max_length \\ 200) do
    markdown
    |> String.slice(0, max_length)
    |> then(fn text ->
      if String.length(markdown || "") > max_length do
        text <> "..."
      else
        text
      end
    end)
    |> render()
  end
end
```

### 1.4 Dashboard Router Module

Create the router helper macro as shown in Architecture section.

---

## Phase 2: Dashboard Layout & Components

### 2.1 Dashboard Layout

Following design direction: slate background, white surfaces, border separation (no shadow), tight typography.

```heex
<!-- Root layout: minimal wrapper -->
<!DOCTYPE html>
<html lang="en" class="h-full">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>PopStash Dashboard</title>
    <link phx-track-static rel="stylesheet" href={~p"/assets/app.css"} />
    <script defer phx-track-static src={~p"/assets/app.js"}></script>
  </head>
  <body class="h-full bg-slate-50 text-slate-900 antialiased">
    {@inner_content}
  </body>
</html>

<!-- Dashboard layout: sidebar + main content -->
<div class="flex h-screen">
  <!-- Sidebar - same bg as content, border separation (Linear/Vercel style) -->
  <aside class="hidden lg:flex lg:flex-col w-56 bg-slate-50 border-r border-slate-200">
    <!-- Logo -->
    <div class="p-4 border-b border-slate-200">
      <h1 class="text-base font-semibold text-slate-900 tracking-tight">PopStash</h1>
      
    </div>
    
    <!-- Navigation -->
    <nav class="flex-1 p-3">
      <ul class="space-y-1">
        <li>
          <.link
            navigate={~p"/pop_stash"}
            class="flex items-center gap-2 px-3 py-2 text-sm text-slate-600 hover:text-slate-900 hover:bg-slate-100 rounded transition-colors duration-150"
          >
            Overview
          </.link>
        </li>
        
        <li class="pt-4">
          <span class="px-3 text-xs font-medium text-slate-400 uppercase tracking-wide">Memory</span>
        </li>
        
        <li>
          <.link
            navigate={~p"/pop_stash/stashes"}
            class="flex items-center gap-2 px-3 py-2 text-sm text-slate-600 hover:text-slate-900 hover:bg-slate-100 rounded transition-colors duration-150"
          >
            Stashes
          </.link>
        </li>
        <li>
          <.link
            navigate={~p"/pop_stash/insights"}
            class="flex items-center gap-2 px-3 py-2 text-sm text-slate-600 hover:text-slate-900 hover:bg-slate-100 rounded transition-colors duration-150"
          >
            Insights
          </.link>
        </li>
        <li>
          <.link
            navigate={~p"/pop_stash/decisions"}
            class="flex items-center gap-2 px-3 py-2 text-sm text-slate-600 hover:text-slate-900 hover:bg-slate-100 rounded transition-colors duration-150"
          >
            Decisions
          </.link>
        </li>
      </ul>
    </nav>
  </aside>
  
  <!-- Main content area -->
  <div class="flex-1 flex flex-col overflow-hidden">
    <!-- Mobile header -->
    <header class="lg:hidden flex items-center gap-4 px-4 py-3 bg-white border-b border-slate-200">
      <button
        type="button"
        class="p-2 text-slate-500 hover:text-slate-900 hover:

### 2.2 Design System Components

Components follow our design direction: precision, density, borders-only depth, violet accent.

```elixir
# lib/pop_stash_web/dashboard/components/dashboard_components.ex
defmodule PopStashWeb.Dashboard.Components do
  @moduledoc """
  Design system components for PopStash Dashboard.
  
  Design direction: Precision & Density (Linear/Raycast aesthetic)
  - Borders-only depth (no shadows)
  - Cool slate foundation
  - Violet accent color
  - 4px grid spacing
  - Sharp border radius (4px-8px)
  """
  
  use Phoenix.Component
  import PopStashWeb.Dashboard.Markdown

  # =============================================================
  # Design Tokens (reference, applied via Tailwind classes)
  # =============================================================
  #
  # Spacing (4px grid):
  #   1 = 4px, 2 = 8px, 3 = 12px, 4 = 16px, 6 = 24px, 8 = 32px
  #
  # Colors:
  #   Background: slate-50
  #   Surface: white
  #   Border: slate-200 (or slate-200/50 for subtle)
  #   Text: slate-900 → slate-600 → slate-400 → slate-300
  #   Accent: violet-600 (hover: violet-700)
  #   
  # Border radius:
  #   sm (4px) - buttons, badges, inputs
  #   md (6px) - cards, dropdowns  
  #   lg (8px) - modals only
  #
  # =============================================================

  # Card - flat with border, no shadow
  attr :class, :string, default: ""
  slot :inner_block, required: true
  slot :actions

  def card(assigns) do
    ~H"""
    <div class={[
      "bg-white border border-slate-200 rounded-md",
      "p-4",  # 16px symmetrical padding
      @class
    ]}>
      {render_slot(@inner_block)}
      <div :if={@actions != []} class="flex justify-end gap-2 mt-4 pt-4 border-t border-slate-100">
        {render_slot(@actions)}
      </div>
    </div>
    """
  end

  # Page header with tight typography
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  slot :actions

  def page_header(assigns) do
    ~H"""
    <div class="flex items-center justify-between mb-6">
      <div>
        <h1 class="text-2xl font-semibold text-slate-900 tracking-tight">{@title}</h1>
        <p :if={@subtitle} class="text-sm text-slate-500 mt-1">{@subtitle}</p>
      </div>
      <div :if={@actions != []} class="flex items-center gap-2">
        {render_slot(@actions)}
      </div>
    </div>
    """
  end

  # Button - primary (violet accent)
  attr :type, :string, default: "button"
  attr :variant, :string, default: "primary", values: ["primary", "secondary", "ghost", "danger"]
  attr :size, :string, default: "md", values: ["sm", "md"]
  attr :class, :string, default: ""
  attr :rest, :global
  slot :inner_block, required: true

  def button(assigns) do
    ~H"""
    <button
      type={@type}
      class={[
        "inline-flex items-center justify-center font-medium rounded transition-colors duration-150",
        button_size_classes(@size),
        button_variant_classes(@variant),
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  defp button_size_classes("sm"), do: "px-2 py-1 text-xs gap-1"
  defp button_size_classes("md"), do: "px-3 py-2 text-sm gap-2"

  defp button_variant_classes("primary"), do: "bg-violet-600 text-white hover:bg-violet-700"
  defp button_variant_classes("secondary"), do: "bg-white border border-slate-200 text-slate-700 hover:bg-slate-50"
  defp button_variant_classes("ghost"), do: "text-slate-600 hover:text-slate-900 hover:bg-slate-100"
  defp button_variant_classes("danger"), do: "bg-red-600 text-white hover:bg-red-700"

  # Data table - dense, monospace data, hover rows
  attr :rows, :list, required: true
  attr :class, :string, default: ""
  slot :col, required: true do
    attr :label, :string, required: true
    attr :class, :string
    attr :mono, :boolean
  end

  def data_table(assigns) do
    ~H"""
    <div class="border border-slate-200 rounded-md overflow-hidden">
      <table class={"w-full text-sm #{@class}"}>
        <thead class="bg-slate-50 border-b border-slate-200">
          <tr>
            <th
              :for={col <- @col}
              class="px-4 py-3 text-left text-xs font-medium text-slate-500 uppercase tracking-wide"
            >
              {col.label}
            </th>
          </tr>
        </thead>
        <tbody class="divide-y divide-slate-100">
          <tr :for={row <- @rows} class="hover:bg-slate-50 transition-colors duration-150">
            <td
              :for={col <- @col}
              class={[
                "px-4 py-3 text-slate-700",
                col[:mono] && "font-mono text-xs tabular-nums",
                col[:class]
              ]}
            >
              {render_slot(col, row)}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  # Badge for tags - subtle, monospace
  attr :tags, :list, default: []
  attr :class, :string, default: ""

  def tag_badges(assigns) do
    ~H"""
    <div class={"flex flex-wrap gap-1 #{@class}"}>
      <span
        :for={tag <- @tags}
        class="inline-flex items-center px-2 py-0.5 rounded text-xs font-mono bg-slate-100 text-slate-600 border border-slate-200"
      >
        {tag}
      </span>
    </div>
    """
  end

  # ID display - monospace, muted
  attr :id, :string, required: true
  attr :class, :string, default: ""

  def id_badge(assigns) do
    ~H"""
    <span class={"font-mono text-xs text-slate-400 tabular-nums #{@class}"}>
      {String.slice(@id, 0, 8)}
    </span>
    """
  end

  # Timestamp - monospace, muted
  attr :datetime, :any, required: true
  attr :class, :string, default: ""

  def timestamp(assigns) do
    formatted = case assigns.datetime do
      %DateTime{} = dt -> Calendar.strftime(dt, "%Y-%m-%d %H:%M")
      %NaiveDateTime{} = dt -> Calendar.strftime(dt, "%Y-%m-%d %H:%M")
      _ -> "-"
    end
    assigns = assign(assigns, :formatted, formatted)

    ~H"""
    <time class={"font-mono text-xs text-slate-400 tabular-nums #{@class}"}>
      {@formatted}
    </time>
    """
  end

  # Markdown preview - prose styling constrained
  attr :content, :string, required: true
  attr :max_length, :integer, default: 200
  attr :class, :string, default: ""

  def markdown_preview(assigns) do
    ~H"""
    <div class={"text-sm text-slate-600 leading-relaxed #{@class}"}>
      {preview(@content, @max_length)}
    </div>
    """
  end

  # Full markdown render
  attr :content, :string, required: true
  attr :class, :string, default: ""

  def markdown(assigns) do
    ~H"""
    <div class={[
      "prose prose-slate prose-sm max-w-none",
      "prose-headings:font-semibold prose-headings:tracking-tight",
      "prose-code:font-mono prose-code:text-xs prose-code:bg-slate-100 prose-code:px-1 prose-code:rounded",
      "prose-pre:bg-slate-900 prose-pre:text-slate-100",
      @class
    ]}>
      {render(@content)}
    </div>
    """
  end

  # Empty state - centered, muted
  attr :title, :string, required: true
  attr :description, :string, default: nil
  slot :action

  def empty_state(assigns) do
    ~H"""
    <div class="text-center py-12 px-4">
      <h3 class="text-sm font-medium text-slate-500">{@title}</h3>
      <p :if={@description} class="text-xs text-slate-400 mt-1">{@description}</p>
      <div :if={@action != []} class="mt-4">
        {render_slot(@action)}
      </div>
    </div>
    """
  end

  # Stats row - compact, monospace values
  attr :stats, :list, required: true

  def stats_row(assigns) do
    ~H"""
    <div class="grid grid-cols-3 gap-4">
      <div
        :for={stat <- @stats}
        class="bg-white border border-slate-200 rounded-md p-4"
      >
        <div class="text-xs font-medium text-slate-500 uppercase tracking-wide">{stat.title}</div>
        <div class="text-2xl font-semibold text-slate-900 tabular-nums mt-1">{stat.value}</div>
        <div :if={stat[:desc]} class="text-xs text-slate-400 mt-1">{stat.desc}</div>
      </div>
    </div>
    """
  end

  # Modal - 8px radius (only exception), border
  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :on_cancel, JS, default: %JS{}
  attr :title, :string, default: nil
  slot :inner_block, required: true

  def modal(assigns) do
    ~H"""
    <div
      :if={@show}
      id={@id}
      class="fixed inset-0 z-50 flex items-center justify-center"
      phx-mounted={@show && JS.focus_first(to: "##{@id}-content")}
    >
      <!-- Backdrop -->
      <div
        class="absolute inset-0 bg-slate-900/50 transition-opacity duration-150"
        phx-click={@on_cancel}
      />
      <!-- Modal content -->
      <div
        id={"#{@id}-content"}
        class="relative bg-white border border-slate-200 rounded-lg shadow-lg w-full max-w-lg mx-4 p-6"
        role="dialog"
      >
        <h2 :if={@title} class="text-lg font-semibold text-slate-900 tracking-tight mb-4">
          {@title}
        </h2>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  # Form input - consistent with design system
  attr :field, Phoenix.HTML.FormField, required: true
  attr :type, :string, default: "text"
  attr :label, :string, required: true
  attr :class, :string, default: ""
  attr :rest, :global

  def input(assigns) do
    ~H"""
    <div class={@class}>
      <label class="block text-xs font-medium text-slate-600 mb-1">{@label}</label>
      <input
        type={@type}
        name={@field.name}
        id={@field.id}
        value={@field.value}
        class={[
          "w-full px-3 py-2 text-sm text-slate-900",
          "bg-white border border-slate-200 rounded",
          "focus:outline-none focus:ring-2 focus:ring-violet-500/20 focus:border-violet-500",
          "placeholder:text-slate-400"
        ]}
        {@rest}
      />
      <.field_error :for={msg <- @field.errors} message={msg} />
    </div>
    """
  end

  # Textarea with same styling
  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true
  attr :rows, :integer, default: 4
  attr :class, :string, default: ""
  attr :rest, :global

  def textarea(assigns) do
    ~H"""
    <div class={@class}>
      <label class="block text-xs font-medium text-slate-600 mb-1">{@label}</label>
      <textarea
        name={@field.name}
        id={@field.id}
        rows={@rows}
        class={[
          "w-full px-3 py-2 text-sm text-slate-900",
          "bg-white border border-slate-200 rounded",
          "focus:outline-none focus:ring-2 focus:ring-violet-500/20 focus:border-violet-500",
          "placeholder:text-slate-400 resize-none"
        ]}
        {@rest}
      >{@field.value}</textarea>
      <.field_error :for={msg <- @field.errors} message={msg} />
    </div>
    """
  end

  defp field_error(assigns) do
    ~H"""
    <p class="text-xs text-red-600 mt-1">{@message}</p>
    """
  end
end
```

---

## Phase 3: CRUD LiveViews

### 3.1 Home/Overview LiveView

```elixir
defmodule PopStashWeb.Dashboard.HomeLive do
  use PopStashWeb.Dashboard, :live_view
  
  alias PopStash.Projects
  alias PopStash.Memory

  def mount(_params, _session, socket) do
    projects = Projects.list()
    
    socket =
      socket
      |> assign(:projects, projects)
      |> assign(:selected_project, List.first(projects))
      |> load_stats()

    {:ok, socket}
  end

  defp load_stats(socket) do
    case socket.assigns.selected_project do
      nil ->
        assign(socket, :stats, [])

      project ->
        stats = [
          %{title: "Stashes", value: length(Memory.list_stashes(project.id))},
          %{title: "Insights", value: length(Memory.list_insights(project.id))},
          %{title: "Decisions", value: length(Memory.list_decisions(project.id))}
        ]
        assign(socket, :stats, stats)
    end
  end
end
```

### 3.2 Stash LiveViews

**Index:**
- List all stashes with preview (name, summary preview, tags, timestamps)
- Filter by project
- Search functionality
- New stash button → modal or dedicated page

**Show:**
- Full stash details with rendered markdown
- Edit button → modal form
- Delete button with confirmation

**Form Component:**
- Fields: name, summary (textarea), files (array input), tags (tag input), expires_at
- Live markdown preview panel

### 3.3 Insight LiveViews

**Index:**
- List insights with content preview
- Filter by project, tags
- New insight button

**Show:**
- Full insight with rendered markdown content
- Edit/delete actions

**Form Component:**
- Fields: key (optional), content (textarea with markdown preview), tags

### 3.4 Decision LiveViews

**Index:**
- List decisions grouped by topic
- Timeline view option
- Filter by project, topic

**Show:**
- Full decision details
- Show decision history for same topic
- Delete action (admin only, with warning)

**Form Component:**
- Fields: topic, decision (textarea), reasoning (textarea), tags
- Topic autocomplete from existing topics

---

## Phase 4: Real-time Updates

### 4.1 PubSub Integration

The `PopStash.Memory` context already broadcasts events. Subscribe in LiveViews:

```elixir
def mount(_params, _session, socket) do
  if connected?(socket) do
    Phoenix.PubSub.subscribe(PopStash.PubSub, "memory:events")
  end
  # ...
end

def handle_info({:stash_created, stash}, socket) do
  # Prepend to list if matches current project
  {:noreply, maybe_prepend(socket, :stashes, stash)}
end

def handle_info({:stash_updated, stash}, socket) do
  # Update in list
  {:noreply, update_in_list(socket, :stashes, stash)}
end

def handle_info({:stash_deleted, id}, socket) do
  # Remove from list
  {:noreply, remove_from_list(socket, :stashes, id)}
end
```

---

## Phase 5: Polish & UX

### 5.1 Features

- [ ] Dark/light theme toggle (DaisyUI theme controller)
- [ ] Keyboard shortcuts (⌘+N for new, etc.)
- [ ] Toast notifications for actions
- [ ] Confirmation modals for destructive actions
- [ ] Responsive design (mobile-friendly drawer)
- [ ] Loading skeletons during data fetch

### 5.2 Component Strategy

We use **custom components over DaisyUI defaults** to maintain design precision. DaisyUI provides utility classes but we override for our design direction:

| Element | Approach |
|---------|----------|
| Buttons | Custom `button` component with violet accent |
| Cards | Custom flat cards with `border-slate-200`, no shadow |
| Tables | Custom `data_table` with dense styling, hover states |
| Inputs | Custom styled inputs with violet focus ring |
| Badges | Custom monospace tags with subtle background |
| Modals | Custom with backdrop, 8px radius |
| Layout | DaisyUI `drawer` structure, custom colors |

**DaisyUI classes used selectively:**
- Layout utilities: `drawer`, `drawer-content`, `drawer-side`
- Prose: `prose prose-slate prose-sm` for markdown
- Transitions: Built-in transition utilities

**Tailwind classes for design system:**
- Colors: `slate-*`, `violet-600`, `violet-700`
- Spacing: `p-4`, `gap-2`, `mb-6` (4px grid)
- Typography: `text-sm`, `font-mono`, `tracking-tight`
- Borders: `border`, `border-slate-200`, `rounded-md`

---

## Implementation Order

### Week 1: Foundation
1. Add dependencies (earmark, html_sanitize_ex)
2. Create MarkdownScrubber module
3. Create Markdown helper module
4. Create Dashboard router macro
5. Create base layouts (root, dashboard)
6. Create DashboardComponents module

### Week 2: Stash CRUD
1. StashLive.Index - list with preview
2. StashLive.Show - full view with markdown
3. StashLive.FormComponent - create/edit
4. Wire up PubSub for real-time

### Week 3: Insight CRUD
1. InsightLive.Index
2. InsightLive.Show
3. InsightLive.FormComponent
4. Real-time updates

### Week 4: Decision CRUD
1. DecisionLive.Index (with topic grouping)
2. DecisionLive.Show (with history)
3. DecisionLive.FormComponent
4. Real-time updates

### Week 5: Polish
1. HomeLive overview with stats
2. Theme toggle
3. Toast notifications
4. Keyboard shortcuts
5. Mobile responsiveness testing
6. Documentation

---

## Security Considerations

⚠️ **The dashboard provides NO authentication by default.**

Users MUST secure the dashboard routes themselves:

```elixir
# Example: Basic auth
pipeline :admin_auth do
  plug :basic_auth, username: "admin", password: System.get_env("ADMIN_PASSWORD")
end

# Example: Session-based auth
pipeline :admin_auth do
  plug :require_admin_user
end

scope "/pop_stash" do
  pipe_through [:browser, :admin_auth]
  pop_stash_dashboard "/"
end
```

Document this prominently in README and module docs.

---

## File Checklist

- [ ] `lib/pop_stash_web/dashboard/router.ex`
- [ ] `lib/pop_stash_web/dashboard/markdown_scrubber.ex`
- [ ] `lib/pop_stash_web/dashboard/markdown.ex`
- [ ] `lib/pop_stash_web/dashboard/components/dashboard_components.ex`
- [ ] `lib/pop_stash_web/dashboard/components/layouts.ex`
- [ ] `lib/pop_stash_web/dashboard/live/home_live.ex`
- [ ] `lib/pop_stash_web/dashboard/live/stash_live/index.ex`
- [ ] `lib/pop_stash_web/dashboard/live/stash_live/show.ex`
- [ ] `lib/pop_stash_web/dashboard/live/stash_live/form_component.ex`
- [ ] `lib/pop_stash_web/dashboard/live/insight_live/index.ex`
- [ ] `lib/pop_stash_web/dashboard/live/insight_live/show.ex`
- [ ] `lib/pop_stash_web/dashboard/live/insight_live/form_component.ex`
- [ ] `lib/pop_stash_web/dashboard/live/decision_live/index.ex`
- [ ] `lib/pop_stash_web/dashboard/live/decision_live/show.ex`
- [ ] `lib/pop_stash_web/dashboard/live/decision_live/form_component.ex`

---

## Testing Strategy

- Unit tests for MarkdownScrubber (XSS prevention)
- Unit tests for Markdown helper
- LiveView tests for each CRUD operation
- Integration tests for real-time updates
