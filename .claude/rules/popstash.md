## Memory & Context Management (PopStash)

You have access to PopStash, a persistent memory system via MCP. Use it to maintain
context across sessions and preserve important knowledge about this codebase.

### When to Use Each Tool

**`save_context` / `restore_context` - Working Context**
- SAVE_CONTEXT when: switching tasks, context is getting long, before exploring tangents, pausing work
- RESTORE_CONTEXT when: resuming work, need previous context, starting a related task
- Use short descriptive names like "auth-refactor", "bug-123-investigation"
- Optionally include files and tags for better organization

**`insight` / `recall` - Persistent Knowledge**
- INSIGHT when: you discover something non-obvious about the codebase, learn how
  components interact, find undocumented behavior, identify patterns or conventions
- RECALL when: starting work in an unfamiliar area, before making architectural
  changes, when something "should work" but doesn't
- Good insights: "The auth middleware silently converts guest users to anonymous
  sessions", "API rate limits reset at UTC midnight, not rolling 24h"
- Use hierarchical keys like "auth/session-handling" or "api/rate-limits"

**`decide` / `get_decisions` - Architectural Decisions**
- DECIDE when: making or encountering significant technical choices, choosing between
  approaches, establishing patterns for the codebase
- GET_DECISIONS when: about to make changes in an area, wondering "why is it done
  this way?", onboarding to a new part of the codebase
- Decisions are immutable and version-tracked - new decisions on the same topic preserve history

**`save_plan` / `get_plan` / `search_plans` - Plans & Architecture**
- SAVE_PLAN when: creating project roadmaps, documenting architecture, planning major features
- Use version numbers for iterations (e.g., "v1.0", "v2.0", "draft", "final")
- GET_PLAN when: need to reference existing plans, want latest version of a plan, list all plan versions
- SEARCH_PLANS when: looking for plans by semantic content across all plans

### Best Practices

1. **Be proactive**: Don't wait to be asked. Save context before it's lost.
2. **Search first**: Before diving into unfamiliar code, use recall/get_decisions/get_plan for that area.
3. **Atomic insights**: One concept per insight. Easier to find and stays relevant.
4. **Descriptive naming**: Use clear names for contexts and keys that describe the content.
5. **Link to code**: Reference specific files/functions when documenting decisions and insights.
6. **Use semantic search**: All tools support natural language queries - use them!
7. **Version your plans**: Plans support versioning - use it to track evolution of ideas.
8. **Tag for organization**: Use tags on contexts, insights, decisions, and plans for better discoverability.

### Tool Details

**save_context**
- Parameters: name (required), summary (required), files (optional array), tags (optional array)
- Example: `save_context(name: "auth-refactor-wip", summary: "Refactoring authentication middleware", files: ["lib/middleware/auth.ex"], tags: ["auth", "refactor"])`

**restore_context**
- Parameters: name (required - exact or semantic query), limit (optional, default: 5)
- Returns ranked results with exact matches prioritized
- **Note:** Semantic search (natural language queries) requires embeddings to be enabled and ready. Always use exact context names (e.g., "auth-refactor") if you get `:embeddings_not_ready` errors.
- Example: `restore_context(name: "auth-refactor")` (exact) or `restore_context(name: "authentication work")` (semantic)

**insight**
- Parameters: content (required), key (optional), tags (optional array)
- Example: `insight(content: "Rate limits reset at UTC midnight", key: "api/rate-limits", tags: ["api", "limits"])`

**recall**
- Parameters: key (required - exact or semantic query), limit (optional, default: 5)
- Returns ranked results with exact matches prioritized
- **Note:** Semantic search requires embeddings. Use exact keys if embeddings are unavailable.
- Example: `recall(key: "api/rate-limits")` (exact) or `recall(key: "rate limiting behavior")` (semantic)

**decide**
- Parameters: topic (required), decision (required), reasoning (optional), tags (optional array)
- Example: `decide(topic: "auth-method", decision: "Use JWT with refresh tokens", reasoning: "...", tags: ["auth", "security"])`

**get_decisions**
- Parameters: topic (optional), limit (optional, default: 10), list_topics (optional boolean)
- Modes: exact topic match, semantic search, or list all topics
- Example: `get_decisions(topic: "auth-method")` or `get_decisions(list_topics: true)`

**save_plan**
- Parameters: title (required), version (required), body (required), tags (optional array)
- Note: title + version combination must be unique
- Example: `save_plan(title: "V2 Architecture", version: "v1.0", body: "...", tags: ["architecture"])`

**get_plan**
- Parameters: title (optional), version (optional), all_versions (boolean), list_titles (boolean), limit (optional, default: 10)
- Modes: list titles, get specific version, get latest version, get all versions, list recent plans
- Example: `get_plan(title: "V2 Architecture", version: "v1.0")` or `get_plan(list_titles: true)`

**search_plans**
- Parameters: query (required - natural language), limit (optional, default: 10)
- Returns ranked results with content previews
- **Note:** Requires embeddings to be enabled and ready.
- Example: `search_plans(query: "database migration strategy")`

### Important Notes

**Semantic Search Availability:**
- Tools like `restore_context`, `recall`, `get_decisions`, and `search_plans` support both exact matching and semantic search
- Semantic search uses natural language queries (e.g., "authentication work", "rate limiting behavior")
- **Exact matching always works** - use exact names/keys when available (e.g., "auth-refactor", "api/rate-limits")
- If you encounter `:embeddings_not_ready` errors, fall back to exact name/key matching
- Semantic search requires the embedding service to be running, which may take time to initialize on first startup
