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
  import PopStashWeb.CoreComponents, only: [icon: 1]

  alias Phoenix.LiveView.JS

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
      "p-4",
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
  attr :rest, :global, include: ~w(disabled phx-click phx-target navigate patch href)
  slot :inner_block, required: true

  def button(assigns) do
    ~H"""
    <button
      type={@type}
      class={[
        "inline-flex items-center justify-center font-medium rounded transition-colors duration-150",
        "disabled:opacity-50 disabled:cursor-not-allowed",
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

  defp button_variant_classes("secondary"),
    do: "bg-white border border-slate-200 text-slate-700 hover:bg-slate-50"

  defp button_variant_classes("ghost"),
    do: "text-slate-600 hover:text-slate-900 hover:bg-slate-100"

  defp button_variant_classes("danger"), do: "bg-red-600 text-white hover:bg-red-700"

  # Link button - wraps Phoenix.Component.link with button styling
  attr :variant, :string, default: "primary", values: ["primary", "secondary", "ghost", "danger"]
  attr :size, :string, default: "md", values: ["sm", "md"]
  attr :class, :string, default: ""
  attr :rest, :global, include: ~w(navigate patch href method)
  slot :inner_block, required: true

  def link_button(assigns) do
    ~H"""
    <.link
      class={[
        "inline-flex items-center justify-center font-medium rounded transition-colors duration-150",
        button_size_classes(@size),
        button_variant_classes(@variant),
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  # Data table - dense, monospace data, hover rows
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil
  attr :row_click, :any, default: nil
  attr :class, :string, default: ""

  slot :col, required: true do
    attr :label, :string, required: true
    attr :class, :string
    attr :mono, :boolean
  end

  def data_table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

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
        <tbody
          id={@id}
          phx-update={match?(%Phoenix.LiveView.LiveStream{}, @rows) && "stream"}
          class="divide-y divide-slate-100"
        >
          <tr
            :for={row <- @rows}
            id={@row_id && @row_id.(row)}
            class={[
              "hover:bg-slate-50 transition-colors duration-150",
              @row_click && "cursor-pointer"
            ]}
            phx-click={@row_click && @row_click.(row)}
          >
            <td
              :for={col <- @col}
              class={[
                "px-4 py-3 text-slate-700",
                col[:mono] && "font-mono text-xs tabular-nums",
                col[:class]
              ]}
            >
              {render_slot(col, extract_row_item(row))}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp extract_row_item({_id, item}), do: item
  defp extract_row_item(item), do: item

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
    formatted =
      case assigns.datetime do
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
      {preview(@content, max_length: @max_length)}
    </div>
    """
  end

  # Full markdown render
  attr :content, :string, required: true
  attr :class, :string, default: ""

  def markdown(assigns) do
    ~H"""
    <div class={[
      "markdown-content",
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
    <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
      <div :for={stat <- @stats}>
        <%= if stat[:link] do %>
          <.link
            navigate={stat.link}
            class="block bg-white border border-slate-200 rounded-md p-4 hover:border-violet-300 hover:shadow-sm transition-all cursor-pointer group"
          >
            <div class="text-xs font-medium text-slate-500 uppercase tracking-wide group-hover:text-violet-600 transition-colors">
              {stat.title}
            </div>
            <div class="text-2xl font-semibold text-slate-900 tabular-nums mt-1 group-hover:text-violet-700 transition-colors">
              {stat.value}
            </div>
            <div :if={stat[:desc]} class="text-xs text-slate-400 mt-1">{stat.desc}</div>
          </.link>
        <% else %>
          <div class="bg-white border border-slate-200 rounded-md p-4">
            <div class="text-xs font-medium text-slate-500 uppercase tracking-wide">{stat.title}</div>
            <div class="text-2xl font-semibold text-slate-900 tabular-nums mt-1">{stat.value}</div>
            <div :if={stat[:desc]} class="text-xs text-slate-400 mt-1">{stat.desc}</div>
          </div>
        <% end %>
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
      phx-mounted={JS.focus_first(to: "##{@id}-content")}
    >
      <!-- Backdrop -->
      <div
        class="absolute inset-0 bg-slate-900/50 transition-opacity duration-150"
        phx-click={@on_cancel}
      />
      <!-- Modal content -->
      <div
        id={"#{@id}-content"}
        class="relative bg-white border border-slate-200 rounded-lg w-full max-w-lg mx-4 p-6"
        role="dialog"
      >
        <div :if={@title} class="flex items-center justify-between mb-4">
          <h2 class="text-lg font-semibold text-slate-900 tracking-tight">
            {@title}
          </h2>
          <button
            type="button"
            class="p-1 text-slate-400 hover:text-slate-600 rounded transition-colors"
            phx-click={@on_cancel}
          >
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  # Form input - consistent with design system
  attr :field, Phoenix.HTML.FormField, required: true
  attr :type, :string, default: "text"
  attr :label, :string, required: true
  attr :placeholder, :string, default: nil
  attr :class, :string, default: ""
  attr :rest, :global

  def input(assigns) do
    ~H"""
    <div class={@class}>
      <label for={@field.id} class="block text-xs font-medium text-slate-600 mb-1">{@label}</label>
      <input
        type={@type}
        name={@field.name}
        id={@field.id}
        value={Phoenix.HTML.Form.normalize_value(@type, @field.value)}
        placeholder={@placeholder}
        class={[
          "w-full px-3 py-2 text-sm text-slate-900",
          "bg-white border border-slate-200 rounded",
          "focus:outline-none focus:ring-2 focus:ring-violet-500/20 focus:border-violet-500",
          "placeholder:text-slate-400",
          @field.errors != [] && "border-red-300 focus:border-red-500 focus:ring-red-500/20"
        ]}
        {@rest}
      />
      <.field_errors errors={@field.errors} />
    </div>
    """
  end

  # Textarea with same styling
  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true
  attr :rows, :integer, default: 4
  attr :placeholder, :string, default: nil
  attr :class, :string, default: ""
  attr :rest, :global

  def textarea(assigns) do
    ~H"""
    <div class={@class}>
      <label for={@field.id} class="block text-xs font-medium text-slate-600 mb-1">{@label}</label>
      <textarea
        name={@field.name}
        id={@field.id}
        rows={@rows}
        placeholder={@placeholder}
        class={[
          "w-full px-3 py-2 text-sm text-slate-900",
          "bg-white border border-slate-200 rounded",
          "focus:outline-none focus:ring-2 focus:ring-violet-500/20 focus:border-violet-500",
          "placeholder:text-slate-400 resize-none",
          @field.errors != [] && "border-red-300 focus:border-red-500 focus:ring-red-500/20"
        ]}
        {@rest}
      >{Phoenix.HTML.Form.normalize_value("textarea", @field.value)}</textarea>
      <.field_errors errors={@field.errors} />
    </div>
    """
  end

  # Select input
  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true
  attr :options, :list, required: true
  attr :prompt, :string, default: nil
  attr :class, :string, default: ""
  attr :rest, :global

  def select(assigns) do
    ~H"""
    <div class={@class}>
      <label for={@field.id} class="block text-xs font-medium text-slate-600 mb-1">{@label}</label>
      <select
        name={@field.name}
        id={@field.id}
        class={[
          "w-full px-3 py-2 text-sm text-slate-900",
          "bg-white border border-slate-200 rounded",
          "focus:outline-none focus:ring-2 focus:ring-violet-500/20 focus:border-violet-500",
          @field.errors != [] && "border-red-300 focus:border-red-500 focus:ring-red-500/20"
        ]}
        {@rest}
      >
        <option :if={@prompt} value="">{@prompt}</option>
        {Phoenix.HTML.Form.options_for_select(@options, @field.value)}
      </select>
      <.field_errors errors={@field.errors} />
    </div>
    """
  end

  # Tag input (comma-separated)
  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true
  attr :placeholder, :string, default: "tag1, tag2, tag3"
  attr :class, :string, default: ""
  attr :rest, :global

  def tag_input(assigns) do
    value =
      case assigns.field.value do
        nil -> ""
        list when is_list(list) -> Enum.join(list, ", ")
        str when is_binary(str) -> str
      end

    assigns = assign(assigns, :display_value, value)

    ~H"""
    <div class={@class}>
      <label for={@field.id} class="block text-xs font-medium text-slate-600 mb-1">{@label}</label>
      <input
        type="text"
        name={@field.name}
        id={@field.id}
        value={@display_value}
        placeholder={@placeholder}
        class={[
          "w-full px-3 py-2 text-sm text-slate-900 font-mono",
          "bg-white border border-slate-200 rounded",
          "focus:outline-none focus:ring-2 focus:ring-violet-500/20 focus:border-violet-500",
          "placeholder:text-slate-400"
        ]}
        {@rest}
      />
      <p class="text-xs text-slate-400 mt-1">Separate tags with commas</p>
      <.field_errors errors={@field.errors} />
    </div>
    """
  end

  defp field_errors(assigns) do
    ~H"""
    <p :for={error <- @errors} class="text-xs text-red-600 mt-1">
      {translate_error(error)}
    </p>
    """
  end

  defp translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", fn _ -> to_string(value) end)
    end)
  end

  # Back link
  attr :navigate, :string, required: true
  attr :label, :string, default: "Back"

  def back_link(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class="inline-flex items-center gap-1 text-sm text-slate-500 hover:text-slate-700 transition-colors"
    >
      <.icon name="hero-arrow-left" class="size-4" />
      {@label}
    </.link>
    """
  end

  # Confirmation dialog
  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :message, :string, required: true
  attr :confirm_label, :string, default: "Confirm"
  attr :cancel_label, :string, default: "Cancel"
  attr :on_confirm, JS, required: true
  attr :on_cancel, JS, default: %JS{}
  attr :variant, :string, default: "danger", values: ["primary", "danger"]

  def confirm_dialog(assigns) do
    ~H"""
    <.modal id={@id} show={true} on_cancel={@on_cancel} title={@title}>
      <p class="text-sm text-slate-600 mb-6">{@message}</p>
      <div class="flex justify-end gap-2">
        <.button variant="secondary" phx-click={@on_cancel}>
          {@cancel_label}
        </.button>
        <.button variant={@variant} phx-click={@on_confirm}>
          {@confirm_label}
        </.button>
      </div>
    </.modal>
    """
  end

  # Section header
  attr :title, :string, required: true
  attr :class, :string, default: ""
  slot :actions

  def section_header(assigns) do
    ~H"""
    <div class={["flex items-center justify-between mb-4", @class]}>
      <h2 class="text-lg font-semibold text-slate-900 tracking-tight">{@title}</h2>
      <div :if={@actions != []} class="flex items-center gap-2">
        {render_slot(@actions)}
      </div>
    </div>
    """
  end

  # Detail row for show pages
  attr :label, :string, required: true
  attr :class, :string, default: ""
  slot :inner_block, required: true

  def detail_row(assigns) do
    ~H"""
    <div class={["py-3 border-b border-slate-100 last:border-0", @class]}>
      <dt class="text-xs font-medium text-slate-500 uppercase tracking-wide mb-1">{@label}</dt>
      <dd class="text-sm text-slate-900">
        {render_slot(@inner_block)}
      </dd>
    </div>
    """
  end

  # Loading spinner
  attr :class, :string, default: ""

  def spinner(assigns) do
    ~H"""
    <svg
      class={["animate-spin size-5 text-violet-600", @class]}
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
    >
      <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
      <path
        class="opacity-75"
        fill="currentColor"
        d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
      />
    </svg>
    """
  end
end
