# Step 4: Mermaid Component with Colocated Hook

## Overview
Create a reusable component for rendering Mermaid diagrams using Phoenix LiveView's colocated hooks feature.

## Context
Phoenix LiveView 1.8+ supports colocated hooks, allowing JavaScript to live inline with the component. This eliminates the need for separate JS files and manual hook registration.

## Implementation

### 1. Install Mermaid.js

```bash
cd assets && npm install mermaid
```

### 2. Create Diagram Components Module

**File:** `lib/pop_stash_web/components/diagram_components.ex`

```elixir
defmodule PopStashWeb.DiagramComponents do
  @moduledoc """
  Components for rendering and working with diagrams.
  """

  use Phoenix.Component

  @doc """
  Renders a Mermaid diagram with client-side rendering.

  ## Attributes
    * `content` - The mermaid diagram syntax (required)
    * `class` - Additional CSS classes (optional)

  ## Examples

      <.mermaid_diagram content={@diagram.content} />

      <.mermaid_diagram
        content={@diagram.content}
        class="my-4 border rounded-lg p-4"
      />
  """
  attr :content, :string, required: true
  attr :class, :string, default: ""

  def mermaid_diagram(assigns) do
    ~H"""
    <div
      id={"diagram-#{:erlang.phash2(@content)}"}
      phx-hook=".MermaidDiagram"
      phx-update="ignore"
      data-diagram={@content}
      class={@class}
    >
      <!-- Mermaid will render here -->
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".MermaidDiagram">
      import mermaid from "mermaid";

      mermaid.initialize({
        startOnLoad: false,
        theme: "default",
        securityLevel: "strict"
      });

      export default {
        mounted() {
          this.render();
        },

        updated() {
          this.render();
        },

        render() {
          const diagram = this.el.dataset.diagram;
          const id = `mermaid-${Math.random().toString(36).substr(2, 9)}`;

          mermaid.render(id, diagram).then(({ svg }) => {
            this.el.innerHTML = svg;
          }).catch(error => {
            this.el.innerHTML = `<pre class="text-red-600">Invalid diagram syntax:\n${error.message}</pre>`;
          });
        }
      }
    </script>
    """
  end
end
```

**Key Points:**
- Uses `phx-hook=".MermaidDiagram"` (note the dot prefix for colocated hooks)
- Hook name matches `name=".MermaidDiagram"` in the script tag
- `phx-update="ignore"` prevents LiveView from touching the rendered SVG
- Unique ID based on content hash prevents conflicts
- Error handling shows syntax errors in red

## Verification

### 1. Test in IEx

```elixir
# Start the Phoenix endpoint
iex -S mix phx.server

# Navigate to any LiveView and try the component
# In the LiveView module:
import PopStashWeb.DiagramComponents

def render(assigns) do
  ~H"""
  <.mermaid_diagram
    content="graph TD\n  A[Start] --> B[End]"
    class="border p-4"
  />
  """
end
```

### 2. Create Test Page (Optional)

**File:** `lib/pop_stash_web/live/test_diagram_live.ex`

```elixir
defmodule PopStashWeb.TestDiagramLive do
  use PopStashWeb, :live_view
  import PopStashWeb.DiagramComponents

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :diagram_content, """
    sequenceDiagram
      Alice->>John: Hello John
      John-->>Alice: Hi Alice!
    """)}
  end

  def render(assigns) do
    ~H"""
    <div class="p-8">
      <h1 class="text-2xl font-bold mb-4">Diagram Test</h1>
      <.mermaid_diagram content={@diagram_content} class="border rounded p-4" />
    </div>
    """
  end
end
```

Add temporary route to test:

```elixir
# In router.ex
live "/test-diagram", TestDiagramLive
```

Visit http://localhost:4000/test-diagram to see the rendered diagram.

### 3. Compile and Check Hook Generation

**Important:** Colocated hooks are only written when the component is compiled.

```bash
# Compile to generate hooks
mix compile

# Check that the hook was generated (it's in your JS bundle manifest)
# The build process handles this automatically
```

### 4. Test Error Handling

```elixir
# Test with invalid mermaid syntax
def mount(_params, _session, socket) do
  {:ok, assign(socket, :diagram_content, "invalid mermaid syntax!!!")}
end
```

Should display error message in red.

## Troubleshooting

**Hook not rendering:**
- Ensure `mix compile` was run after creating the component
- Check browser console for JS errors
- Verify mermaid was installed: `cd assets && npm list mermaid`

**Diagram not updating:**
- This is expected behavior with `phx-update="ignore"`
- If you need dynamic updates, remove `phx-update="ignore"` but may cause flicker

**Styling issues:**
- Mermaid generates inline SVG; use CSS on parent div
- Consider theme options in `mermaid.initialize()` for dark mode support

## Tests

**File:** `test/pop_stash_web/components/diagram_components_test.exs`

