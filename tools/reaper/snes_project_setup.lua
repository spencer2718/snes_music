-- snes_project_setup.lua
-- ReaScript: One-click SNES composition project setup.
-- Creates monitor track, instrument tracks with MIDI routing, and RS5K sample loading.

local SCRIPT_NAME = "SNES Project Setup"
local MAX_CHANNELS = 8
local JSFX_NAME = "snes_music/snes_channel_monitor"

----------------------------------------------------------------------
-- Logging
----------------------------------------------------------------------

local function log(msg)
  reaper.ShowConsoleMsg(msg .. "\n")
end

----------------------------------------------------------------------
-- Scan samples directory for NN_name.wav files
----------------------------------------------------------------------

local function scan_samples(dir)
  local samples = {}
  local i = 0

  -- Enumerate files in directory
  while true do
    local filename = reaper.EnumerateFiles(dir, i)
    if not filename then break end
    i = i + 1

    -- Match NN_name.wav pattern
    local num, name = filename:match("^(%d+)_(.+)%.wav$")
    if num and name then
      -- Capitalize first letter of each word for track name
      local display_name = name:gsub("_", " "):gsub("(%a)([%w_']*)", function(first, rest)
        return first:upper() .. rest
      end)
      samples[#samples + 1] = {
        index = tonumber(num),
        filename = filename,
        path = dir .. "/" .. filename,
        display_name = display_name,
      }
    end
  end

  -- Sort by NN prefix
  table.sort(samples, function(a, b) return a.index < b.index end)

  -- Cap at MAX_CHANNELS
  if #samples > MAX_CHANNELS then
    log("[WARNING] Found " .. #samples .. " samples, using first " .. MAX_CHANNELS)
    local capped = {}
    for j = 1, MAX_CHANNELS do
      capped[j] = samples[j]
    end
    samples = capped
  end

  return samples
end

----------------------------------------------------------------------
-- Find FX by name in REAPER's FX list
----------------------------------------------------------------------

local function add_fx_by_name(track, fx_name)
  local idx = reaper.TrackFX_AddByName(track, fx_name, false, -1)
  return idx >= 0 and idx or nil
end

----------------------------------------------------------------------
-- Create MIDI send from source track to destination track on a specific channel
----------------------------------------------------------------------

local function create_midi_send(src_track, dst_track, midi_channel)
  local send_idx = reaper.CreateTrackSend(src_track, dst_track)
  if send_idx < 0 then return false end

  -- Disable audio send (MIDI only)
  -- I_SRCCHAN: -1 = no audio
  reaper.SetTrackSendInfo_Value(src_track, 0, send_idx, "I_SRCCHAN", -1)

  -- I_MIDIFLAGS: set source and destination MIDI channels
  -- Bits 0-4: source channel (0 = all, 1-16 = specific)
  -- Bits 5-9: dest channel (0 = all, 1-16 = specific)
  -- We want: all source channels → remap to specific dest channel
  local midi_flags = 0 | (midi_channel << 5)
  reaper.SetTrackSendInfo_Value(src_track, 0, send_idx, "I_MIDIFLAGS", midi_flags)

  return true
end

----------------------------------------------------------------------
-- Load sample into RS5K on a track
----------------------------------------------------------------------

local function load_rs5k(track, sample_path, track_name)
  local fx_idx = reaper.TrackFX_AddByName(track, "ReaSamplOmatic5000", false, -1)
  if fx_idx < 0 then
    log("[WARNING] Could not add RS5K to '" .. track_name .. "'")
    return false
  end

  -- Set the sample file
  reaper.TrackFX_SetNamedConfigParm(track, fx_idx, "FILE0", sample_path)
  reaper.TrackFX_SetNamedConfigParm(track, fx_idx, "DONE", "")

  -- Set mode to "Note (Semitone shifted)" = mode 1
  -- Parameter index for Mode varies; use named config
  reaper.TrackFX_SetNamedConfigParm(track, fx_idx, "MODE", "1")

  -- Set note range: 0-127 (full range)
  -- Note range low = param 3, note range high = param 4 in RS5K
  -- Values are 0.0-1.0 mapping to 0-127
  reaper.TrackFX_SetParam(track, fx_idx, 3, 0.0)    -- note range low = 0
  reaper.TrackFX_SetParam(track, fx_idx, 4, 1.0)    -- note range high = 127

  return true
end

----------------------------------------------------------------------
-- Main
----------------------------------------------------------------------

local function main()
  log("=== " .. SCRIPT_NAME .. " ===")

  -- Prompt for samples directory
  local ok, samples_dir = reaper.GetUserInputs(
    SCRIPT_NAME, 1,
    "Samples directory (WAV files from .gsi converter):,extrawidth=300",
    ""
  )
  if not ok or samples_dir == "" then
    log("Setup cancelled.")
    return
  end

  -- Scan for WAV files
  local samples = scan_samples(samples_dir)
  if #samples == 0 then
    reaper.MB("No WAV files matching NN_name.wav found in:\n" .. samples_dir, SCRIPT_NAME, 0)
    log("No WAV files found. Aborting.")
    return
  end

  log("Found " .. #samples .. " sample(s) in " .. samples_dir)

  -- Begin undo block
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  -- 1. Create monitor track at position 0
  reaper.InsertTrackAtIndex(0, true)
  local monitor_track = reaper.GetTrack(0, 0)
  reaper.GetSetMediaTrackInfo_String(monitor_track, "P_NAME", "SNES Monitor", true)

  -- Add JSFX
  local jsfx_idx = add_fx_by_name(monitor_track, JSFX_NAME)
  if jsfx_idx then
    log("  Monitor: JSFX loaded")
  else
    log("[WARNING] JSFX '" .. JSFX_NAME .. "' not found — monitor track created without it")
  end

  -- Disable monitor track audio output to master (it's MIDI-only)
  reaper.SetMediaTrackInfo_Value(monitor_track, "B_MAINSEND", 0)

  -- 2. Create instrument tracks with MIDI sends and RS5K
  local created = {}
  for i, sample in ipairs(samples) do
    -- Insert track after monitor + previous instrument tracks
    local track_idx = i
    reaper.InsertTrackAtIndex(track_idx, true)
    local track = reaper.GetTrack(0, track_idx)

    -- Set track name
    reaper.GetSetMediaTrackInfo_String(track, "P_NAME", sample.display_name, true)

    -- Create MIDI send to monitor track on channel i
    if create_midi_send(track, monitor_track, i) then
      log("  Ch " .. i .. ": " .. sample.display_name .. " → MIDI send OK")
    else
      log("[WARNING] Failed to create MIDI send for " .. sample.display_name)
    end

    -- Load RS5K with sample
    if load_rs5k(track, sample.path, sample.display_name) then
      log("  Ch " .. i .. ": RS5K loaded with " .. sample.filename)
    end

    created[#created + 1] = {
      name = sample.display_name,
      channel = i,
      filename = sample.filename,
    }
  end

  -- End undo block
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock(SCRIPT_NAME, -1)
  reaper.TrackList_AdjustWindows(false)
  reaper.UpdateArrange()

  -- 3. Print summary
  log("")
  log("=== SNES Project Setup complete ===")
  log(#created .. " instrument track(s) created:")
  for _, t in ipairs(created) do
    log("  Ch " .. t.channel .. ": " .. t.name .. " ← " .. t.filename)
  end
  log("")
  log("Ready to compose!")
end

-- Guard
if reaper then
  main()
else
  print("This script must be run inside REAPER as a ReaScript.")
end
