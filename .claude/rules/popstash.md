## Memory & Context Management (PopStash)

You have access to PopStash, a persistent memory system via MCP. Use it to maintain
context across sessions and preserve important knowledge about this codebase.

### Core Concept: Thread Identity

All PopStash records are **immutable**—you never edit existing entries. Instead, you create new versions. The `thread_id` field connects related records across revisions:

- **Same `thread_id`** = same logical entity, different versions (use timestamps to determine latest)
- **When revising**: Pass back the `thread_id` from the record you're updating
- **When creating new**: Omit `thread_id`—the system generates one automatically

You don't invent thread IDs. You either omit them (new thread) or echo back one you received (continuing a thread).

### When to Use Each Tool

**`save_context` / `restore_context` - Working Context**
- SAVE_CONTEXT when: switching tasks, context is getting long, before exploring tangents, pausing work
- RESTORE_CONTEXT when: resuming work, need previous context, starting a related task
- Use short descriptive names like "auth-refactor", "bug-123-investigation"
- Optionally include files and tags for organization
- Pass `thread_id` when saving a new snapshot of an ongoing work stream

**`insight` / `recall` - Persistent Knowledge**
- INSIGHT when: you discover something non-obvious about the codebase, learn how
  components interact, find undocumented behavior, identify patterns or conventions
- RECALL when: starting work in an unfamiliar area, before making architectural
  changes, when something "should work" but doesn't
- Good insights: "The auth middleware silently converts guest users to anonymous
  sessions", "API rate limits reset at UTC midnight, not rolling 24h"
- Use hierarchical keys like "auth/session-handling" or "api/rate-limits"
- Pass `thread_id` when refining or correcting a previous insight

**`decide` / `get_decisions` - Architectural Decisions**
- DECIDE when: making or encountering significant technical choices, choosing between
  approaches, establishing patterns for the codebase
- GET_DECISIONS when: about to make changes in an area, wondering "why is it done
  this way?", onboarding to a new part of the codebase
- Pass `thread_id` from a previous decision when recording a revision to that decision

**`save_plan` / `get_plan` / `search_plans` - Plans & Architecture**
- SAVE_PLAN when: creating project roadmaps, documenting architecture, planning major features
- GET_PLAN when: need to reference existing plans, check latest version, list all versions
- SEARCH_PLANS when: looking for plans by semantic content
- Pass `thread_id` when saving a new version of an existing plan

### Best Practices

1. **Be proactive**: Don't wait to be asked. Save context before it's lost.
2. **Search first**: Before diving into unfamiliar code, use recall/get_decisions/get_plan.
3. **Atomic insights**: One concept per insight. Easier to find and stays relevant.
4. **Descriptive naming**: Use clear names and keys that describe the content.
5. **Link to code**: Reference specific files/functions in decisions and insights.
6. **Use semantic search**: All tools support natural language queries—use them!
7. **Preserve threads**: When revising, always pass back the `thread_id` you received.

### Tool Details

**save_context**
- Parameters: name (required), summary (required), files (optional array), tags (optional array), thread_id (optional)
- Example: `save_context(name: "auth-refactor-wip", summary: "Refactoring auth middleware", files: ["lib/middleware/auth.ex"], tags: ["auth"])`
- Example (revision): `save_context(name: "auth-refactor-wip", summary: "Completed token validation", thread_id: "cthr_k8f2m9x1p4qz")`

**restore_context**
- Parameters: name (required - exact or semantic query), limit (optional, default: 5)
- Returns ranked results with exact matches prioritized; includes `thread_id` for each result
- Example: `restore_context(name: "auth-refactor")` or `restore_context(name: "authentication work")`

**insight**
- Parameters: content (required), key (optional), tags (optional array), thread_id (optional)
- Example: `insight(content: "Rate limits reset at UTC midnight", key: "api/rate-limits", tags: ["api"])`
- Example (revision): `insight(content: "Rate limits reset at UTC midnight per-key, not globally", key: "api/rate-limits", thread_id: "ithr_x7g3n2k9m1pq")`

**recall**
- Parameters: key (required - exact or semantic query), limit (optional, default: 5)
- Returns ranked results; includes `thread_id` for each result
- Example: `recall(key: "api/rate-limits")` or `recall(key: "rate limiting behavior")`

**decide**
- Parameters: topic (required), decision (required), reasoning (optional), tags (optional array), thread_id (optional)
- Example: `decide(topic: "auth-method", decision: "Use JWT with refresh tokens", reasoning: "...")`
- Example (revision): `decide(topic: "auth-method", decision: "Switch to session tokens", reasoning: "JWTs caused issues with...", thread_id: "dthr_p4k8m2n6x9qz")`

**get_decisions**
- Parameters: topic (optional), limit (optional, default: 10), list_topics (optional boolean)
- Returns decisions with `thread_id` for each; use to find thread when revising
- Example: `get_decisions(topic: "auth-method")` or `get_decisions(list_topics: true)`

**save_plan**
- Parameters: title (required), version (required), body (required), tags (optional array), thread_id (optional)
- Note: title + version must be unique
- Example: `save_plan(title: "V2 Architecture", version: "draft", body: "...")`
- Example (revision): `save_plan(title: "V2 Architecture", version: "v1.0", body: "...", thread_id: "pthr_m3k9n7x2p4qz")`

**get_plan**
- Parameters: title (optional), version (optional), all_versions (boolean), list_titles (boolean), limit (optional)
- Returns plans with `thread_id`; all versions of a plan share the same thread
- Example: `get_plan(title: "V2 Architecture")` or `get_plan(list_titles: true)`

**search_plans**
- Parameters: query (required - natural language), limit (optional, default: 10)
- Returns ranked results with `thread_id` for each
- Example: `search_plans(query: "database migration strategy")`

### Important Notes

**Semantic Search:**
- Tools support both exact matching and semantic search via natural language
- Exact matching always works; semantic search requires embeddings service
- If you get `:embeddings_not_ready` errors, use exact names/keys

**Thread Identity:**
- All records return a `thread_id`—store it if you may revise later
- Never invent thread IDs; omit for new records, echo back for revisions
- Records sharing a `thread_id` are versions of the same logical entity
- Use timestamps to determine which version is current
