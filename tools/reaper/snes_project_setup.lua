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
  -- Use -1000 - desired_position to add FX without opening its UI window
  local idx = reaper.TrackFX_AddByName(track, fx_name, false, -1000)
  if idx < 0 then
    -- Fallback: try normal add, then close window
    idx = reaper.TrackFX_AddByName(track, fx_name, false, -1)
    if idx >= 0 then
      reaper.TrackFX_SetOpen(track, idx, false)
    end
  end
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
-- Base64 encode/decode (for RS5K state chunk modification)
----------------------------------------------------------------------

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_DECODE = {}
for i = 1, #B64 do
  B64_DECODE[B64:byte(i)] = i - 1
end
B64_DECODE[string.byte("=")] = 0

local function b64_decode(data)
  data = data:gsub("%s+", "")
  local out = {}
  for i = 1, #data, 4 do
    local b1 = B64_DECODE[data:byte(i)] or 0
    local b2 = B64_DECODE[data:byte(i + 1)] or 0
    local b3 = B64_DECODE[data:byte(i + 2)] or 0
    local b4 = B64_DECODE[data:byte(i + 3)] or 0
    local n = (b1 << 18) | (b2 << 12) | (b3 << 6) | b4
    out[#out + 1] = string.char((n >> 16) & 0xFF)
    if data:byte(i + 2) ~= string.byte("=") then
      out[#out + 1] = string.char((n >> 8) & 0xFF)
    end
    if data:byte(i + 3) ~= string.byte("=") then
      out[#out + 1] = string.char(n & 0xFF)
    end
  end
  return table.concat(out)
end

local function b64_encode(data)
  local out = {}
  for i = 1, #data, 3 do
    local b1 = data:byte(i)
    local b2 = data:byte(i + 1) or 0
    local b3 = data:byte(i + 2) or 0
    local n = (b1 << 16) | (b2 << 8) | b3
    out[#out + 1] = B64:sub(((n >> 18) & 0x3F) + 1, ((n >> 18) & 0x3F) + 1)
    out[#out + 1] = B64:sub(((n >> 12) & 0x3F) + 1, ((n >> 12) & 0x3F) + 1)
    if i + 1 <= #data then
      out[#out + 1] = B64:sub(((n >> 6) & 0x3F) + 1, ((n >> 6) & 0x3F) + 1)
    else
      out[#out + 1] = "="
    end
    if i + 2 <= #data then
      out[#out + 1] = B64:sub((n & 0x3F) + 1, (n & 0x3F) + 1)
    else
      out[#out + 1] = "="
    end
  end
  return table.concat(out)
end

----------------------------------------------------------------------
-- Set RS5K mode via binary state chunk modification
----------------------------------------------------------------------

local function set_rs5k_mode_note(track)
  -- RS5K mode is stored in the VST binary state at byte offset 8 (uint32 LE).
  -- Mode 0 = Sample, 1 = Note (Semitone shifted), 2 = Note (Frequency).
  -- The mode is NOT accessible via SetNamedConfigParm or SetParam.
  -- The 44-byte header is encoded as its own base64 segment (first line after VST header).
  -- Header starts with "mosr" magic (base64: "bW9z").

  local ok, chunk = reaper.GetTrackStateChunk(track, "", false)
  if not ok then return false end

  -- Find the RS5K VST block's first base64 line (starts with "bW9z" = "mosr" magic)
  local header_b64 = chunk:match("(bW9z[A-Za-z0-9+/]+=*)")
  if not header_b64 then
    log("[WARNING] Could not find RS5K header in track chunk")
    return false
  end

  -- Decode header
  local header_bin = b64_decode(header_b64)
  if #header_bin < 12 then
    log("[WARNING] RS5K header too short: " .. #header_bin .. " bytes")
    return false
  end

  -- Verify magic "mosr" at bytes 0-3
  if header_bin:sub(1, 4) ~= "mosr" then
    log("[WARNING] RS5K header magic mismatch: " .. header_bin:sub(1, 4))
    return false
  end

  -- Set byte 8 to 1 (Note Semitone shifted mode)
  local current_mode = header_bin:byte(9) -- Lua strings are 1-indexed
  if current_mode == 1 then
    return true -- already in the right mode
  end

  header_bin = header_bin:sub(1, 8) .. string.char(1) .. header_bin:sub(10)

  -- Re-encode
  local new_header_b64 = b64_encode(header_bin)

  -- Replace in chunk
  chunk = chunk:gsub(header_b64, new_header_b64, 1)

  -- Set the modified chunk back
  reaper.SetTrackStateChunk(track, chunk, false)
  log("  RS5K mode set to Note (Semitone shifted) via chunk edit")
  return true
end

----------------------------------------------------------------------
-- Load sample into RS5K on a track
----------------------------------------------------------------------

local function load_rs5k(track, sample_path, track_name)
  -- Add RS5K without opening its UI window
  local fx_idx = reaper.TrackFX_AddByName(track, "ReaSamplOmatic5000", false, -1000)
  if fx_idx < 0 then
    fx_idx = reaper.TrackFX_AddByName(track, "ReaSamplOmatic5000", false, -1)
  end
  if fx_idx < 0 then
    log("[WARNING] Could not add RS5K to '" .. track_name .. "'")
    return false
  end

  -- Load sample file
  reaper.TrackFX_SetNamedConfigParm(track, fx_idx, "FILE0", sample_path)
  reaper.TrackFX_SetNamedConfigParm(track, fx_idx, "DONE", "")

  -- Set note range: full 0-127
  reaper.TrackFX_SetParam(track, fx_idx, 3, 0.0)
  reaper.TrackFX_SetParam(track, fx_idx, 4, 1.0)

  -- Enable "Obey note-offs" (param 11)
  reaper.TrackFX_SetParam(track, fx_idx, 11, 1.0)

  -- Set mode to "Note (Semitone shifted)" via binary chunk modification
  set_rs5k_mode_note(track)

  return true
end

----------------------------------------------------------------------
-- Main
----------------------------------------------------------------------

local function main()
  log("=== " .. SCRIPT_NAME .. " ===")

  -- Prompt for samples directory
  local default_path = "/home/spencer/snes/snes_music/samples"
  local ok, samples_dir = reaper.GetUserInputs(
    SCRIPT_NAME, 1,
    "Samples directory (WAV files from .gsi converter):,extrawidth=300",
    default_path
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

  -- Force-close all FX windows (belt and suspenders)
  for i = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, i)
    local fx_count = reaper.TrackFX_GetCount(track)
    for j = 0, fx_count - 1 do
      reaper.TrackFX_SetOpen(track, j, false)
    end
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
