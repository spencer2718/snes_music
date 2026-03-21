# Test fixtures conventions

## Scope
Test data in `docs/fixtures/` and test code in `tests/`.

## Fixture location
- All fixtures live in `docs/fixtures/`
- Each fixture is a directory named for the test case (e.g., `docs/fixtures/four_channel_basic/`)

## Fixture contents
A fixture directory contains:
- Input file(s) — intermediate JSON, constrained MIDI, or both
- `expected.md` — human-readable description of expected behavior and validation results
- Optional: expected output files for regression comparison

## Adding a new fixture
1. Create a directory under `docs/fixtures/` with a descriptive snake_case name
2. Add input files representing the test scenario
3. Write `expected.md` describing what the validator should report
4. Reference the fixture in a pytest test in `tests/`

## What a passing export looks like
- Intermediate JSON is valid and contains all expected fields
- Constrained MIDI has correct track count and no unsupported events
- Validation report lists zero errors (warnings are acceptable)
- Build manifest includes hashes for all output files and a timestamp
- No unsupported REAPER features were silently dropped
