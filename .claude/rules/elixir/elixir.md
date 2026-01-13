- **Always use full path aliases, never grouped aliases** — for maximum searchability across the codebase

  **Never do this:**

      alias PopStash.Memory.{Stash, Insight}
      alias PopStash.Coordination.{Session, Lock, Decision}

  **Always do this:**

      alias PopStash.Memory.Stash
      alias PopStash.Memory.Insight
      alias PopStash.Coordination.Session
      alias PopStash.Coordination.Lock
      alias PopStash.Coordination.Decision
