"""Build manifest generation."""

from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path

VALIDATOR_VERSION = "0.1.0"
ENGINE_TARGET = "SNESGSS"


def _sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()


def generate_manifest(
    export_dir: Path,
    passed: bool,
    output_files: list[Path],
) -> dict:
    manifest = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "engine_target": ENGINE_TARGET,
        "validator_version": VALIDATOR_VERSION,
        "status": "PASS" if passed else "FAIL",
        "source_hash": _sha256(export_dir / "snes_export.json"),
        "files": [],
    }
    for f in output_files:
        if f.exists():
            manifest["files"].append({
                "path": f.name,
                "sha256": _sha256(f),
            })
    return manifest


def write_manifest(export_dir: Path, manifest: dict) -> Path:
    path = export_dir / "build_manifest.json"
    with open(path, "w") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")
    return path
