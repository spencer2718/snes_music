"""Tests for the SNES export validator."""

import json
from pathlib import Path

from tools.validate.validator import validate

FIXTURE_DIR = Path(__file__).parent.parent / "docs" / "fixtures" / "four_channel_basic"


def test_four_channel_basic_passes():
    """The four_channel_basic fixture should pass with 0 errors."""
    with open(FIXTURE_DIR / "sample_export.json") as f:
        data = json.load(f)
    result = validate(data)
    assert result.passed, (
        f"Expected PASS but got errors: "
        f"{[e.message for e in result.errors]}"
    )
    assert len(result.errors) == 0


def test_overlapping_notes_error():
    """Two overlapping notes on the same track should produce an error."""
    data = {
        "project_name": "overlap_test",
        "tempo_map": [{"position_beats": 0, "bpm": 120, "time_sig_num": 4, "time_sig_den": 4}],
        "regions": [],
        "tracks": [
            {
                "name": "Overlap",
                "midi_channel": 1,
                "notes": [
                    {"pitch": 60, "velocity": 100, "start_beats": 0, "duration_beats": 2},
                    {"pitch": 64, "velocity": 100, "start_beats": 1, "duration_beats": 2},
                ],
            }
        ],
    }
    result = validate(data)
    assert not result.passed
    overlap_errors = [e for e in result.errors if "Overlap" in e.message]
    assert len(overlap_errors) >= 1


def test_nine_tracks_error():
    """More than 8 tracks should produce a channel count error."""
    tracks = []
    for i in range(9):
        tracks.append({
            "name": f"Track {i + 1}",
            "midi_channel": i + 1,
            "notes": [
                {"pitch": 60, "velocity": 100, "start_beats": 0, "duration_beats": 1},
            ],
        })
    data = {
        "project_name": "too_many_tracks",
        "tempo_map": [{"position_beats": 0, "bpm": 120, "time_sig_num": 4, "time_sig_den": 4}],
        "regions": [],
        "tracks": tracks,
    }
    result = validate(data)
    assert not result.passed
    channel_errors = [e for e in result.errors if "Channel count" in e.message]
    assert len(channel_errors) == 1
