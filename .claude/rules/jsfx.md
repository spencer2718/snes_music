# JSFX conventions

## Scope
JSFX files in `tools/reaper/` (`.jsfx` extension).

## Language constraints
- JSFX is EEL2-based, not Lua — different syntax and semantics
- No external imports or libraries
- All state lives in slider variables, instance variables, or `gmem[]`
- String handling is limited — use `sprintf()` and `#string` literals
- No file I/O from JSFX — it only processes MIDI and draws UI

## MIDI processing (`@block`)
- Read MIDI via `midrecv(offset, msg1, msg2, msg3)`
- Note on: `(msg1 & 0xF0) == 0x90` and `msg3 > 0`
- Note off: `(msg1 & 0xF0) == 0x80` or note-on with velocity 0
- Channel: `msg1 & 0x0F` (0-indexed, display as 1-indexed)
- Always pass MIDI through with `midisend(offset, msg1, msg2, msg3)`

## UI drawing (`@gfx`)
- Keep drawing simple — JSFX `@gfx` is primitive (no widgets, no layout engine)
- Use `gfx_r/gfx_g/gfx_b` for colors, `gfx_rectto()` for filled rects, `gfx_drawstr()` for text
- Design for a small panel size (~400x200 px)
- Start with traffic-light style: green = OK, yellow = warning, red = error
- If the UI proves too noisy, fall back to minimal indicators and push detail to the validation report

## Known limitations
- No floating point precision guarantees in EEL2
- `@gfx` redraws are not synchronized with `@block` — use shared variables carefully
- Maximum slider count: 64
