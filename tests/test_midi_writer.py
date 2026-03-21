"""Tests for the exported constrained MIDI file."""

import struct
from pathlib import Path

EXPORT_MID = Path(__file__).parent.parent / "exports" / "snes_export.mid"


def _read_u16be(data: bytes, offset: int) -> int:
    return struct.unpack_from(">H", data, offset)[0]


def _read_u32be(data: bytes, offset: int) -> int:
    return struct.unpack_from(">I", data, offset)[0]


def test_midi_file_exists():
    assert EXPORT_MID.exists(), f"{EXPORT_MID} not found"


def test_midi_header_magic():
    data = EXPORT_MID.read_bytes()
    assert data[:4] == b"MThd", f"Expected MThd, got {data[:4]}"


def test_midi_format_1():
    data = EXPORT_MID.read_bytes()
    fmt = _read_u16be(data, 8)
    assert fmt == 1, f"Expected format 1, got {fmt}"


def test_midi_ppq_480():
    data = EXPORT_MID.read_bytes()
    ppq = _read_u16be(data, 12)
    assert ppq == 480, f"Expected PPQ 480, got {ppq}"


def test_midi_track_count_matches_chunks():
    """Header track count must match actual MTrk chunks in file."""
    data = EXPORT_MID.read_bytes()
    header_track_count = _read_u16be(data, 10)

    # Count MTrk chunks
    chunk_count = 0
    pos = 14  # after MThd header (8 bytes) + header data (6 bytes)
    while pos < len(data) - 8:
        chunk_id = data[pos : pos + 4]
        chunk_size = _read_u32be(data, pos + 4)
        if chunk_id == b"MTrk":
            chunk_count += 1
        pos += 8 + chunk_size

    assert header_track_count == chunk_count, (
        f"Header says {header_track_count} tracks, found {chunk_count} MTrk chunks"
    )


def test_midi_all_tracks_end_correctly():
    """Every MTrk chunk must end with FF 2F 00 (end-of-track)."""
    data = EXPORT_MID.read_bytes()
    pos = 14
    track_idx = 0
    while pos < len(data) - 8:
        chunk_id = data[pos : pos + 4]
        chunk_size = _read_u32be(data, pos + 4)
        if chunk_id == b"MTrk":
            track_data = data[pos + 8 : pos + 8 + chunk_size]
            assert track_data[-3:] == b"\xff\x2f\x00", (
                f"Track {track_idx} does not end with FF 2F 00"
            )
            track_idx += 1
        pos += 8 + chunk_size


def test_midi_file_size_consistent():
    """File size must equal header + sum of all chunk sizes."""
    data = EXPORT_MID.read_bytes()
    # MThd: 8 bytes header + 6 bytes data = 14
    expected_size = 14
    pos = 14
    while pos < len(data) - 4:
        chunk_size = _read_u32be(data, pos + 4)
        expected_size += 8 + chunk_size
        pos += 8 + chunk_size

    assert len(data) == expected_size, (
        f"File size {len(data)} != expected {expected_size}"
    )
