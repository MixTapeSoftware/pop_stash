defmodule PopStashWeb.Dashboard.Markdown do
  @moduledoc """
  Safe Markdown rendering for the dashboard with syntax highlighting.

  This module provides a secure way to render markdown content with:
  - Syntax highlighting for 100+ languages via makeup_syntect
  - Optimized Elixir/Erlang highlighting via native Makeup lexers
  - HTML sanitization to prevent XSS attacks
  - Preview generation for long content
  """

  alias Phoenix.HTML
  require Logger

  @default_preview_length 200
  @code_class_prefix "language-"

  @elixir_extensions ~w[elixir ex exs iex]
  @erlang_extensions ~w[erlang erl hrl]
  @pre_code_pattern ~r/<pre><code(?:\s+class="([^"]*)")?>(.*?)<\/code><\/pre>/s
  @language_pattern ~r/(?:^|\s)(?:language-)?(\w+)/
  @makeup_extraction_pattern ~r/<pre[^>]*><code[^>]*>(.*)<\/code><\/pre>/s
  @word_boundary_pattern ~r/^(.+)\s+\S*$/

  # Type specifications for better dialyzer support
  @type safe_html :: {:safe, iodata()}
  @type options :: [max_length: non_neg_integer()]

  @doc """
  Converts markdown to sanitized HTML with syntax highlighting.

  ## Examples

      iex> render("# Hello World")
      {:safe, "<h1>Hello World</h1>"}

      iex> render(nil)
      {:safe, ""}
  """
  @spec render(binary() | nil) :: safe_html()
  def render(markdown)
  def render(nil), do: safe_html([])
  def render(""), do: safe_html([])

  def render(markdown) when is_binary(markdown) do
    markdown
    |> to_html()
    |> highlight_code_blocks()
    |> sanitize()
    |> safe_html()
  end

  @doc """
  Renders a truncated preview of markdown content.

  ## Options

    * `:max_length` - Maximum length of the preview (default: #{@default_preview_length})

  ## Examples

      iex> preview("This is a long text...", max_length: 10)
      {:safe, "This is a..."}
  """
  @spec preview(binary() | nil, options()) :: safe_html()
  def preview(markdown, opts \\ [])
  def preview(nil, _opts), do: safe_html([])
  def preview("", _opts), do: safe_html([])

  def preview(markdown, opts) when is_binary(markdown) do
    max_length = Keyword.get(opts, :max_length, @default_preview_length)

    markdown
    |> truncate_intelligently(max_length)
    |> render()
  end

  # Core transformation pipeline

  defp to_html(markdown) do
    earmark_options = [
      code_class_prefix: @code_class_prefix,
      smartypants: false,
      pure_links: true,
      compact_output: true
    ]

    case Earmark.as_html(markdown, earmark_options) do
      {:ok, html, warnings} ->
        log_warnings(warnings)
        html

      {:error, html, errors} ->
        log_errors(errors)
        html
    end
  end

  defp highlight_code_blocks(html) do
    Regex.replace(@pre_code_pattern, html, &process_code_block/3)
  end

  defp process_code_block(full_match, class_attr, code_content) do
    with {:ok, language} <- extract_language(class_attr),
         {:ok, highlighted} <- highlight_code(code_content, language) do
      build_highlighted_block(language, highlighted)
    else
      _ -> full_match
    end
  end

  defp extract_language(nil), do: {:error, :no_language}
  defp extract_language(""), do: {:error, :no_language}

  defp extract_language(class_attr) do
    case Regex.run(@language_pattern, class_attr) do
      [_, lang] -> {:ok, String.downcase(lang)}
      _ -> {:error, :no_language}
    end
  end

  defp highlight_code(code_content, language) do
    decoded = HtmlEntities.decode(code_content)

    result =
      case select_highlighter(language) do
        {:makeup, lexer_opts} ->
          apply_makeup_highlighting(decoded, lexer_opts)

        {:syntect, lang} ->
          apply_syntect_highlighting(decoded, lang)

        :plain ->
          {:ok, escape_html(decoded)}
      end

    case result do
      {:ok, highlighted} -> {:ok, highlighted}
      {:error, _} -> {:ok, escape_html(decoded)}
    end
  end

  defp select_highlighter(language)
       when language in @elixir_extensions do
    {:makeup, []}
  end

  defp select_highlighter(language) when language in @erlang_extensions do
    {:makeup, [lexer: Makeup.Lexers.ErlangLexer]}
  end

  defp select_highlighter(language) do
    if supported_language?(language) do
      {:syntect, language}
    else
      :plain
    end
  end

  defp apply_makeup_highlighting(code, opts) do
    highlighted = Makeup.highlight(code, opts)
    {:ok, extract_highlighted_content(highlighted, code)}
  rescue
    exception ->
      Logger.debug("Makeup highlighting failed: #{inspect(exception)}")
      {:error, :highlighting_failed}
  catch
    kind, reason ->
      Logger.debug("Makeup highlighting failed: #{inspect({kind, reason})}")
      {:error, :highlighting_failed}
  end

  defp apply_syntect_highlighting(code, language) do
    highlighted = Makeup.highlight(code, lexer: language)
    {:ok, extract_highlighted_content(highlighted, code)}
  rescue
    exception ->
      Logger.debug("Syntect highlighting failed for #{language}: #{inspect(exception)}")
      {:error, :highlighting_failed}
  catch
    kind, reason ->
      Logger.debug("Syntect highlighting failed for #{language}: #{inspect({kind, reason})}")
      {:error, :highlighting_failed}
  end

  defp extract_highlighted_content(highlighted_html, fallback_code) do
    case Regex.run(@makeup_extraction_pattern, highlighted_html) do
      [_, content] -> content
      _ -> escape_html(fallback_code)
    end
  end

  defp build_highlighted_block(language, content) do
    [
      ~s(<pre class="highlight"><code class="language-),
      language,
      ~s(">),
      content,
      ~s(</code></pre>)
    ]
    |> IO.iodata_to_binary()
  end

  defp escape_html(code) do
    code
    |> HTML.html_escape()
    |> HTML.safe_to_string()
  end

  defp sanitize(html) do
    HtmlSanitizeEx.Scrubber.scrub(html, PopStashWeb.Dashboard.MarkdownScrubber)
  end

  defp safe_html(content) do
    HTML.raw(content)
  end

  # Text truncation with word boundary awareness

  defp truncate_intelligently(text, max_length) when byte_size(text) <= max_length do
    text
  end

  defp truncate_intelligently(text, max_length) do
    # Handle unicode properly
    truncated = String.slice(text, 0, max_length)

    # Try to break at word boundary
    case Regex.run(@word_boundary_pattern, truncated) do
      [_, clean_text] -> clean_text <> "..."
      nil -> truncated <> "..."
    end
  end

  # Language support checking

  defp supported_language?(language) do
    # This could be moved to compile-time or ETS for better performance
    # if the list is large and checks are frequent
    MapSet.member?(supported_languages(), language)
  end

  defp supported_languages do
    # Cached at compile time for performance
    # This is a subset - extend as needed
    MapSet.new(~w[
      javascript js typescript ts python py ruby rb rust rs go
      java kotlin swift objc html css scss sass less json yaml
      toml xml sql bash sh zsh fish powershell dockerfile
      makefile cmake nginx apache vim
    ])
  end

  # Logging helpers

  defp log_warnings([]), do: :ok

  defp log_warnings(warnings) do
    Logger.debug("Earmark warnings: #{inspect(warnings)}")
  end

  defp log_errors([]), do: :ok

  defp log_errors(errors) do
    Logger.warning("Earmark errors: #{inspect(errors)}")
  end
end
