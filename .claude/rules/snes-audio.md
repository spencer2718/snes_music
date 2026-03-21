# SNES audio hardware constraints

> Canonical constraint model: SPEC.md §8. This file has implementation-facing details only.

## Scope
Any code that validates against or references SNES audio limits.

## Hardware facts
- **Voices:** 8 simultaneous (Sony SPC700 DSP)
- **ARAM:** 64 KiB total audio RAM — shared by samples, echo buffer, and engine code
- **Sample format:** BRR (Bit Rate Reduction) — 9 bytes encode 16 samples, ~32 KiB practical sample budget after engine/echo overhead
- **Sample rate:** 32 kHz max per voice, typically lower per-voice rates used
- **Pitch:** 14-bit pitch register per voice

## Echo registers
- **EON:** Echo enable bitmask — one bit per voice (which voices feed the echo)
- **EDL:** Echo delay — 0–15, each step = 16ms = 2048 bytes of ARAM
- **ESA:** Echo buffer start address in ARAM (page-aligned)
- **EFB:** Echo feedback coefficient (-128 to 127)
- **FIR:** 8-tap FIR filter coefficients for echo processing
- Echo buffer size = EDL * 2048 bytes — this directly reduces available sample memory

## SNESGSS MIDI import constraints
- Expects one MIDI channel per instrument voice
- Channels are monophonic — overlapping notes on the same channel are not supported
- Drum channel uses note-to-sample mapping (typically channel 10)
- Tempo from MIDI tempo events
- No CC automation support in the base import path
- No pitch bend in the base import path
- SNESGSS has its own instrument/envelope definitions — MIDI is note data only

## SNESGSS tool location
- Repo: ~/snes/snesgss (sibling to this repo, not inside it)
- Source: https://github.com/nathancassano/snesgss
- Run via: `wine ~/snes/snesgss/snesgss.exe` (Linux/Ubuntu)
- CLI export: `wine ~/snes/snesgss/snesgss.exe filename.gsm -e [path]`
