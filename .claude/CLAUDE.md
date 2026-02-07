# Planning Workflow

When creating plans for new features or tasks, follow this structure:

## Directory Structure
```
docs/planning/{thing-we-are-doing}/
├── plan.yml           # High-level plan and overview
├── step-0.yml         # First orthogonal step with tests
├── step-1.yml         # Second orthogonal step with tests
└── step-N.yml         # Additional steps as needed
```

## Process
1. Start with `plan.yml` - create a comprehensive overview of the work
2. Break down into orthogonal steps in separate `step-N.yml` files
3. Each step file should include:
   - Clear scope and objectives
   - Tests to verify completion
   - Dependencies (if any)
4. **Compact between steps** - after completing each step, consolidate/refactor before moving to next
5. Steps should be independent where possible (orthogonal)

## When to Use This
Apply this workflow whenever starting significant new work, features, or refactoring efforts.

