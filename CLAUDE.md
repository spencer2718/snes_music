# CLAUDE.md — SNES Music Constraint/Export Tool

## Project purpose

REAPER-first authoring toolchain for SNES music composition. Compose in REAPER's piano roll, validate against SNES hardware and SNESGSS engine constraints during authoring, and export a deterministic package for downstream SNES integration. This is a constraint-aware export harness, not a soundchip emulator or VST.

## Engine target

**SNESGSS** — sole v0.1 target. No other engine adapters in scope.

## v0.1 supported subset

- Note on/off, duration
- Velocity (only if mapped to a defined engine semantic)
- Channel/instrument assignment
- Loop start/end markers
- Simple tempo map subset
- Drum split rules
- Song metadata

## Build/test commands

<!-- None yet. Update this section as commands are established. -->

## File ownership

| Directory | Owns |
|---|---|
| `tools/reaper/` | JSFX validator panel + Lua ReaScript exporter |
| `tools/export/` | SNESGSS engine adapter |
| `tools/validate/` | Python validation/build CLI |
| `docs/decisions/` | Active decision records |
| `docs/fixtures/` | Test fixtures and expected outputs |
| `docs/design/` | Design documents and diagrams |

## Repo conventions

- `snake_case` for all filenames
- All commits via CC (sole committer)
- `SPEC.md` is normative — if code contradicts the spec, fix the code or update the spec first
- Every CC pass ends with a commit and push. Commit message format: `[pass] short description`. Never leave work uncommitted. The PM reviews diffs, not chat summaries.
- CC reads `CLAUDE.md`, `docs/decisions/active.md`, and relevant `.claude/rules/` files at session start. If unsure about project state, read these before asking.
- Keep this file under 80 lines

## Memory rules

- Durable decisions → `docs/decisions/active.md`
- Transient findings → CC auto memory
- Never duplicate the full spec in CLAUDE.md or memory

## Non-goals (v0.1)

1. Not a cross-DAW product
2. Not a cycle-accurate SNES audio emulator/VST
3. Not a universal exporter for every SNES music engine
4. Not a compiler for arbitrary REAPER automation, plugin chains, or audio effects
5. Not a headless `.gsm` pipeline — defer unless format proves tractable
