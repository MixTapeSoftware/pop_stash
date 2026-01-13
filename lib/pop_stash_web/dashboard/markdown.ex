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
  def preview(markdown, max_length \\ 200)
  def preview(nil, _max_length), do: {:safe, ""}
  def preview("", _max_length), do: {:safe, ""}

  def preview(markdown, max_length) when is_binary(markdown) do
    markdown
    |> String.slice(0, max_length)
    |> then(fn text ->
      if String.length(markdown) > max_length do
        text <> "..."
      else
        text
      end
    end)
    |> render()
  end
end
