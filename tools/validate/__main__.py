"""CLI entry point: python -m tools.validate <export_dir>"""

import sys
from pathlib import Path

from .manifest import generate_manifest, write_manifest
from .report import format_report, write_report
from .validator import load_export, validate


def main() -> int:
    if len(sys.argv) < 2:
        print("Usage: python -m tools.validate <export_dir>", file=sys.stderr)
        return 2

    export_dir = Path(sys.argv[1])
    json_path = export_dir / "snes_export.json"

    if not json_path.exists():
        print(f"Error: {json_path} not found", file=sys.stderr)
        return 2

    try:
        data = load_export(export_dir)
    except Exception as e:
        print(f"Error loading export: {e}", file=sys.stderr)
        return 2

    result = validate(data)

    report_path = write_report(export_dir, result)
    report_text = format_report(result)

    output_files = [json_path, report_path]
    manifest = generate_manifest(export_dir, result.passed, output_files)
    manifest_path = write_manifest(export_dir, manifest)

    print(report_text)
    print(f"Report: {report_path}")
    print(f"Manifest: {manifest_path}")

    return 0 if result.passed else 1


sys.exit(main())
