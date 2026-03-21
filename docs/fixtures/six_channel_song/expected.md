# Fixture: six_channel_song

## Description

6-channel, 4-bar loop composed in REAPER with the following instruments:
- Channel 1: Piano Mid
- Channel 2: Strings 2
- Channel 3: Synth Bass 1
- Channel 4: Harp
- Channel 5: Kick 1
- Channel 6: Snare 1

Note: drums (kick, snare) use regular melodic channels (5–6), not SNESGSS drum channels (7–8). Drum channel mapping is deferred to v0.4+.

## Expected validation results

- **Status:** PASS
- **Errors:** 0
- **Warnings:** 0
- **Tracks:** 6
- **Channels:** 1–6
- **Velocity variation:** present (multiple distinct values)
- **Regions:** 0

## SNESGSS verification

Verified in SNESGSS (Wine on Ubuntu):
- Imports via Song → Import notes from MIDI
- Notes appear on correct channels with correct timing
- Playback works
- Loop set via Ctrl+Home / Ctrl+End → loops correctly
- Exported via SNESGSS → spc700.bin + music_0.bin produced

## MIDI export

- Format 1, 7 tracks (1 tempo + 6 note tracks)
- 480 PPQ
- 1080 bytes
- Note-on/note-off events only
