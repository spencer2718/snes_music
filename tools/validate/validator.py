"""Core validation logic for SNES export JSON."""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path

MAX_CHANNELS = 8
ARAM_TOTAL_KB = 64
ARAM_ENGINE_OVERHEAD_KB = 32  # rough: engine + echo leaves ~32KB for samples
SAMPLE_ESTIMATE_KB = 2  # placeholder per-track sample budget
PITCH_WARN_LOW = 24
PITCH_WARN_HIGH = 96


@dataclass
class Finding:
    level: str  # "error", "warning", "info"
    message: str


@dataclass
class ValidationResult:
    findings: list[Finding] = field(default_factory=list)

    def error(self, msg: str) -> None:
        self.findings.append(Finding("error", msg))

    def warning(self, msg: str) -> None:
        self.findings.append(Finding("warning", msg))

    def info(self, msg: str) -> None:
        self.findings.append(Finding("info", msg))

    @property
    def errors(self) -> list[Finding]:
        return [f for f in self.findings if f.level == "error"]

    @property
    def warnings(self) -> list[Finding]:
        return [f for f in self.findings if f.level == "warning"]

    @property
    def infos(self) -> list[Finding]:
        return [f for f in self.findings if f.level == "info"]

    @property
    def passed(self) -> bool:
        return len(self.errors) == 0


def load_export(export_dir: Path) -> dict:
    path = export_dir / "snes_export.json"
    with open(path) as f:
        return json.load(f)


def validate(data: dict, export_dir: Path | None = None) -> ValidationResult:
    result = ValidationResult()
    tracks = data.get("tracks", [])
    tempo_map = data.get("tempo_map", [])
    regions = data.get("regions", [])

    _check_channel_count(tracks, result)
    _check_monophonic(tracks, result)
    _check_note_range(tracks, result)
    _check_tempo_map(tempo_map, result)
    _check_empty_tracks(tracks, result)
    _check_velocity(tracks, result)
    _check_regions(regions, result)
    _check_aram_budget(tracks, result)

    if export_dir is not None:
        _check_midi_file(export_dir, result)

    return result


def _check_channel_count(tracks: list[dict], result: ValidationResult) -> None:
    if len(tracks) > MAX_CHANNELS:
        result.error(
            f"Channel count {len(tracks)} exceeds SNES limit of {MAX_CHANNELS}"
        )


def _check_monophonic(tracks: list[dict], result: ValidationResult) -> None:
    for track in tracks:
        name = track.get("name", "?")
        channel = track.get("midi_channel", "?")
        notes = track.get("notes", [])
        sorted_notes = sorted(notes, key=lambda n: (n["start_beats"], n["pitch"]))
        overlap_count = 0
        first_beat = None
        for i in range(1, len(sorted_notes)):
            prev = sorted_notes[i - 1]
            curr = sorted_notes[i]
            prev_end = prev["start_beats"] + prev["duration_beats"]
            if curr["start_beats"] < prev_end:
                overlap_count += 1
                if first_beat is None:
                    first_beat = curr["start_beats"]
        if overlap_count > 0:
            result.error(
                f"Overlap on '{name}' (ch {channel}): "
                f"{overlap_count} overlapping note(s), first at beat {first_beat}"
            )


def _check_note_range(tracks: list[dict], result: ValidationResult) -> None:
    for track in tracks:
        name = track.get("name", "?")
        for note in track.get("notes", []):
            pitch = note["pitch"]
            if pitch < 0 or pitch > 127:
                result.error(f"Illegal MIDI pitch {pitch} on '{name}'")
            elif pitch < PITCH_WARN_LOW or pitch > PITCH_WARN_HIGH:
                result.warning(
                    f"Unusual SNES pitch {pitch} on '{name}' "
                    f"(outside {PITCH_WARN_LOW}-{PITCH_WARN_HIGH})"
                )


def _check_tempo_map(tempo_map: list[dict], result: ValidationResult) -> None:
    if not tempo_map:
        result.warning("No tempo map entries")
    elif len(tempo_map) > 1:
        result.warning(
            f"Multiple tempo changes ({len(tempo_map)}) — "
            f"supported but worth reviewing"
        )


def _check_empty_tracks(tracks: list[dict], result: ValidationResult) -> None:
    for track in tracks:
        if not track.get("notes"):
            result.warning(f"Track '{track.get('name', '?')}' has zero notes")


def _check_velocity(tracks: list[dict], result: ValidationResult) -> None:
    all_velocities = set()
    for track in tracks:
        for note in track.get("notes", []):
            all_velocities.add(note["velocity"])
    if len(all_velocities) <= 1:
        result.info("No velocity variation — all notes at same velocity")
    else:
        result.info(
            f"Velocity variation present: {min(all_velocities)}-{max(all_velocities)} "
            f"({len(all_velocities)} distinct values)"
        )


def _check_regions(regions: list[dict], result: ValidationResult) -> None:
    result.info(f"Regions: {len(regions)}")
    for region in regions:
        name = region.get("name", "unnamed")
        start = region.get("start_beats", 0)
        end_ = region.get("end_beats", 0)
        result.info(f"  Region '{name}': beats {start}-{end_}")


def _check_midi_file(export_dir: Path, result: ValidationResult) -> None:
    midi_path = export_dir / "snes_export.mid"
    if not midi_path.exists():
        result.warning("Constrained MIDI file (snes_export.mid) not found in export directory")
    else:
        size = midi_path.stat().st_size
        result.info(f"Constrained MIDI file present ({size} bytes)")


def _check_aram_budget(tracks: list[dict], result: ValidationResult) -> None:
    sample_budget_kb = ARAM_TOTAL_KB - ARAM_ENGINE_OVERHEAD_KB
    estimated_usage_kb = len(tracks) * SAMPLE_ESTIMATE_KB
    result.info(
        f"ARAM estimate: {estimated_usage_kb}KB / {sample_budget_kb}KB sample budget "
        f"({len(tracks)} tracks × {SAMPLE_ESTIMATE_KB}KB placeholder)"
    )
    if estimated_usage_kb > sample_budget_kb:
        result.warning(
            f"ARAM estimate exceeds budget: "
            f"{estimated_usage_kb}KB > {sample_budget_kb}KB"
        )
