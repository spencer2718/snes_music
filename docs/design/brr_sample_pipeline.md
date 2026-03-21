# BRR Sample Pipeline — Research Findings

**Date:** 2026-03-21
**Status:** Research complete, implementation not started

---

## 1. .gsi file format

SNESGSS instrument files (`.gsi`) are **text-based INI format**, not binary. They use the signature `[SNESGSS Instrument]` and store all data as key-value pairs.

### Fields (from `src/UnitMain.h` struct `instrumentStruct` and `src/UnitMain.cpp` `InstrumentDataParse`)

| Field | Type | Description |
|---|---|---|
| `Name` | string | Instrument display name |
| `EnvAR` | int | ADSR attack rate (0–15) |
| `EnvDR` | int | ADSR decay rate (0–7) |
| `EnvSL` | int | ADSR sustain level (0–7) |
| `EnvSR` | int | ADSR sustain rate (0–31) |
| `Length` | int | BRR-resampled sample length (in samples) |
| `LoopStart` | int | Loop start point (in source samples) |
| `LoopEnd` | int | Loop end point (in source samples) |
| `LoopEnable` | bool | Whether the sample loops |
| `SourceLength` | int | Original source sample length (in samples) |
| `SourceRate` | int | Source sample rate (8000/16000/32000 Hz) |
| `SourceVolume` | int | Volume scaling (0–128) |
| `WavLoopStart` | int | WAV loop start (original file loop point) |
| `WavLoopEnd` | int | WAV loop end |
| `EQLow` | int | 3-band EQ low |
| `EQMid` | int | 3-band EQ mid |
| `EQHigh` | int | 3-band EQ high |
| `ResampleType` | int | Resampling algorithm (0–4: nearest/linear/sine/cubic/bandlimited) |
| `DownsampleFactor` | int | Downsample multiplier |
| `RampEnable` | bool | Ramp on/off |
| `LoopUnroll` | bool | Whether to unroll loops for quality |
| `TrebleBoost` | int | Gaussian filter compensation |
| `SourceData` | hex string | **Raw 16-bit PCM sample data, hex-encoded** |

### SourceData encoding

The `SourceData` field contains the sample as a **contiguous hex string of 16-bit signed integers** (4 hex chars per sample, big-endian unsigned representation of signed values). Parsed by `gss_load_short_data()` in `UnitMain.cpp:1579`.

Example from `waveform_sine.gsi` (64 samples, SourceLength=64):
```
000008e111ad1a4d22ad2ab73257397c4012460b...
```
Each 4-char group is one 16-bit PCM sample: `0000` = 0, `08e1` = 2273, etc.

### Critical finding: .gsi contains PCM, not BRR

The source data in `.gsi` files is **original 16-bit PCM**, not BRR-encoded data. BRR encoding happens at SNESGSS export time (when File > Export or CLI export runs). The `Length` field is the target BRR-resampled length; `SourceLength` is the original PCM length.

**This means we do NOT need a BRR decoder for the v0.2 preview pipeline.** We can extract PCM directly from the .gsi hex string and write it as a WAV file.

---

## 2. BRR encoding summary (for reference)

BRR (Bit Rate Reduction) is the SNES's native compressed audio format. Included here for completeness, though v0.2 preview does not require BRR decoding.

### Format
- **Block size:** 9 bytes encode 16 samples (4.5:1 compression)
- **Byte 0 (header):** `SSSSFFLE`
  - `SSSS` (bits 7–4): shift amount (0–12, values 13–15 are special)
  - `FF` (bits 3–2): filter mode (0–3, determines prediction coefficients)
  - `L` (bit 1): loop flag (1 = sample loops)
  - `E` (bit 0): end flag (1 = last block)
- **Bytes 1–8:** 16 nibbles (4-bit signed values), two per byte (high nibble first)

### Filter modes (from `src/brr/brr.cpp` `get_brr_prediction`)
- Filter 0: no prediction (raw delta)
- Filter 1: `p = p1 - (p1 >> 4)` (simple 1-tap)
- Filter 2: two-tap with `p1` and `p2`
- Filter 3: two-tap with different coefficients

### Decoding (from `decodeBRR()`)
Each nibble is sign-extended, shifted by the shift amount, added to the filter prediction, and clamped to 16-bit range with wrapping.

