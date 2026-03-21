-- debug_rs5k_chunk.lua
-- Diagnostic script: dumps RS5K state chunk in hex + decoded doubles.
-- Run after snes_project_setup.lua to inspect the RS5K binary state.
-- Reads from track index 1 (first instrument track).

local function log(msg)
  reaper.ShowConsoleMsg(msg .. "\n")
end

----------------------------------------------------------------------
-- Base64 decoder (pure Lua, no external deps)
----------------------------------------------------------------------

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_DECODE = {}
for i = 1, #B64 do
  B64_DECODE[B64:byte(i)] = i - 1
end
B64_DECODE[string.byte("=")] = 0

local function b64_decode(data)
  data = data:gsub("%s+", "") -- strip whitespace
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

----------------------------------------------------------------------
-- Hex dump
----------------------------------------------------------------------

local function hex_dump(data, max_bytes)
  max_bytes = max_bytes or #data
  local count = math.min(#data, max_bytes)
  for offset = 0, count - 1, 16 do
    local hex_parts = {}
    local ascii_parts = {}
    for i = 0, 15 do
      local pos = offset + i + 1
      if pos <= count then
        local byte = data:byte(pos)
        hex_parts[#hex_parts + 1] = string.format("%02X", byte)
        ascii_parts[#ascii_parts + 1] = (byte >= 32 and byte < 127) and string.char(byte) or "."
      else
        hex_parts[#hex_parts + 1] = "  "
        ascii_parts[#ascii_parts + 1] = " "
      end
    end
    log(string.format("%04X: %s  %s", offset, table.concat(hex_parts, " "), table.concat(ascii_parts)))
  end
end

----------------------------------------------------------------------
-- IEEE 754 double decoder (little-endian)
----------------------------------------------------------------------

local function bytes_to_double(data, offset)
  -- Lua 5.3 string.unpack
  if #data < offset + 8 then return nil end
  local d = string.unpack("<d", data, offset + 1)
  return d
end

----------------------------------------------------------------------
-- Main
----------------------------------------------------------------------

local function main()
  log("=== RS5K Chunk Debug ===")

  local track = reaper.GetTrack(0, 1) -- track index 1 = first instrument track
  if not track then
    log("ERROR: No track at index 1. Run snes_project_setup.lua first.")
    return
  end

  local ok, chunk = reaper.GetTrackStateChunk(track, "", false)
  if not ok then
    log("ERROR: Could not get track state chunk")
    return
  end

  -- Extract the base64 data from the <VST block for RS5K
  -- Pattern: lines of base64 between the VST header line and the closing >
  local vst_block = chunk:match("<VST.-reasamplomatic.-\n(.-)\n%s*>")
  if not vst_block then
    log("ERROR: Could not find RS5K VST block in chunk")
    log("Full chunk (first 2000 chars):")
    log(chunk:sub(1, 2000))
    return
  end

  log("Raw base64 block (first 500 chars):")
  log(vst_block:sub(1, 500))
  log("")

  -- Decode base64
  local binary = b64_decode(vst_block)
  log("Decoded binary: " .. #binary .. " bytes")
  log("")

  -- Hex dump first 200 bytes
  log("=== HEX DUMP (first 200 bytes) ===")
  hex_dump(binary, 200)
  log("")

  -- Find the null terminator after the file path
  -- The path typically starts after a header section
  local path_start = nil
  local path_end = nil

  -- Search for .wav in the binary to find the file path
  local wav_pos = binary:find("%.wav")
  if wav_pos then
    -- Walk backwards to find the start of the path
    local search_start = wav_pos
    while search_start > 1 and binary:byte(search_start) ~= 0 do
      search_start = search_start - 1
    end
    path_start = search_start + 1
    -- Walk forward to find the null terminator after .wav
    path_end = wav_pos + 4
    while path_end <= #binary and binary:byte(path_end) ~= 0 do
      path_end = path_end + 1
    end
    local path = binary:sub(path_start, path_end - 1)
    log("File path found at offset " .. (path_start - 1) .. ": " .. path)
    log("Path ends at offset " .. (path_end - 1))
    log("")
  else
    log("No .wav path found in binary data")
    path_end = 50 -- guess at where params start
  end

  -- Decode doubles after the file path
  -- Skip the null terminator and any padding
  local doubles_start = path_end
  -- Align to 8-byte boundary
  while doubles_start % 8 ~= 0 and doubles_start < #binary do
    doubles_start = doubles_start + 1
  end

  log("=== DOUBLES starting at offset " .. doubles_start .. " ===")
  local idx = 0
  local pos = doubles_start
  while pos + 8 <= #binary do
    local d = bytes_to_double(binary, pos)
    if d then
      local hex_bytes = {}
      for i = pos + 1, pos + 8 do
        hex_bytes[#hex_bytes + 1] = string.format("%02X", binary:byte(i))
      end
      log(string.format("  [%2d] offset %3d: %12.6f  (%s)", idx, pos, d, table.concat(hex_bytes, " ")))
    end
    pos = pos + 8
    idx = idx + 1
  end
  log("")
  log("=== END DEBUG ===")
end

if reaper then
  main()
else
  print("This script must be run inside REAPER as a ReaScript.")
end
