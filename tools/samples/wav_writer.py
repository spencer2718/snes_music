"""Write 16-bit mono WAV files from PCM sample data."""

from __future__ import annotations

import math
import struct
import wave
from pathlib import Path


def retune_b21_to_c(samples: list[int], source_rate: int) -> tuple[list[int], int]:
    """Resample to shift pitch up 79 cents (B+21 → C).

    SNESGSS samples are tuned to B +21 cents. Shifting up 79 cents
    maps them to C, matching standard MIDI note expectations.

    The ratio is 2^(79/1200) ≈ 1.0466. We resample by stretching
    the sample (lowering the effective pitch), which means producing
    MORE output samples. The output sample rate stays the same, but
    the waveform is compressed in time → higher pitch.

    Actually: to raise pitch by N cents without changing sample rate,
    we DROP samples (shorten the waveform). The ratio of
    input_length / output_length = 2^(79/1200).
    """
    ratio = 2.0 ** (79.0 / 1200.0)  # ≈ 1.0466
    out_length = int(len(samples) / ratio)
    if out_length < 1:
        return samples, source_rate

    resampled = []
    for i in range(out_length):
        src_pos = i * ratio
        idx = int(src_pos)
        frac = src_pos - idx
        if idx + 1 < len(samples):
            val = samples[idx] * (1.0 - frac) + samples[idx + 1] * frac
        else:
            val = samples[idx] if idx < len(samples) else 0
        # Clamp to int16 range
        val = max(-32768, min(32767, int(round(val))))
        resampled.append(val)

    return resampled, source_rate


def write_wav(
    samples: list[int],
    sample_rate: int,
    output_path: Path,
    retune: bool = True,
) -> Path:
    """Write PCM samples as a 16-bit mono WAV file.

    If retune is True, applies B+21→C pitch correction.
    """
    if retune:
        samples, sample_rate = retune_b21_to_c(samples, sample_rate)

    with wave.open(str(output_path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)  # 16-bit
        wf.setframerate(sample_rate)
        # Pack as little-endian signed 16-bit
        data = struct.pack(f"<{len(samples)}h", *samples)
        wf.writeframes(data)

    return output_path
