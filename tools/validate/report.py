"""Human-readable validation report generation."""

from __future__ import annotations

from pathlib import Path

from .validator import ValidationResult


def format_report(result: ValidationResult) -> str:
    lines = []

    status = "PASS" if result.passed else "FAIL"
    lines.append(f"=== Validation Report: {status} ===")
    lines.append(
        f"Errors: {len(result.errors)}  "
        f"Warnings: {len(result.warnings)}  "
        f"Info: {len(result.infos)}"
    )
    lines.append("")

    if result.errors:
        lines.append("--- ERRORS ---")
        for f in result.errors:
            lines.append(f"  [ERROR] {f.message}")
        lines.append("")

    if result.warnings:
        lines.append("--- WARNINGS ---")
        for f in result.warnings:
            lines.append(f"  [WARN]  {f.message}")
        lines.append("")

    if result.infos:
        lines.append("--- INFO ---")
        for f in result.infos:
            lines.append(f"  [INFO]  {f.message}")
        lines.append("")

    return "\n".join(lines)


def write_report(export_dir: Path, result: ValidationResult) -> Path:
    path = export_dir / "validation_report.txt"
    path.write_text(format_report(result))
    return path
