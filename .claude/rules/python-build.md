# Python build/validation CLI conventions

## Scope
Files in `tools/validate/`.

## Runtime
- Python 3.11+
- No heavy dependencies — prefer stdlib where possible
- Use `pyproject.toml` for project metadata if packaging is needed
- Pin versions in `requirements.txt` if external deps are added

## CLI conventions
- Entry point: `python -m tools.validate` or a named CLI script
- Accept input directory (the Lua exporter's output) as a required argument
- Write validation report and build manifest to the output directory
- Exit code 0 = pass, 1 = validation errors, 2 = fatal/unexpected error

## Testing
- Framework: `pytest`
- Test files: `tests/` directory at repo root
- Fixtures live in `docs/fixtures/` — tests reference them by path
- Run: `pytest` from repo root

## Relationship to Lua exporter
- The Python CLI is a **second-pass validator**, not a replacement for the Lua exporter
- It consumes the intermediate JSON and constrained MIDI produced by the Lua script
- It does NOT read REAPER project files directly
- It adds: manifest generation, hash verification, regression checks, ARAM budget estimation
