# Active decisions

## Baseline scope
Per SPEC.md §§1-5. No changes from the spec's initial position.
Only add entries here when a decision **diverges from or resolves an ambiguity in** the spec.

## JSFX scope
Start with minimal traffic-light validation (channel count, overlap detection).
Prototype early. If the drawing UX is too limited, move detail to the validation report.

## Subagent usage
- test-runner: YES, use from session 1
- export-auditor: pipeline exists as of v0.1, activate when MIDI content validation is added in v0.2
- spec-keeper: NO, the PM web instance fills this role

## Workflow protocol
CC commits and pushes at end of every pass. PM pulls and reviews diffs.
Established session 1. See CLAUDE.md repo conventions.

## REAPER authoring workflow
**Primary (automated):** Run `snes_project_setup.lua` from Actions menu. Provide samples directory path. Script creates monitor track, instrument tracks (1–8), MIDI routing, and RS5K instances.
Melodic tracks: manually switch RS5K to "Note (Semitone shifted)" after setup.
Drum tracks: leave RS5K in default "Sample" mode.

**Manual alternative:** Place SNES Channel Monitor JSFX on a track, select it in the FX chain, FX menu → "Build 16 channels of MIDI routing to this track", delete tracks 9–16.

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

## v0.1 status: COMPLETE
All exit criteria met in session 1. Date: 2026-03-21.

### Exit criteria verification
1. ✓ JSFX panel loads in REAPER, shows channel occupancy for channels 1–8
2. ✓ Lua exporter emits intermediate JSON for test project (4 channels, 34 notes)
3. ✓ Lua exporter emits constrained MIDI (Format 1, 5 tracks, 480 PPQ, 372 bytes)
4. ✓ Python validator produces deterministic validation report (PASS) and build manifest with hashes
5. ✓ Fixture project imports into SNESGSS via documented manual path:
   - Wine on Ubuntu works (SNESGSS v1.42 via wine snesgss.exe)
   - F3 to load instruments, Song → Import notes from MIDI
   - Navigate via Z: drive to reach Linux filesystem
   - Notes appear on correct channels, playback works
6. ✓ Unsupported semantics reported explicitly (overlap warnings, >8 channel warnings, no-MIDI-item warnings)

### SNESGSS import workflow (verified)
- Launch: `cd ~/snes/snesgss && wine snesgss.exe`
- Load instruments: F3
- Import MIDI: Song → Import notes from MIDI → navigate Z:/home/spencer/snes/snes_music/exports/snes_export.mid
- Wine needs Z: drive prefix to access Linux filesystem

### Original acceptance test (historical)
1. Launch SNESGSS via `wine ~/snes/snesgss/snesgss.exe`
2. Create new project, define 4 placeholder instruments for channels 1–4
3. Import snes_export.mid
4. Verify notes appear on correct channels with correct timing
5. Test whether tempo survives import
6. Export via CLI → verify spc700.bin + music_0.bin are produced

### Open items for v0.2
- ~~Lua project template script~~ → DONE: `snes_project_setup.lua`
- ~~BRR→WAV conversion~~ → DONE: `tools/samples/` (.gsi contains PCM, no BRR decoding needed)
- ~~RS5K auto-loading~~ → DONE: setup script loads RS5K with samples
- RS5K mode automation → DEFERRED: cannot be set via ReaScript, manual step required
- Drum channel support (SNESGSS channels 7–8, instruments 10–13) → DEFERRED to v0.4+
- Tempo import verification → UNTESTED (SNESGSS may ignore MIDI tempo)
- ARAM budget estimator with real sample sizes → NOT STARTED
- Constrained MIDI content validation in Python → NOT STARTED
- JSFX enhancements → NOT STARTED

## RS5K mode setting
Cannot be automated via ReaScript (not exposed as parameter, named config, or chunk field).
Melodic tracks: user must manually switch to "Note (Semitone shifted)" after project setup.
Drum/percussion tracks: default "Sample" mode is correct (triggers sample regardless of note pitch).
Attempted: SetNamedConfigParm MODE, SetParam, binary state chunk modification — none worked.
Revisit if REAPER exposes this in a future API update.

## v0.2 scope
North star: hear SNES samples in REAPER during composition.
Core path: .gsi→WAV conversion + RS5K auto-loading. **ACHIEVED.**

Verified end-to-end: 6-channel song (piano, strings, synth bass, harp, kick, snare) composed in REAPER → exported → imported into SNESGSS → plays back correctly → exported to spc700.bin + music_0.bin.

Known limitations:
- RS5K mode must be set manually (melodic = "Note semitone shifted", drums = "Sample")
- Short samples don't sustain well in RS5K (loop point embedding attempted, reverted — samples too short)
- Velocity data exported but likely ignored by SNESGSS; mixing done in SNESGSS
- SPC700 emulation VST deferred (would solve preview fidelity and sustain issues)

Remaining v0.2 polish (not blocking):
- Tempo import verification
- MIDI content validation in Python
- ARAM budget with real sample sizes

### v0.2 acceptance test (verified)
1. Composed 6-channel, 4-bar loop in REAPER (piano, strings, synth bass, harp, kick, snare)
2. Exported via snes_export.lua → snes_export.json + snes_export.mid (1080 bytes, 7 tracks)
3. Validated via Python CLI → PASS, 0 errors
4. Imported into SNESGSS (Wine) → notes on correct channels, playback works
5. Set loop in SNESGSS → loops correctly
6. Exported from SNESGSS → spc700.bin + music_0.bin produced
Full pipeline verified: REAPER → JSON + MIDI → SNESGSS → SNES-ready binaries
