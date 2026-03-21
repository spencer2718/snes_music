"""CLI entry point for .gsi to WAV conversion.

Usage:
  python -m tools.samples convert <gsi_file_or_dir> --output <dir>
  python -m tools.samples default --output <dir>
"""

import re
import sys
from pathlib import Path

from .gsi_parser import parse_gsi
from .wav_writer import write_wav

# Default SNESGSS instruments directory
SNESGSS_INSTRUMENTS = Path.home() / "snes" / "snesgss" / "instruments"
DEFAULT_SET_FILE = Path(__file__).parent / "default_set.txt"


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
              f"({len(inst.samples)} samples, {inst.source_rate} Hz) "
              f"(pitch-corrected B+21→C)")
        return True
    except Exception as e:
        print(f"  ERR  {gsi_path.name}: {e}")
        return False


def find_output_dir(args: list[str]) -> Path | None:
    """Parse --output <dir> from args."""
    for i, arg in enumerate(args):
        if arg == "--output" and i + 1 < len(args):
            return Path(args[i + 1])
    return None


def cmd_convert(args: list[str]) -> int:
    """Handle 'convert' subcommand."""
    if len(args) < 3:
        print("Usage: python -m tools.samples convert <gsi_file_or_dir> --output <dir>",
              file=sys.stderr)
        return 2

    source = Path(args[0])
    output_dir = find_output_dir(args[1:])

    if output_dir is None:
        print("Error: --output <dir> is required", file=sys.stderr)
        return 2

    output_dir.mkdir(parents=True, exist_ok=True)

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


def cmd_default(args: list[str]) -> int:
    """Handle 'default' subcommand — convert the curated default set."""
    output_dir = find_output_dir(args)
    if output_dir is None:
        print("Usage: python -m tools.samples default --output <dir>", file=sys.stderr)
        return 2

    if not DEFAULT_SET_FILE.exists():
        print(f"Error: {DEFAULT_SET_FILE} not found", file=sys.stderr)
        return 2

    if not SNESGSS_INSTRUMENTS.is_dir():
        print(f"Error: SNESGSS instruments not found at {SNESGSS_INSTRUMENTS}", file=sys.stderr)
        print("Clone https://github.com/nathancassano/snesgss to ~/snes/snesgss/", file=sys.stderr)
        return 2

    filenames = [
        line.strip() for line in DEFAULT_SET_FILE.read_text().splitlines()
        if line.strip() and not line.strip().startswith("#")
    ]

    if not filenames:
        print("Error: default_set.txt is empty", file=sys.stderr)
        return 2

    output_dir.mkdir(parents=True, exist_ok=True)
    print(f"Converting {len(filenames)} default instruments to {output_dir}/")

    success = 0
    errors = 0
    for idx, filename in enumerate(filenames, 1):
        gsi_path = SNESGSS_INSTRUMENTS / filename
        if not gsi_path.exists():
            print(f"  ERR  {filename}: not found in {SNESGSS_INSTRUMENTS}")
            errors += 1
            continue
        if convert_gsi(gsi_path, output_dir, idx):
            success += 1
        else:
            errors += 1

    print(f"\nDone: {success} converted, {errors} errors/skipped")
    return 0 if errors == 0 else 1


def main() -> int:
    if len(sys.argv) < 2:
        print(
            "Usage:\n"
            "  python -m tools.samples convert <gsi_file_or_dir> --output <dir>\n"
            "  python -m tools.samples default --output <dir>",
            file=sys.stderr,
        )
        return 2

    cmd = sys.argv[1]
    if cmd == "convert":
        return cmd_convert(sys.argv[2:])
    elif cmd == "default":
        return cmd_default(sys.argv[2:])
    else:
        print(f"Unknown command: {cmd}", file=sys.stderr)
        return 2


sys.exit(main())
