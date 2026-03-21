"""Tests for the .gsi parser and WAV conversion."""

from pathlib import Path

from tools.samples.gsi_parser import GsiInstrument, decode_source_data, parse_gsi

FIXTURE_GSI = Path(__file__).parent.parent / "docs" / "fixtures" / "waveform_sine.gsi"


def test_decode_source_data_known_values():
    """Hand-computed hex decode for known values."""
    # 0000 = 0, 7FFF = 32767, 8000 = -32768, FFFF = -1
    samples = decode_source_data("000080007FFFFFFFE001")
    assert samples[0] == 0
    assert samples[1] == -32768  # 0x8000 → signed = -32768
    assert samples[2] == 32767   # 0x7FFF → signed = 32767
    assert samples[3] == -1      # 0xFFFF → signed = -1
    assert samples[4] == -8191   # 0xE001 → signed = 57345 - 65536 = -8191


def test_decode_source_data_empty():
    """Empty string returns empty list."""
    assert decode_source_data("") == []
    assert decode_source_data("  ") == []


def test_parse_gsi_waveform_sine():
    """Parse the waveform_sine.gsi fixture."""
    inst = parse_gsi(FIXTURE_GSI)

    assert inst.name == "waveform_sine"
    assert inst.source_rate == 32000
    assert inst.source_rate in (8000, 16000, 32000)
    assert inst.source_length == 64
    assert inst.loop_enable is True
    assert inst.env_ar == 15

    # SourceLength should match decoded sample count
    assert len(inst.samples) == inst.source_length

    # All samples must be in signed 16-bit range
    for s in inst.samples:
        assert -32768 <= s <= 32767, f"Sample {s} out of int16 range"


def test_parse_gsi_first_samples():
    """Verify first few decoded samples from waveform_sine."""
    inst = parse_gsi(FIXTURE_GSI)
    # From the hex: 0000 08e1 11ad 1a4d
    assert inst.samples[0] == 0x0000  # 0
    assert inst.samples[1] == 0x08E1  # 2273
    assert inst.samples[2] == 0x11AD  # 4525
    assert inst.samples[3] == 0x1A4D  # 6733


def test_parse_gsi_loop_fields():
    """Verify loop fields are populated from waveform_sine.gsi."""
    inst = parse_gsi(FIXTURE_GSI)
    assert inst.loop_enable is True
    assert inst.loop_start == 0
    assert inst.loop_end == 63
    assert isinstance(inst.loop_start, int)
    assert isinstance(inst.loop_end, int)
