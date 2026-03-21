-- snes_export.lua
-- ReaScript: Scans active REAPER project and exports MIDI data as JSON.
-- Raw extraction layer only — no validation or engine-specific output.

local SCRIPT_NAME = "SNES Export"
local MAX_CHANNELS = 8

----------------------------------------------------------------------
-- JSON helpers (no external deps — Lua 5.3 stdlib only)
----------------------------------------------------------------------

local function json_escape(s)
  s = s:gsub('\\', '\\\\')
  s = s:gsub('"', '\\"')
  s = s:gsub('\n', '\\n')
  s = s:gsub('\r', '\\r')
  s = s:gsub('\t', '\\t')
  return s
end

local function json_number(n)
  -- Round to 6 decimal places to keep output clean
  if n == math.floor(n) then
    return string.format("%d", n)
  else
    return string.format("%.6f", n)
  end
end

----------------------------------------------------------------------
-- Logging
----------------------------------------------------------------------

local warning_count = 0

local function log(msg)
  reaper.ShowConsoleMsg(msg .. "\n")
end

local function warn(msg)
  warning_count = warning_count + 1
  reaper.ShowConsoleMsg("[WARNING] " .. msg .. "\n")
end

----------------------------------------------------------------------
-- Tempo map extraction
----------------------------------------------------------------------

local function get_tempo_map()
  local tempo_entries = {}
  local num_markers = reaper.CountTempoTimeSigMarkers(0)

  for i = 0, num_markers - 1 do
    local ok, time_pos, measure_pos, beat_pos, bpm, time_sig_num, time_sig_den, is_linear
      = reaper.GetTempoTimeSigMarker(0, i)
    if ok then
      local qn = reaper.TimeMap2_timeToQN(0, time_pos)
      tempo_entries[#tempo_entries + 1] = {
        position_beats = qn,
        bpm = bpm,
        time_sig_num = time_sig_num,
        time_sig_den = time_sig_den,
      }
    end
  end

  -- If no markers, read the project default tempo
  if #tempo_entries == 0 then
    local bpm, bpi = reaper.GetProjectTimeSignature2(0)
    tempo_entries[1] = {
      position_beats = 0,
      bpm = bpm,
      time_sig_num = math.floor(bpi),
      time_sig_den = 4,
    }
  end

  return tempo_entries
end

----------------------------------------------------------------------
-- Region extraction (future loop markers)
----------------------------------------------------------------------

local function get_regions()
  local regions = {}
  local num_markers, num_regions = reaper.CountProjectMarkers(0)
  local total = num_markers + num_regions -- this is actually total count

  for i = 0, reaper.CountProjectMarkers(0) - 1 do
    local ok, is_region, pos, region_end, name, index = reaper.EnumProjectMarkers(i)
    if ok and is_region then
      local start_qn = reaper.TimeMap2_timeToQN(0, pos)
      local end_qn = reaper.TimeMap2_timeToQN(0, region_end)
      regions[#regions + 1] = {
        name = name,
        index = index,
        start_beats = start_qn,
        end_beats = end_qn,
      }
    end
  end

  return regions
end

----------------------------------------------------------------------
-- MIDI extraction per track
----------------------------------------------------------------------

local function get_notes_from_take(take)
  local notes = {}
  local ok, note_count = reaper.MIDI_CountEvts(take)
  if not ok then return notes end

  for i = 0, note_count - 1 do
    local ok2, selected, muted, start_ppq, end_ppq, chan, pitch, vel
      = reaper.MIDI_GetNote(take, i)
    if ok2 then
      local start_qn = reaper.MIDI_GetProjQNFromPPQPos(take, start_ppq)
      local end_qn = reaper.MIDI_GetProjQNFromPPQPos(take, end_ppq)
      notes[#notes + 1] = {
        pitch = pitch,
        velocity = vel,
        start_beats = start_qn,
        duration_beats = end_qn - start_qn,
      }
    end
  end

  return notes
end

local function track_has_midi(track)
  local num_items = reaper.CountTrackMediaItems(track)
  for item_idx = 0, num_items - 1 do
    local item = reaper.GetTrackMediaItem(track, item_idx)
    local num_takes = reaper.CountTakes(item)
    for take_idx = 0, num_takes - 1 do
      local take = reaper.GetTake(item, take_idx)
      if take and reaper.TakeIsMIDI(take) then
        return true
      end
    end
  end
  return false
end

