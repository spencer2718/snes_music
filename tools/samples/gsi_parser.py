"""Parse SNESGSS .gsi instrument files."""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class GsiInstrument:
    name: str = ""
    env_ar: int = 0
    env_dr: int = 0
    env_sl: int = 0
    env_sr: int = 0
    length: int = 0
    loop_start: int = 0
    loop_end: int = 0
    loop_enable: bool = False
    source_length: int = 0
    source_rate: int = 32000
    source_volume: int = 128
    wav_loop_start: int = 0
    wav_loop_end: int = 0
    eq_low: int = 0
    eq_mid: int = 0
    eq_high: int = 0
    resample_type: int = 0
    downsample_factor: int = 0
    ramp_enable: bool = False
    loop_unroll: bool = False
    treble_boost: int = 0
    samples: list[int] = field(default_factory=list)


# Map .gsi key suffixes to GsiInstrument field names
_FIELD_MAP = {
    "Name": ("name", str),
    "EnvAR": ("env_ar", int),
    "EnvDR": ("env_dr", int),
    "EnvSL": ("env_sl", int),
    "EnvSR": ("env_sr", int),
    "Length": ("length", int),
    "LoopStart": ("loop_start", int),
    "LoopEnd": ("loop_end", int),
    "LoopEnable": ("loop_enable", bool),
    "SourceLength": ("source_length", int),
    "SourceRate": ("source_rate", int),
    "SourceVolume": ("source_volume", int),
    "WavLoopStart": ("wav_loop_start", int),
    "WavLoopEnd": ("wav_loop_end", int),
    "EQLow": ("eq_low", int),
    "EQMid": ("eq_mid", int),
    "EQHigh": ("eq_high", int),
    "ResampleType": ("resample_type", int),
    "DownsampleFactor": ("downsample_factor", int),
    "RampEnable": ("ramp_enable", bool),
    "LoopUnroll": ("loop_unroll", bool),
    "TrebleBoost": ("treble_boost", int),
}


def decode_source_data(hex_string: str) -> list[int]:
    """Decode hex-encoded 16-bit PCM samples.

    Each 4-char group is an unsigned 16-bit int. Values > 0x7FFF
    are negative (two's complement).
    """
    hex_string = hex_string.strip()
    if not hex_string:
        return []
    samples = []
    for i in range(0, len(hex_string), 4):
        chunk = hex_string[i : i + 4]
        if len(chunk) < 4:
            break
        unsigned_val = int(chunk, 16)
        # Convert to signed two's complement
        if unsigned_val > 0x7FFF:
            signed_val = unsigned_val - 0x10000
        else:
            signed_val = unsigned_val
        samples.append(signed_val)
    return samples


def parse_gsi(path: Path) -> GsiInstrument:
    """Parse a .gsi file and return a GsiInstrument."""
    text = path.read_text(encoding="latin-1")
    lines = text.replace("\r\n", "\n").replace("\r", "\n").split("\n")

    inst = GsiInstrument()
    prefix = "Instrument0"

    for line in lines:
        line = line.strip()
        if not line or line.startswith("["):
            continue
        if "=" not in line:
            continue

        key, value = line.split("=", 1)

        if key == prefix + "SourceData":
            inst.samples = decode_source_data(value)
            continue

        for suffix, (field_name, field_type) in _FIELD_MAP.items():
            if key == prefix + suffix:
                if field_type is bool:
                    setattr(inst, field_name, value.strip() == "1")
                elif field_type is int:
                    setattr(inst, field_name, int(value.strip()) if value.strip() else 0)
                else:
                    setattr(inst, field_name, value.strip())
                break

    return inst
