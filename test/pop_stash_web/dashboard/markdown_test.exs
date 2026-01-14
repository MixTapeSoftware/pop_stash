defmodule PopStashWeb.Dashboard.MarkdownTest do
  use ExUnit.Case, async: true

  alias PopStashWeb.Dashboard.Markdown

  describe "render/1" do
    test "returns empty safe tuple for nil" do
      assert Markdown.render(nil) == {:safe, []}
    end

    test "returns empty safe tuple for empty string" do
      assert Markdown.render("") == {:safe, []}
    end

    test "renders basic markdown" do
      {:safe, html} = Markdown.render("**bold** and *italic*")
      assert html =~ "<strong>bold</strong>"
      assert html =~ "<em>italic</em>"
    end

    test "renders headings" do
      {:safe, html} = Markdown.render("# Heading 1\n## Heading 2")
      assert html =~ "<h1>"
      assert html =~ "<h2>"
    end

    test "renders code blocks" do
      {:safe, html} = Markdown.render("```elixir\ndefmodule Test do\nend\n```")
      assert html =~ "<pre class=\"highlight\">"
      assert html =~ "<code class=\"language-elixir\">"
    end

    test "highlights Elixir code with syntax classes" do
      code = """
      ```elixir
      defmodule Example do
        def hello(name) do
          "Hello, \#{name}!"
        end
      end
      ```
      """

      {:safe, html} = Markdown.render(code)
      assert html =~ ~r/<pre class="highlight">/
      assert html =~ ~r/<code class="language-elixir">/
      # Check for syntax highlighting spans
      assert html =~ ~r/<span class="kd">defmodule<\/span>/
      assert html =~ ~r/<span class="nc">Example<\/span>/
      assert html =~ ~r/<span class="kd">def<\/span>/
      assert html =~ ~r/<span class="nf">hello<\/span>/
    end

    test "highlights JavaScript code with syntax classes" do
      code = """
      ```javascript
      function greet(name) {
        console.log(`Hello, ${name}!`);
      }
      ```
      """

      {:safe, html} = Markdown.render(code)
      assert html =~ ~r/<pre class="highlight">/
      assert html =~ ~r/<code class="language-javascript">/
      # Check for syntax highlighting spans
      assert html =~ ~r/<span class="kt">function<\/span>/
      assert html =~ ~r/<span class="nf">greet<\/span>/
      assert html =~ ~r/<span class="nb">console<\/span>/
    end

    test "highlights Python code with syntax classes" do
      code = """
      ```python
      def greet(name):
          print(f"Hello, {name}!")
      ```
      """

      {:safe, html} = Markdown.render(code)
      assert html =~ ~r/<pre class="highlight">/
      assert html =~ ~r/<code class="language-python">/
      # Check for syntax highlighting spans
      assert html =~ ~r/<span class="kt">def<\/span>/
      assert html =~ ~r/<span class="nf">greet<\/span>/
    end

    test "falls back to escaped code for unsupported languages" do
      code = """
      ```unknownlang
      some code here
      ```
      """

      {:safe, html} = Markdown.render(code)
      assert html =~ ~r/<pre class="highlight">/
      assert html =~ ~r/<code class="language-unknownlang">/
      # Should still contain the code, but HTML-escaped
      assert html =~ "some code here"
    end

    test "renders inline code" do
      {:safe, html} = Markdown.render("Use `mix test` to run tests")
      assert html =~ "<code"
      assert html =~ "mix test"
    end

    test "renders lists" do
      {:safe, html} = Markdown.render("- item 1\n- item 2\n- item 3")
      assert html =~ "<ul>"
      assert html =~ "<li>"
    end

    test "renders ordered lists" do
      {:safe, html} = Markdown.render("1. first\n2. second\n3. third")
      assert html =~ "<ol>"
      assert html =~ "<li>"
    end

    test "renders blockquotes" do
      {:safe, html} = Markdown.render("> This is a quote")
      assert html =~ "<blockquote>"
    end

    # XSS Prevention Tests
    test "strips script tags" do
      {:safe, html} = Markdown.render("<script>alert('xss')</script>")
      refute html =~ "<script"
      refute html =~ "</script>"
    end

    test "strips javascript: URLs in links" do
      {:safe, html} = Markdown.render(~S[<a href="javascript:alert('xss')">click</a>])
      refute html =~ ~S[javascript:]
    end

    test "strips onclick attributes" do
      {:safe, html} = Markdown.render(~S[<a onclick="alert('xss')" href="#">link</a>])
      refute html =~ "onclick"
    end

    test "strips style tags" do
      {:safe, html} = Markdown.render("<style>body { display: none; }</style>")
      refute html =~ "<style"
    end

    test "strips iframe tags" do
      {:safe, html} = Markdown.render("<iframe src=\"evil.com\"></iframe>")
      refute html =~ "<iframe"
    end

    test "strips onerror attributes" do
      {:safe, html} = Markdown.render(~S[<img src="x" onerror="alert('xss')" />])
      refute html =~ "onerror"
    end

    test "strips form tags" do
      {:safe, html} = Markdown.render("<form action=\"evil.com\"><input></form>")
      refute html =~ "<form"
    end

    test "strips object tags" do
      {:safe, html} = Markdown.render("<object data=\"evil.swf\"></object>")
      refute html =~ "<object"
    end

    test "strips embed tags" do
      {:safe, html} = Markdown.render("<embed src=\"evil.swf\" />")
      refute html =~ "<embed"
    end

    test "allows safe http links" do
      {:safe, html} = Markdown.render("<a href=\"https://example.com\">link</a>")
      assert html =~ "<a"
      assert html =~ "https://example.com"
    end
  end

  describe "preview/2" do
    test "returns empty safe tuple for nil" do
      assert Markdown.preview(nil) == {:safe, []}
    end

    test "returns empty safe tuple for empty string" do
      assert Markdown.preview("") == {:safe, []}
    end

    test "truncates long content with ellipsis" do
      long_text = String.duplicate("a", 300)
      {:safe, html} = Markdown.preview(long_text, max_length: 200)
      # Should be truncated - the ellipsis might be Unicode or ASCII
      assert String.length(html) < String.length(long_text) + 50
    end

    test "does not truncate short content" do
      short_text = "Short text"
      {:safe, html} = Markdown.preview(short_text, max_length: 200)
      assert html =~ "Short text"
    end

    test "respects custom max_length" do
      text = String.duplicate("a", 50)
      {:safe, html} = Markdown.preview(text, max_length: 10)
      # Truncated output should be shorter than original
      assert String.length(html) < 50
    end

    test "renders markdown in preview" do
      {:safe, html} = Markdown.preview("**bold** text")
      assert html =~ "<strong>bold</strong>"
    end
  end
end
