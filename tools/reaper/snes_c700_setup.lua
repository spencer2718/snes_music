-- SNES C700 Project Setup
-- Creates a C700 instrument track + 8 MIDI voice tracks routed by channel.
-- Part of: https://github.com/spencer2718/snes_music

-- Derive samples path from script location
local script_path = ({reaper.get_action_context()})[2]
local repo_root = script_path:match("(.*)/tools/reaper/") or ""
local samples_path = repo_root .. "/samples/snesgss"

reaper.PreventUIRefresh(1)
reaper.Undo_BeginBlock()

-- 1. Create the C700 instrument track
reaper.InsertTrackAtIndex(0, true)
local c700_track = reaper.GetTrack(0, 0)
reaper.GetSetMediaTrackInfo_String(c700_track, "P_NAME", "C700", true)

-- Try to add C700 VST3
local fx_idx = reaper.TrackFX_AddByName(c700_track, "VST3:C700", false, -1)
if fx_idx < 0 then
  fx_idx = reaper.TrackFX_AddByName(c700_track, "VST3i:C700", false, -1)
end
if fx_idx < 0 then
  fx_idx = reaper.TrackFX_AddByName(c700_track, "C700", false, -1)
end
if fx_idx < 0 then
  reaper.Undo_EndBlock("SNES C700 Setup (failed)", -1)
  reaper.PreventUIRefresh(-1)
  reaper.ShowMessageBox(
    "C700 VST3 not found.\n\n" ..
    "Install it to ~/.vst3/ first:\n" ..
    "  cd ~/snes/C700 && bash scripts/build-install.sh\n\n" ..
    "Then rescan: Options > Preferences > VST > Re-scan",
    "C700 Setup Error", 0)
  return
end

-- Ensure C700 track receives on all MIDI channels and outputs audio
reaper.SetMediaTrackInfo_Value(c700_track, "B_MAINSEND", 1)

-- 2. Create 8 MIDI voice tracks
for voice = 1, 8 do
  local idx = voice  -- insert after C700 track
  reaper.InsertTrackAtIndex(idx, true)
  local voice_track = reaper.GetTrack(0, idx)
  reaper.GetSetMediaTrackInfo_String(voice_track, "P_NAME", "Voice " .. voice, true)

  -- Disable master/parent send (audio only goes via send to C700)
  reaper.SetMediaTrackInfo_Value(voice_track, "B_MAINSEND", 0)

  -- Create send to C700 track
  local send_idx = reaper.CreateTrackSend(voice_track, c700_track)

  -- Disable audio send (MIDI only)
  reaper.SetTrackSendInfo_Value(voice_track, 0, send_idx, "I_SRCCHAN", -1)

  -- Set MIDI send: source = all channels, dest = channel N
  -- I_MIDIFLAGS: low 5 bits = source channel (0=all), bits 5-9 = dest channel (0=all, 1-16=ch)
  local midi_flags = voice * 32  -- dest channel = voice (1-8), source = 0 (all)
  reaper.SetTrackSendInfo_Value(voice_track, 0, send_idx, "I_MIDIFLAGS", midi_flags)

  -- Insert a tiny MIDI item at beat 0 with a program change event
  -- Program = voice-1 (Voice 1 → program 0, Voice 2 → program 1, etc.)
  local item = reaper.CreateNewMIDIItemInProj(voice_track, 0, 0.01)
  if item then
    local take = reaper.GetActiveTake(item)
    if take then
      -- MIDI_InsertCC(take, selected, muted, ppqpos, chanmsg, chan, msg2, msg3)
      -- Program change: chanmsg=0xC0, chan=0 (send remaps), msg2=program, msg3=0
      reaper.MIDI_InsertCC(take, false, false, 0, 0xC0, 0, voice - 1, 0)
      reaper.MIDI_Sort(take)
    end
  end
end

reaper.Undo_EndBlock("SNES C700 Project Setup", -1)
reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()

-- Print summary
reaper.ShowConsoleMsg("\n=== SNES C700 Project Setup ===\n")
reaper.ShowConsoleMsg("C700 instrument track created\n")
reaper.ShowConsoleMsg("8 MIDI voice tracks with default program mapping:\n")
for v = 1, 8 do
  reaper.ShowConsoleMsg("  Voice " .. v .. " -> Channel " .. v .. " -> Program " .. (v-1) .. "\n")
end
reaper.ShowConsoleMsg("Samples path: " .. samples_path .. "\n")
reaper.ShowConsoleMsg("Next: Open C700 editor > Load Sample > browse to samples/snesgss/\n")
reaper.ShowConsoleMsg("Ready to compose!\n\n")
