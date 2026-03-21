# Active decisions

## Baseline scope
Per SPEC.md §§1-5. No changes from the spec's initial position.
Only add entries here when a decision **diverges from or resolves an ambiguity in** the spec.

## JSFX scope
Start with minimal traffic-light validation (channel count, overlap detection).
Prototype early. If the drawing UX is too limited, move detail to the validation report.

## Subagent usage
- test-runner: YES, use from session 1
- export-auditor: add when export pipeline exists
- spec-keeper: NO, the PM web instance fills this role

## Workflow protocol
CC commits and pushes at end of every pass. PM pulls and reviews diffs.
Established session 1. See CLAUDE.md repo conventions.
