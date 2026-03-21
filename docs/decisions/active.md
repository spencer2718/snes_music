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

## Channel assignment
MIDI channel is determined by track position, not by note-level MIDI channel data.
Tracks without MIDI items (e.g., the monitor track) are skipped.
First MIDI track = channel 1, second = channel 2, up to 8.
The "Build 16 channels" REAPER routing creates tracks in channel order,
so track position matches the monitor's channel view.
This keeps the workflow frictionless — compose on a track, channel is implicit.

## SNESGSS integration (v0.1 target)

### MIDI import contract
- Supports Format 0 and Format 1 (we export Format 1 — OK)
- Imports **notes only** — no program changes, CC, pitch bend
- Instrument assigned by **channel number**, not MIDI program change
- Channels 1–8, strict monophony per channel
- Track order likely irrelevant; importer is channel-driven
- Tempo import is **unverified** — SNESGSS has its own native speed field (1–99, default 20). Test explicitly; do not assume MIDI tempo meta-events survive import.

### Drum channel (deferred past v0.1 basic test)
- SNESGSS drum mapping is NOT generic MIDI channel 10
- Drums go to SNES channels 7–8: ch7 = hats, ch8 = kick/snare/toms
- Drum instrument numbers: 10=kick, 11=snare, 12=toms, 13=hats
- Our exporter will need drum-aware logic eventually

### Instrument/sample requirements
- Instruments must be pre-defined in SNESGSS before MIDI import
- Samples: 16-bit mono WAV, 8000/16000/32000 Hz (32000 preferred)
- Melodic samples tuned to B +21 cents for BRR alignment
- Single sample bank shared across all songs and SFX

### .gsm format
- SNESGSS native project file, not a runtime asset
- Not publicly documented as a schema
- Direct .gsm generation remains deferred per spec

### Export path (SNESGSS → SNES)
- GUI: File > Export (some users report I/O error 123; "Save and Export" or CLI may be more reliable)
- CLI: `wine snesgss.exe filename.gsm -e [export_path]` (use relative paths under Wine)
- Outputs: spc700.bin (driver+samples), music_N.bin (per-song), sounds.asm, sounds.h
- Integration uses WLA DX assembler format, assumes LoROM
- CLI export confirmed working on Ubuntu 24.04 + Wine 9.0

### Known gotchas
- Windows-only GUI (Borland C++ Builder). Runs under Wine 9.0 on Ubuntu.
- Thin documentation — readme.txt + commented asm is essentially all there is
- Known driver bug that can lock console (patched versions exist)
- Some users had issues with File > Export; CLI export is more reliable
- Do not hex-edit spc700.bin header bytes
- Wine requires relative paths for CLI export (absolute Unix paths don't work)

### v0.1 acceptance test
1. Launch SNESGSS via `wine ~/snes/snesgss/snesgss.exe`
2. Create new project, define 4 placeholder instruments for channels 1–4
3. Import snes_export.mid
4. Verify notes appear on correct channels with correct timing
5. Test whether tempo survives import
6. Export via CLI → verify spc700.bin + music_0.bin are produced
