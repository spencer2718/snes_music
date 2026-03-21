"""Write 16-bit mono WAV files from PCM sample data."""

from __future__ import annotations

import struct
import wave
from pathlib import Path

RETUNE_RATIO = 2.0 ** (79.0 / 1200.0)  # ≈ 1.0466, B+21 → C


def retune_b21_to_c(samples: list[int], source_rate: int) -> tuple[list[int], int]:
    """Resample to shift pitch up 79 cents (B+21 → C).

    SNESGSS samples are tuned to B +21 cents. Shifting up 79 cents
    maps them to C, matching standard MIDI note expectations.

    To raise pitch by N cents without changing sample rate,
    we DROP samples (shorten the waveform). The ratio of
    input_length / output_length = 2^(79/1200).
    """
    ratio = RETUNE_RATIO
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
        val = max(-32768, min(32767, int(round(val))))
        resampled.append(val)

    return resampled, source_rate


def _write_smpl_chunk(f, sample_rate: int, loop_start: int, loop_end: int) -> int:
    """Write a WAV smpl chunk for loop points. Returns bytes written."""
    sample_period = int(1_000_000_000 / sample_rate)  # nanoseconds per sample
    num_loops = 1
    chunk_size = 36 + 24 * num_loops

    smpl_data = struct.pack(
        "<4sI"       # chunk ID + size
        "IIIIIIIII"  # manufacturer..sampler_data_size
        "IIIIII",    # loop 0
        b"smpl", chunk_size,
        0,              # manufacturer
        0,              # product
        sample_period,  # sample period
        60,             # MIDI unity note (middle C)
        0,              # MIDI pitch fraction
        0,              # SMPTE format
        0,              # SMPTE offset
        num_loops,      # num sample loops
        0,              # sampler data size
        # Loop 0:
        0,              # cue point ID
        0,              # type (0 = forward loop)
        loop_start,     # start
        loop_end,       # end
        0,              # fraction
        0,              # play count (0 = infinite)
    )
    f.write(smpl_data)
    return len(smpl_data)


def write_wav(
    samples: list[int],
    sample_rate: int,
    output_path: Path,
    retune: bool = True,
    loop_enable: bool = False,
    loop_start: int = 0,
    loop_end: int = 0,
) -> Path:
    """Write PCM samples as a 16-bit mono WAV file.

    If retune is True, applies B+21→C pitch correction and adjusts
    loop points by the same ratio.
    If loop_enable is True, appends a WAV smpl chunk with loop points.
    """
    if retune:
        if loop_enable and (loop_start > 0 or loop_end > 0):
            loop_start = int(loop_start / RETUNE_RATIO)
            loop_end = int(loop_end / RETUNE_RATIO)
        samples, sample_rate = retune_b21_to_c(samples, sample_rate)

    # Clamp loop_end to sample count
    if loop_enable:
        loop_end = min(loop_end, len(samples) - 1)
        if loop_end <= loop_start:
            loop_enable = False

    # Write the base WAV using the wave module
    with wave.open(str(output_path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sample_rate)
        data = struct.pack(f"<{len(samples)}h", *samples)
        wf.writeframes(data)

    # Append smpl chunk if looping is enabled
    if loop_enable:
        with open(output_path, "r+b") as f:
            # Read current RIFF size
            f.seek(4)
            riff_size = struct.unpack("<I", f.read(4))[0]

            # Seek to end, write smpl chunk
            f.seek(0, 2)
            smpl_bytes = _write_smpl_chunk(f, sample_rate, loop_start, loop_end)

            # Update RIFF size
            f.seek(4)
            f.write(struct.pack("<I", riff_size + smpl_bytes))

    return output_path
