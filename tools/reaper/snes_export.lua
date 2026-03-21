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
        channel = chan, -- 0-indexed internally
      }
    end
  end

  return notes
end

local function scan_tracks()
  local tracks = {}
  local num_tracks = reaper.CountTracks(0)

  for t = 0, num_tracks - 1 do
    local track = reaper.GetTrack(0, t)
    local ok, track_name = reaper.GetTrackName(track)
    if not ok then track_name = "Track " .. (t + 1) end

    local all_notes = {}
    local channels_seen = {}
    local num_items = reaper.CountTrackMediaItems(track)

    if num_items == 0 then
      warn("Track '" .. track_name .. "' has no MIDI items")
    end

    for item_idx = 0, num_items - 1 do
      local item = reaper.GetTrackMediaItem(track, item_idx)
      local num_takes = reaper.CountTakes(item)

      for take_idx = 0, num_takes - 1 do
        local take = reaper.GetTake(item, take_idx)
        if take and reaper.TakeIsMIDI(take) then
          local notes = get_notes_from_take(take)
          for _, note in ipairs(notes) do
            all_notes[#all_notes + 1] = note
            channels_seen[note.channel] = true
          end
        end
      end
    end

    -- Determine the primary MIDI channel for this track
    local primary_channel = nil
    local channel_list = {}
    for ch, _ in pairs(channels_seen) do
      channel_list[#channel_list + 1] = ch
    end

    if #channel_list == 1 then
      primary_channel = channel_list[1]
    elseif #channel_list > 1 then
      -- Multiple channels on one track — use the most common
      local counts = {}
      for _, note in ipairs(all_notes) do
        counts[note.channel] = (counts[note.channel] or 0) + 1
      end
      local max_count = 0
      for ch, count in pairs(counts) do
        if count > max_count then
          max_count = count
          primary_channel = ch
        end
      end
      warn("Track '" .. track_name .. "' has notes on multiple MIDI channels")
    end

    -- Warn about channels > 8
    for ch, _ in pairs(channels_seen) do
      if ch >= MAX_CHANNELS then
        warn("Track '" .. track_name .. "' has notes on channel " .. (ch + 1) .. " (>8)")
      end
    end

    -- Check for overlapping notes per channel
    local notes_by_channel = {}
    for _, note in ipairs(all_notes) do
      local ch = note.channel
      if not notes_by_channel[ch] then notes_by_channel[ch] = {} end
      notes_by_channel[ch][#notes_by_channel[ch] + 1] = note
    end

    for ch, ch_notes in pairs(notes_by_channel) do
      -- Sort by start time
      table.sort(ch_notes, function(a, b) return a.start_beats < b.start_beats end)
      for i = 2, #ch_notes do
        local prev_end = ch_notes[i-1].start_beats + ch_notes[i-1].duration_beats
        if ch_notes[i].start_beats < prev_end then
          warn("Track '" .. track_name .. "' channel " .. (ch + 1) .. ": overlapping notes at beat " .. json_number(ch_notes[i].start_beats))
        end
      end
    end

    -- Sort all notes by start time for deterministic output
    table.sort(all_notes, function(a, b)
      if a.start_beats ~= b.start_beats then return a.start_beats < b.start_beats end
      return a.pitch < b.pitch
    end)

    if #all_notes > 0 then
      tracks[#tracks + 1] = {
        name = track_name,
        midi_channel = primary_channel and (primary_channel + 1) or nil, -- 1-indexed for output
        notes = all_notes,
      }
    end
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
    local ret, val = reaper.GetUserInputs(SCRIPT_NAME, 1, "Output directory:,extrawidth=200", proj_path)
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
