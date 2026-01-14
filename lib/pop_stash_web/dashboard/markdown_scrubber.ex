defmodule PopStashWeb.Dashboard.MarkdownScrubber do
  @moduledoc """
  Allows basic HTML tags for Markdown rendering.
  Does not allow scripts, styles, or dangerous elements.
  """

  require HtmlSanitizeEx.Scrubber.Meta
  alias HtmlSanitizeEx.Scrubber.Meta

  @valid_schemes ["http", "https", "mailto"]

  Meta.remove_cdata_sections_before_scrub()
  Meta.strip_comments()

  # Text formatting
  Meta.allow_tag_with_these_attributes("b", [])
  Meta.allow_tag_with_these_attributes("strong", [])
  Meta.allow_tag_with_these_attributes("i", [])
  Meta.allow_tag_with_these_attributes("em", [])
  Meta.allow_tag_with_these_attributes("u", [])
  Meta.allow_tag_with_these_attributes("del", [])
  Meta.allow_tag_with_these_attributes("span", ["class"])

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
  Meta.allow_tag_with_these_attributes("pre", ["class"])
  Meta.allow_tag_with_these_attributes("code", ["class"])
  Meta.allow_tag_with_these_attributes("hr", [])
  Meta.allow_tag_with_these_attributes("div", [])

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

  # Links - custom scrub function to validate href
  def scrub({"a", attributes, children}) do
    href = get_attribute(attributes, "href")

    if valid_href?(href) do
      {"a", [{"href", href}], children}
    else
      # Strip the tag but keep the content
      nil
    end
  end

  # Allow other covered tags through
  Meta.strip_everything_not_covered()

  defp get_attribute(attributes, name) do
    case List.keyfind(attributes, name, 0) do
      {^name, value} -> value
      _ -> nil
    end
  end

  defp valid_href?(nil), do: false

  defp valid_href?(href) do
    uri = URI.parse(href)
    uri.scheme in @valid_schemes
  end
end
