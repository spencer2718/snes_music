"""CLI entry point: python -m tools.samples convert <gsi_file_or_dir> --output <dir>"""

import re
import sys
from pathlib import Path

from .gsi_parser import parse_gsi
from .wav_writer import write_wav


def sanitize_name(name: str) -> str:
    """Convert instrument name to snake_case filename."""
    name = name.lower().strip()
    name = re.sub(r"[^a-z0-9]+", "_", name)
    name = name.strip("_")
    return name or "instrument"


def convert_gsi(gsi_path: Path, output_dir: Path, index: int) -> bool:
    """Convert a single .gsi file to WAV. Returns True on success."""
    try:
        inst = parse_gsi(gsi_path)
        if not inst.samples:
            print(f"  SKIP {gsi_path.name}: no sample data")
            return False

        safe_name = sanitize_name(inst.name)
        wav_name = f"{index:02d}_{safe_name}.wav"
        wav_path = output_dir / wav_name

        write_wav(inst.samples, inst.source_rate, wav_path)
        print(f"  OK   {gsi_path.name} → {wav_name} "
              f"({len(inst.samples)} samples, {inst.source_rate} Hz)")
        return True
    except Exception as e:
        print(f"  ERR  {gsi_path.name}: {e}")
        return False


def main() -> int:
    if len(sys.argv) < 4 or sys.argv[1] != "convert":
        print(
            "Usage: python -m tools.samples convert <gsi_file_or_dir> --output <dir>",
            file=sys.stderr,
        )
        return 2

    source = Path(sys.argv[2])
    output_dir = None

    for i, arg in enumerate(sys.argv[3:], 3):
        if arg == "--output" and i + 1 < len(sys.argv):
            output_dir = Path(sys.argv[i + 1])
            break

    if output_dir is None:
        print("Error: --output <dir> is required", file=sys.stderr)
        return 2

    output_dir.mkdir(parents=True, exist_ok=True)

    # Collect .gsi files
    if source.is_file():
        gsi_files = [source]
    elif source.is_dir():
        gsi_files = sorted(source.glob("*.gsi"))
    else:
        print(f"Error: {source} not found", file=sys.stderr)
        return 2

    if not gsi_files:
        print(f"No .gsi files found in {source}")
        return 1

    print(f"Converting {len(gsi_files)} .gsi file(s) to {output_dir}/")

    success = 0
    errors = 0
    for idx, gsi_path in enumerate(gsi_files, 1):
        if convert_gsi(gsi_path, output_dir, idx):
            success += 1
        else:
            errors += 1

    print(f"\nDone: {success} converted, {errors} errors/skipped")
    return 0 if errors == 0 else 1


sys.exit(main())
