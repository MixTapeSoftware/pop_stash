## Docker Compose Guidelines

- **Always bind ports to localhost (127.0.0.1)** — Never expose services to all interfaces

  **Never do this (exposes to network):**

      ports:
        - "5432:5432"
        - "8108:8108"

  **Always do this:**

      ports:
        - "127.0.0.1:5432:5432"
        - "127.0.0.1:8108:8108"