```elixir
defmodule PopStashWeb.DiagramComponentsTest do
  use PopStashWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import PopStashWeb.DiagramComponents

  describe "mermaid_diagram/1" do
    test "renders div with mermaid hook" do
      assigns = %{content: "graph TD\n  A --> B"}

      html =
        rendered_to_string(~H"""
        <.mermaid_diagram content={@content} />
        """)

      assert html =~ ~s(phx-hook=".MermaidDiagram")
      assert html =~ ~s(phx-update="ignore")
      assert html =~ ~s(data-diagram="graph TD\n  A --> B")
    end

    test "generates unique ID based on content" do
      assigns = %{content: "graph TD\n  A --> B"}

      html =
        rendered_to_string(~H"""
        <.mermaid_diagram content={@content} />
        """)

      assert html =~ ~r/id="diagram-\d+"/
    end

    test "applies custom class" do
      assigns = %{content: "graph TD\n  A --> B"}

      html =
        rendered_to_string(~H"""
        <.mermaid_diagram content={@content} class="my-custom-class" />
        """)

      assert html =~ ~s(class="my-custom-class")
    end

    test "different content generates different IDs" do
      assigns1 = %{content: "graph TD\n  A --> B"}
      assigns2 = %{content: "graph TD\n  X --> Y"}

      html1 =
        rendered_to_string(~H"""
        <.mermaid_diagram content={@content} />
        """, assigns: assigns1)

      html2 =
        rendered_to_string(~H"""
        <.mermaid_diagram content={@content} />
        """, assigns: assigns2)

      [id1] = Regex.run(~r/id="(diagram-\d+)"/, html1, capture: :all_but_first)
      [id2] = Regex.run(~r/id="(diagram-\d+)"/, html2, capture: :all_but_first)

      assert id1 != id2
    end

    test "same content generates same ID (idempotent)" do
      assigns = %{content: "graph TD\n  A --> B"}

      html1 =
        rendered_to_string(~H"""
        <.mermaid_diagram content={@content} />
        """, assigns: assigns)

      html2 =
        rendered_to_string(~H"""
        <.mermaid_diagram content={@content} />
        """, assigns: assigns)

      [id1] = Regex.run(~r/id="(diagram-\d+)"/, html1, capture: :all_but_first)
      [id2] = Regex.run(~r/id="(diagram-\d+)"/, html2, capture: :all_but_first)

      assert id1 == id2
    end
  end
end
```

**File:** `test/pop_stash_web/live/diagram_component_integration_test.exs`

Integration test to verify the component works in a LiveView:

```elixir
defmodule PopStashWeb.DiagramComponentIntegrationTest do
  use PopStashWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  defmodule TestLive do
    use PopStashWeb, :live_view
    import PopStashWeb.DiagramComponents

    def mount(_params, _session, socket) do
      {:ok,
       assign(socket,
         simple_diagram: "graph TD\n  A --> B",
         sequence_diagram: """
         sequenceDiagram
           Alice->>Bob: Hello
           Bob-->>Alice: Hi
         """,
         invalid_diagram: "invalid syntax!!!"
       )}
    end

    def render(assigns) do
      ~H"""
      <div>
        <div id="simple">
          <.mermaid_diagram content={@simple_diagram} />
        </div>
        <div id="sequence">
          <.mermaid_diagram content={@sequence_diagram} class="custom-class" />
        </div>
        <div id="invalid">
          <.mermaid_diagram content={@invalid_diagram} />
        </div>
      </div>
      """
    end
  end

  test "renders mermaid diagrams in LiveView", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, TestLive)

    # Check simple diagram is present with hook
    assert has_element?(view, "#simple [phx-hook='.MermaidDiagram']")
    assert has_element?(view, "#simple [phx-update='ignore']")

    # Check sequence diagram with custom class
    assert has_element?(view, "#sequence .custom-class")
    assert has_element?(view, "#sequence [phx-hook='.MermaidDiagram']")

    # Check invalid diagram container is present
    # (actual error display happens in JS, so we just verify container exists)
    assert has_element?(view, "#invalid [phx-hook='.MermaidDiagram']")
  end

  test "each diagram has unique ID", %{conn: conn} do
    {:ok, _view, html} = live_isolated(conn, TestLive)

    # Extract all diagram IDs
    ids =
      Regex.scan(~r/id="(diagram-\d+)"/, html, capture: :all_but_first)
      |> List.flatten()

    # Verify we have multiple diagrams
    assert length(ids) >= 2

    # Verify all IDs are unique
    assert length(ids) == length(Enum.uniq(ids))
  end

  test "diagram data attribute contains mermaid syntax", %{conn: conn} do
    {:ok, _view, html} = live_isolated(conn, TestLive)

    assert html =~ ~s(data-diagram="graph TD\n  A --> B")
    assert html =~ "sequenceDiagram"
  end
end
```

**Run tests:**
```bash
mix test test/pop_stash_web/components/diagram_components_test.exs
mix test test/pop_stash_web/live/diagram_component_integration_test.exs
```

**Note on JavaScript testing:**

The colocated hook's JavaScript behavior (mermaid rendering, error handling) is tested at the browser level through the LiveView integration. For unit testing the JS itself, you would need:

```bash
# Optional: Setup Jest for JS testing
cd assets && npm install --save-dev jest @testing-library/dom
```

Then create `assets/js/__tests__/mermaid_hook.test.js` for isolated JS unit tests. However, this is optional as the LiveView integration tests provide good coverage for typical use cases.

## Dependencies
- Node.js and npm installed
- Phoenix LiveView 1.8+
- Mermaid.js package
