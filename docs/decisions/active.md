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

## REAPER authoring workflow
Each SNES voice maps to a MIDI channel (1–8). Use REAPER's native multi-channel routing:
1. Place SNES Channel Monitor JSFX on a dedicated track
2. In the FX chain window, select the JSFX instance on the left
3. Open the **FX menu** (top of window, not Options) → "Build 16 channels of MIDI routing to this track"
4. REAPER creates 16 child tracks with per-channel sends. Delete tracks 9–16.
5. Compose on tracks 1–8. Each track's MIDI arrives at the monitor on the correct channel.

No custom channel remap JSFX needed. Native REAPER feature.
A Lua project template script may be added later for convenience (v0.2).
