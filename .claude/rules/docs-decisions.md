# Decision records conventions

## Scope
Files in `docs/decisions/`.

## When to write a decision record
- Engine target or scope changes
- A spec ambiguity is resolved during implementation
- An approach is tried and rejected (record why)
- A non-obvious technical tradeoff is made
- The PM instructs CC to record a decision

## Active file
`docs/decisions/active.md` is the living document of current decisions. Update it in place — don't append, keep it clean and current.

## Format template
For decisions that need more context than a line in `active.md`, create a standalone file:

```markdown
# Decision: [short title]

**Date:** YYYY-MM-DD
**Status:** accepted | superseded | rejected

## Context
What prompted this decision.

## Decision
What was decided.

## Consequences
What follows from this decision — tradeoffs, constraints, follow-up work.
```

## Naming
- `active.md` — always exists, always current
- Additional records: `NNNN_short_title.md` (e.g., `0001_snesgss_target.md`)