### Loop mechanism
The loop flag in byte 0 bit 1 marks which blocks are part of the loop. The end flag in bit 0 marks the final block. The SPC700 DSP uses a sample directory (DIR register) that stores start and loop addresses for each voice.

---

## 3. Existing BRR tools in the SNESGSS repo

The SNESGSS source includes a complete BRR encoder/decoder in `src/brr/`:

- **`brr.cpp` / `brr.h`** — BRR block decoder (`decodeBRR()`), filter prediction, gaussian filter emulation, WAV file writer (`generate_wave_file()` — currently commented out)
- **`brr_encoder.cpp`** — Full BRR encoder with resampling, loop adjustment, treble boost. The `main()` is commented out (integrated into SNESGSS GUI instead of standalone CLI).
- **`common.h`** — Type definitions (`pcm_t` = `signed short`, `u8`, `u16`, `u32`)

These are embedded in the SNESGSS GUI build (Borland C++ Builder). They are NOT standalone command-line tools in their current form.

### External BRR tools (for reference, not needed for v0.2)
- **BRR Tools** by Bregalad — the original standalone version of the encoder/decoder in the SNESGSS repo. Available separately but the SNESGSS copy is sufficient.
- **snesbrr** — various other community BRR encoders exist but are not needed since we're extracting PCM directly.

---

## 4. Proposed v0.2 conversion pipeline

Since .gsi files contain raw PCM (not BRR), the pipeline is simpler than expected:

```
.gsi file (text/INI)
    │
    ▼
Python parser: read INI fields + decode hex SourceData
    │
    ▼
16-bit signed PCM samples (in memory)
    │
    ▼
Write as 16-bit mono WAV (SourceRate from .gsi header)
    │
    ▼
Load into RS5K in REAPER (one instance per track)
```

### Implementation plan

**Tool:** Python script in `tools/validate/` or a new `tools/samples/` directory.

**Input:** Path to a .gsi file (or directory of .gsi files).

**Steps:**
1. Parse the INI-style header (simple text parsing, no library needed)
2. Read `SourceData` hex string
3. Decode: each 4-char group → one `int16` sample (interpret as unsigned, convert to signed)
4. Read `SourceRate` for the WAV sample rate
5. Read `SourceLength` to verify sample count
6. Write standard 16-bit mono WAV file using Python `wave` module
7. Optionally apply `SourceVolume` scaling

**Loop points:** Capture `LoopStart`, `LoopEnd`, `LoopEnable` from the header. RS5K supports sample loop points, so these can be passed through.

**ADSR envelope:** Capture `EnvAR/DR/SL/SR` for reference. RS5K does not emulate SPC700 ADSR, but we could approximate with RS5K's built-in envelope or just document the mismatch.

### Tool recommendation: build in Python

Reasons to build rather than reuse:
- The .gsi parsing is trivial (text INI + hex decode)
- The WAV writing is trivial (Python `wave` stdlib module)
- No BRR decoding needed — we're reading raw PCM
- No external dependencies required
- Keeps the toolchain self-contained
- A standalone C tool would need compilation and adds complexity

---

## 5. Blockers and unknowns

### Resolved
- ✓ .gsi format is documented enough (via source code) to parse
- ✓ BRR decoding is NOT needed for preview (PCM is in the .gsi)
- ✓ Python stdlib has everything needed (`wave` module, basic hex/int parsing)

### Open questions
- **Hex encoding signedness:** The hex values in SourceData are written as `unsigned short` by `gss_save_short_data()`. Need to verify whether values >0x7FFF should be interpreted as negative (two's complement). The struct stores `short*` (signed), so likely yes.
- **SourceVolume application:** Should we scale samples by `SourceVolume/128` before writing WAV? Or let RS5K handle volume?
- **Resampling:** The .gsi stores both `SourceLength` (original PCM length) and `Length` (BRR-target length after resampling). For preview, we should use the original PCM at `SourceRate` — the resampling is a BRR export concern.
- **RS5K loop point format:** Need to verify that RS5K accepts loop points in sample-offset format and how to set them via ReaScript.
- **B +21 cent tuning:** The .gsi samples are tuned to B +21 cents per the readme. RS5K would need a pitch offset of +79 cents (to map B+21 → C) or we document that the composer should use B as the reference pitch. Need a decision on this.