local function scan_tracks()
  local tracks = {}
  local num_tracks = reaper.CountTracks(0)
  local midi_track_index = 0 -- counts MIDI-containing tracks for channel assignment

  for t = 0, num_tracks - 1 do
    local track = reaper.GetTrack(0, t)
    local ok, track_name = reaper.GetTrackName(track)
    if not ok then track_name = "Track " .. (t + 1) end

    -- Skip tracks with no MIDI items (e.g., the monitor track)
    if not track_has_midi(track) then
      goto continue
    end

    midi_track_index = midi_track_index + 1

    -- Cap at 8 SNES voices
    if midi_track_index > MAX_CHANNELS then
      warn("Track '" .. track_name .. "' exceeds 8-channel limit (position " .. midi_track_index .. "), skipping")
      goto continue
    end

    -- Collect all notes from this track
    local all_notes = {}
    local num_items = reaper.CountTrackMediaItems(track)

    for item_idx = 0, num_items - 1 do
      local item = reaper.GetTrackMediaItem(track, item_idx)
      local num_takes = reaper.CountTakes(item)

      for take_idx = 0, num_takes - 1 do
        local take = reaper.GetTake(item, take_idx)
        if take and reaper.TakeIsMIDI(take) then
          local notes = get_notes_from_take(take)
          for _, note in ipairs(notes) do
            all_notes[#all_notes + 1] = note
          end
        end
      end
    end

    -- Check for overlapping notes (track = channel = must be monophonic)
    table.sort(all_notes, function(a, b)
      if a.start_beats ~= b.start_beats then return a.start_beats < b.start_beats end
      return a.pitch < b.pitch
    end)

    local overlap_count = 0
    local first_overlap_beat = nil
    for i = 2, #all_notes do
      local prev_end = all_notes[i-1].start_beats + all_notes[i-1].duration_beats
      if all_notes[i].start_beats < prev_end then
        overlap_count = overlap_count + 1
        if not first_overlap_beat then
          first_overlap_beat = all_notes[i].start_beats
        end
      end
    end
    if overlap_count > 0 then
      warn("Track '" .. track_name .. "' (channel " .. midi_track_index .. "): " .. overlap_count .. " overlapping note(s), first at beat " .. json_number(first_overlap_beat))
    end

    tracks[#tracks + 1] = {
      name = track_name,
      midi_channel = midi_track_index, -- assigned by position, 1-indexed
      notes = all_notes,
    }

    ::continue::
  end

  return tracks
end

----------------------------------------------------------------------
-- JSON serialization
----------------------------------------------------------------------

local function serialize_tempo_map(entries)
  local parts = {}
  for _, e in ipairs(entries) do
    parts[#parts + 1] = string.format(
      '    {"position_beats": %s, "bpm": %s, "time_sig_num": %d, "time_sig_den": %d}',
      json_number(e.position_beats), json_number(e.bpm),
      e.time_sig_num, e.time_sig_den)
  end
  return "[\n" .. table.concat(parts, ",\n") .. "\n  ]"
end

local function serialize_regions(regions)
  if #regions == 0 then return "[]" end
  local parts = {}
  for _, r in ipairs(regions) do
    parts[#parts + 1] = string.format(
      '    {"name": "%s", "index": %d, "start_beats": %s, "end_beats": %s}',
      json_escape(r.name), r.index,
      json_number(r.start_beats), json_number(r.end_beats))
  end
  return "[\n" .. table.concat(parts, ",\n") .. "\n  ]"
end

local function serialize_notes(notes)
  if #notes == 0 then return "[]" end
  local parts = {}
  for _, n in ipairs(notes) do
    parts[#parts + 1] = string.format(
      '        {"pitch": %d, "velocity": %d, "start_beats": %s, "duration_beats": %s}',
      n.pitch, n.velocity,
      json_number(n.start_beats), json_number(n.duration_beats))
  end
  return "[\n" .. table.concat(parts, ",\n") .. "\n      ]"
end

local function serialize_tracks(tracks)
  if #tracks == 0 then return "[]" end
  local parts = {}
  for _, t in ipairs(tracks) do
    local ch_str = t.midi_channel and tostring(t.midi_channel) or "null"
    parts[#parts + 1] = string.format(
      '    {\n      "name": "%s",\n      "midi_channel": %s,\n      "notes": %s\n    }',
      json_escape(t.name), ch_str, serialize_notes(t.notes))
  end
  return "[\n" .. table.concat(parts, ",\n") .. "\n  ]"
end

local function build_json(project_name, tempo_map, regions, tracks)
  return string.format(
    '{\n  "project_name": "%s",\n  "tempo_map": %s,\n  "regions": %s,\n  "tracks": %s\n}\n',
    json_escape(project_name),
    serialize_tempo_map(tempo_map),
    serialize_regions(regions),
    serialize_tracks(tracks))
end

----------------------------------------------------------------------
-- Constrained MIDI file writer (Format 1, raw binary, no library)
----------------------------------------------------------------------

local MIDI_PPQ = 480 -- ticks per quarter note

local function write_u8(f, val)
  f:write(string.char(val & 0xFF))
end

local function write_u16be(f, val)
  f:write(string.char((val >> 8) & 0xFF, val & 0xFF))
end

local function write_u32be(f, val)
  f:write(string.char(
    (val >> 24) & 0xFF,
    (val >> 16) & 0xFF,
    (val >> 8) & 0xFF,
    val & 0xFF
  ))
end

local function encode_vlq(value)
  value = math.floor(value + 0.5)
  if value < 0 then value = 0 end
  if value < 0x80 then
    return string.char(value)
  end
  local bytes = {}
  bytes[1] = value & 0x7F
  value = value >> 7
  while value > 0 do
    table.insert(bytes, 1, (value & 0x7F) | 0x80)
    value = value >> 7
  end
  local chars = {}
  for _, b in ipairs(bytes) do
    chars[#chars + 1] = string.char(b)
  end
  return table.concat(chars)
end

local function beats_to_ticks(beats)
  return math.floor(beats * MIDI_PPQ + 0.5)
end

local function bpm_to_tempo_us(bpm)
  return math.floor(60000000 / bpm + 0.5)
end

local function build_tempo_track(tempo_map)
  local events = {}
  for _, entry in ipairs(tempo_map) do
    local tick = beats_to_ticks(entry.position_beats)
    local us = bpm_to_tempo_us(entry.bpm)
    -- Meta event: FF 51 03 tt tt tt
    local data = string.char(
      0xFF, 0x51, 0x03,
      (us >> 16) & 0xFF,
      (us >> 8) & 0xFF,
      us & 0xFF
    )
    events[#events + 1] = { tick = tick, data = data }
  end
  -- Sort by tick
  table.sort(events, function(a, b) return a.tick < b.tick end)
  -- Build track data with delta times
  local parts = {}
  local prev_tick = 0
  for _, evt in ipairs(events) do
    local delta = evt.tick - prev_tick
    parts[#parts + 1] = encode_vlq(delta)
    parts[#parts + 1] = evt.data
    prev_tick = evt.tick
  end
  -- End of track: delta=0, FF 2F 00
  parts[#parts + 1] = encode_vlq(0)
  parts[#parts + 1] = string.char(0xFF, 0x2F, 0x00)
  return table.concat(parts)
end

local function build_note_track(track_data)
  local ch = (track_data.midi_channel - 1) & 0x0F -- 0-indexed for MIDI bytes
  local events = {}

  for _, note in ipairs(track_data.notes) do
    local start_tick = beats_to_ticks(note.start_beats)
    local end_tick = beats_to_ticks(note.start_beats + note.duration_beats)
    -- Note on: 9n kk vv
    events[#events + 1] = {
      tick = start_tick,
      data = string.char(0x90 | ch, note.pitch & 0x7F, note.velocity & 0x7F),
      sort_order = 0, -- note-on before note-off at same tick
    }
    -- Note off: 8n kk 40
    events[#events + 1] = {
      tick = end_tick,
      data = string.char(0x80 | ch, note.pitch & 0x7F, 0x40),
      sort_order = 1, -- note-off after note-on at same tick
    }
  end

  -- Sort by tick, then note-off before note-on at same tick
  table.sort(events, function(a, b)
    if a.tick ~= b.tick then return a.tick < b.tick end
    return a.sort_order > b.sort_order
  end)

  -- Build track data with delta times
  local parts = {}
  local prev_tick = 0
  for _, evt in ipairs(events) do
    local delta = evt.tick - prev_tick
    parts[#parts + 1] = encode_vlq(delta)
    parts[#parts + 1] = evt.data
    prev_tick = evt.tick
  end
  -- End of track
  parts[#parts + 1] = encode_vlq(0)
  parts[#parts + 1] = string.char(0xFF, 0x2F, 0x00)
  return table.concat(parts)
end

local function write_midi_file(output_path, tempo_map, tracks)
  local f = io.open(output_path, "wb")
  if not f then
    log("ERROR: Could not write MIDI to " .. output_path)
    return false
  end

  local num_tracks = 1 + #tracks -- tempo track + note tracks
  local total_notes = 0

  -- MThd header
  f:write("MThd")
  write_u32be(f, 6)         -- header length
  write_u16be(f, 1)         -- format 1
  write_u16be(f, num_tracks) -- number of tracks
  write_u16be(f, MIDI_PPQ)  -- ticks per quarter note

  -- Track 0: tempo map
  local tempo_data = build_tempo_track(tempo_map)
  f:write("MTrk")
  write_u32be(f, #tempo_data)
  f:write(tempo_data)

  -- Tracks 1–N: note data
  for _, track_data in ipairs(tracks) do
    local track_bytes = build_note_track(track_data)
    f:write("MTrk")
    write_u32be(f, #track_bytes)
    f:write(track_bytes)
    total_notes = total_notes + #track_data.notes
  end

  f:close()
  log("Wrote: " .. output_path)
  log("  MIDI tracks: " .. num_tracks .. " (1 tempo + " .. #tracks .. " note)")
  log("  Total notes: " .. total_notes)
  return true
end

----------------------------------------------------------------------
-- Main
----------------------------------------------------------------------

local function main()
  log("=== " .. SCRIPT_NAME .. " ===")

  -- Get project name
  local proj_path = reaper.GetProjectPath()
  local _, proj_file = reaper.EnumProjects(-1)
  local project_name = "Untitled"
  if proj_file and proj_file ~= "" then
    project_name = proj_file:match("([^/\\]+)%.RPP$") or proj_file:match("([^/\\]+)$") or "Untitled"
  end
  log("Project: " .. project_name)

  -- Choose output directory (no JS extension dependency)
  local ok = false
  local output_dir = nil

  -- Try JS folder browser if the extension happens to be installed
  if reaper.JS_Dialog_BrowseForFolder then
    local js_ok, js_dir = reaper.JS_Dialog_BrowseForFolder("Select export output folder", proj_path)
    if js_ok and js_dir and js_dir ~= "" then
      output_dir = js_dir
      ok = true
    end
  end

  -- Fallback: text input dialog (vanilla REAPER)
  if not ok then
    local script_path = ({reaper.get_action_context()})[2]
    local repo_root = script_path:match("(.*)/tools/reaper/") or ""
    local default_export = repo_root ~= "" and (repo_root .. "/exports") or ""
    local ret, val = reaper.GetUserInputs(SCRIPT_NAME, 1, "Output directory:,extrawidth=200", default_export)
    if ret and val ~= "" then
      output_dir = val
      ok = true
    end
  end

  -- Last resort: confirm project path via message box
  if not ok then
    local confirm = reaper.MB("Export to:\n" .. proj_path .. "\n\nOK?", SCRIPT_NAME, 1)
    if confirm == 1 then -- OK
      output_dir = proj_path
      ok = true
    end
  end

  if not ok then
    log("Export cancelled.")
    return
  end

  log("Output directory: " .. output_dir)
  log("Scanning project...")

  -- Collect data
  local tempo_map = get_tempo_map()
  log("  Tempo entries: " .. #tempo_map)

  local regions = get_regions()
  log("  Regions: " .. #regions)

  local tracks = scan_tracks()
  log("  Tracks with MIDI: " .. #tracks)

  -- Warn if non-MIDI tracks are interspersed between MIDI tracks
  local total_project_tracks = reaper.CountTracks(0)
  if #tracks > 0 and total_project_tracks > #tracks + 1 then
    warn("Non-MIDI track(s) detected between MIDI tracks — channel assignment may not match the monitor. Use contiguous MIDI tracks.")
  end

  -- Serialize
  local json = build_json(project_name, tempo_map, regions, tracks)

  -- Write output
  local output_path = output_dir .. "/snes_export.json"
  local f = io.open(output_path, "w")
  if not f then
    log("ERROR: Could not write to " .. output_path)
    return
  end
  f:write(json)
  f:close()

  log("Wrote: " .. output_path)

  -- Write constrained MIDI file
  local midi_path = output_dir .. "/snes_export.mid"
  write_midi_file(midi_path, tempo_map, tracks)

  if warning_count > 0 then
    log("Completed with " .. warning_count .. " warning(s).")
  else
    log("Export complete. No warnings.")
  end
end

-- Guard: check we're running inside REAPER
if reaper then
  main()
else
  print("This script must be run inside REAPER as a ReaScript.")
end
