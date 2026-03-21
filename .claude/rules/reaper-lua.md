# ReaScript / Lua conventions

## Scope
Files in `tools/reaper/` that use the REAPER Lua API (ReaScript).

## Language
- Lua 5.3 (REAPER's embedded interpreter)
- No external Lua dependencies — only `reaper.*` API calls and standard library

## Conventions
- All scripts must be loadable via REAPER Actions > Load ReaScript
- Use `reaper.ShowConsoleMsg()` for debug output, never `print()`
- Wrap API calls that may fail with error checks
- snake_case for local functions and variables
- UPPER_CASE for module-level constants

## Export structure
- The Lua exporter scans the active REAPER project and writes output to a specified directory
- Output artifacts: intermediate JSON, constrained MIDI, validation report stub
- Export must be deterministic — same project state produces identical output
- Never silently drop unsupported REAPER features — log warnings for anything outside the supported subset

## Dependencies
- Do not depend on the JS ReaScript API extension (`js_ReaScriptAPI`)
- All scripts must work with vanilla REAPER + ReaScript only
- Check for optional API functions with `if reaper.FunctionName then` before calling

## REAPER version
- Target REAPER 6.x+ (ReaScript API is stable across 6.x and 7.x)
- Do not use deprecated API functions
