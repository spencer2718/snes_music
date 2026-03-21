# CLAUDE.md — SNES Music Constraint/Export Tool

## Project purpose

REAPER-first authoring toolchain for SNES music composition. Compose in REAPER's piano roll, validate against SNES hardware and SNESGSS engine constraints during authoring, and export a deterministic package for downstream SNES integration. This is a constraint-aware export harness, not a soundchip emulator or VST.

## Engine target

**SNESGSS** — sole v0.1 target. No other engine adapters in scope.

Current version: v0.2 in progress. See SPEC.md §5a for roadmap.

## v0.1 supported subset

<!-- Items marked (partial) are collected but not fully implemented. See SPEC.md §5a for version roadmap. -->
- Note on/off, duration
- Velocity (only if mapped to a defined engine semantic)
- Channel/instrument assignment
- Loop start/end markers (partial)
- Simple tempo map subset
- Drum split rules (partial)
- Song metadata (partial)

## REAPER setup

JSFX files are symlinked into REAPER's Effects folder — edits in the repo are live immediately (JSFX auto-reloads on file change). No manual copy needed after `git pull`.

```
ln -s /home/spencer/snes/snes_music/tools/reaper ~/.config/REAPER/Effects/snes_music
```

In REAPER: FX browser > JS > snes_music > snes_channel_monitor

Project setup: run `snes_project_setup.lua` from Actions — creates monitor, instrument tracks, MIDI routing, and RS5K sample loading in one step.

## Build/test commands

```
python -m tools.validate exports/                                        # validate export output
python -m tools.samples convert path/to/file.gsi --output samples/       # convert .gsi to WAV
pytest tests/                                                            # run test suite
```

## File ownership

| Directory | Owns |
|---|---|
<!-- tools/export/ removed — SNESGSS integration is via MIDI import, not a code adapter -->
| `tools/reaper/` | JSFX validator panel + Lua ReaScript exporter |
| `tools/validate/` | Python validation/build CLI |
| `tools/samples/` | .gsi→WAV conversion tool |
| `docs/decisions/` | Active decision records |
| `docs/fixtures/` | Test fixtures and expected outputs |
| `docs/design/` | Design documents and diagrams |
| `exports/` | Generated export output (tracked) |
| `samples/` | Converted WAV instrument files (gitignored, regenerated from .gsi) |

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

## Non-goals

1. Not a cross-DAW product
2. Not a cycle-accurate SNES audio emulator/VST
3. Not a universal exporter for every SNES music engine
4. Not a compiler for arbitrary REAPER automation, plugin chains, or audio effects
5. Not a headless `.gsm` pipeline — defer unless format proves tractable
