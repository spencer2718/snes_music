# SNES Music — REAPER + C700 Workflow

Companion repo for [C700 Linux Fork](https://github.com/spencer2718/C700) — provides a REAPER action script for quick project setup and a library of SNESGSS instrument samples converted to WAV.

## Prerequisites

- REAPER on Linux
- C700 VST3 installed (`~/.vst3/C700.vst3`) — see the [C700 fork](https://github.com/spencer2718/C700) for build instructions

## Setup

Symlink the action scripts into REAPER's Effects folder so they auto-update with git pull:

```bash
ln -s /path/to/snes_music/tools/reaper ~/.config/REAPER/Effects/snes_music
```

Then in REAPER: Actions > New action > Load ReaScript > navigate to `tools/reaper/snes_c700_setup.lua`

## Workflow

### Quick start

1. Run the `snes_c700_setup` action from REAPER's action list
2. The script creates a C700 instrument track + 8 MIDI voice tracks, each routed to C700 on its own MIDI channel
3. Open C700's editor, click "Load Sample" to load instruments from the `samples/` folder into C700's slots
4. Compose on the MIDI tracks — each track sends on a unique channel
5. Use MIDI program change to select which C700 instrument slot each channel uses
6. For drums: use C700's multi-sample bank feature with high/low key mapping

### Constraints (enforced by C700's SPC700 emulation)

- 8 simultaneous voices (hardware limit)
- 64KB ARAM total (samples + echo buffer + player code) — check the ARAM Used parameter
- BRR sample format (C700 encodes automatically from WAV)
- SPC700 ADSR envelopes only

### SPC Export

1. Set Record Start and Record End beat values in C700's editor
2. Click Export SPC, choose save location
3. Disable REAPER loop, play through the region
4. `.spc` file is written automatically — playable on real SNES hardware

## Samples

`samples/snesgss/` contains instrument samples converted from SNESGSS's .gsi instrument library to 16-bit mono WAV. These are ready to load directly into C700.

Samples are raw PCM extracted from SNESGSS .gsi files at original pitch. C700 handles pitch mapping via its DSP pitch register — no external correction needed. Set basekey=59 in C700 for correct tuning.
