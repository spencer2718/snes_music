# Fixture: four_channel_basic

## Scenario

4 MIDI tracks routed to channels 1–4, each playing a single monophonic melodic line. No overlapping notes within any channel. Channels 5–8 are silent.

## Expected JSFX behavior

### Normal case (no overlaps)

| Channel | Active notes | Bar color | Status |
|---------|-------------|-----------|--------|
| 1 | 0 or 1 | Green | OK |
| 2 | 0 or 1 | Green | OK |
| 3 | 0 or 1 | Green | OK |
| 4 | 0 or 1 | Green | OK |
| 5 | 0 | Dim green | Inactive |
| 6 | 0 | Dim green | Inactive |
| 7 | 0 | Dim green | Inactive |
| 8 | 0 | Dim green | Inactive |

- Total voices: 4 (when all 4 channels have a note sounding simultaneously)
- Summary line: "Voices: 4 / 8" in white/grey text
- No red bars, no warnings

### Overlap failure case

2 overlapping notes on channel 1 (e.g., C4 starts, E4 starts before C4 ends).

| Channel | Active notes | Bar color | Status |
|---------|-------------|-----------|--------|
| 1 | 2 | Red | Overlap violation |
| 2 | 0 or 1 | Green | OK |
| 3 | 0 or 1 | Green | OK |
| 4 | 0 or 1 | Green | OK |

- Channel 1 bar turns red immediately when the second note-on arrives
- Active note count for channel 1 shows "2"
- This indicates a SNESGSS constraint violation: channels must be monophonic

### Voice limit case

If all 8 channels have active notes simultaneously and a 9th voice would be needed, the summary line shows "Voices: X / 8" in red with "OVER LIMIT" warning. (Not testable with only 4 channels in this fixture, but documents the expected behavior.)
