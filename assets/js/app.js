// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/pop_stash"
import topbar from "../vendor/topbar"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

// Alpine.js integration hook
const AlpineHook = {
  mounted() {
    if (window.Alpine) {
      window.Alpine.initTree(this.el)
    }
  },
  updated() {
    if (window.Alpine) {
      window.Alpine.initTree(this.el)
    }
  }
}

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, AlpineHook},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// Initialize Alpine.js when it's loaded
document.addEventListener('alpine:init', () => {
  console.log('Alpine initialized')
})

// Wait for Alpine to be available
if (window.Alpine) {
  window.Alpine.start()
} else {
  document.addEventListener('DOMContentLoaded', () => {
    if (window.Alpine) {
      window.Alpine.start()
    }
  })
}

// Handle LiveView DOM updates
window.addEventListener("phx:page-loading-stop", () => {
  if (window.Alpine) {
    window.Alpine.initTree(document.body)
  }
})

// Sidebar collapse functionality
function initSidebar() {
  const sidebar = document.getElementById('sidebar');
  const collapsed = localStorage.getItem('sidebarCollapsed') === 'true';
  
  if (sidebar) {
    updateSidebarState(sidebar, collapsed);
  }
}

function updateSidebarState(sidebar, collapsed) {
  if (collapsed) {
    sidebar.classList.remove('w-56');
    sidebar.classList.add('w-16');
    document.querySelectorAll('.sidebar-text, .sidebar-expanded').forEach(el => {
      el.style.display = 'none';
    });
  } else {
    sidebar.classList.remove('w-16');
    sidebar.classList.add('w-56');
    document.querySelectorAll('.sidebar-text, .sidebar-expanded').forEach(el => {
      el.style.display = '';
    });
  }
}

// Listen for sidebar toggle events
window.addEventListener('sidebar:toggle', () => {
  const sidebar = document.getElementById('sidebar');
  if (sidebar) {
    const isCollapsed = sidebar.classList.contains('w-16');
    const newState = !isCollapsed;
    localStorage.setItem('sidebarCollapsed', newState);
    updateSidebarState(sidebar, newState);
  }
});

// Initialize on DOM ready and after LiveView updates
document.addEventListener('DOMContentLoaded', initSidebar);
window.addEventListener('phx:page-loading-stop', initSidebar);

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

