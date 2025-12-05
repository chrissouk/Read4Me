"""Merge multiple audio files into a single MP3 using pydub.

Requires `pydub` and `ffmpeg` available on the PATH.
"""
from pathlib import Path
from typing import Iterable, List, Optional
import logging
import re

try:
    from rich.progress import Progress, BarColumn, TextColumn, TimeElapsedColumn
    _RICH = True
except Exception:
    _RICH = False

from pydub import AudioSegment

logger = logging.getLogger(__name__)
if not logging.getLogger().hasHandlers():
    logging.basicConfig(level=logging.INFO)


def merge_audio(file_paths: Iterable[Path], out_path: Optional[Path] = None, gap_ms: int = 300) -> Path:
    """Merge audio files in `file_paths` into a single MP3 at `out_path`.

    Args:
        file_paths: Iterable of Paths to audio files (mp3/wav/etc).
        out_path: Optional output path. If omitted, creates `merged.mp3` next to
            the first input file.
        gap_ms: Milliseconds of silence between parts.

    Returns:
        Path to the merged MP3 file.
    """
    files = [Path(p) for p in file_paths]
    # sort by numerical part suffix when present (e.g. foo_part001.mp3)
    def sort_key(item_index_path):
        idx, p = item_index_path
        m = re.search(r"_part(\d{1,6})$", p.stem)
        if m:
            return (0, int(m.group(1)), idx)
        # place files without part suffix after numbered parts, preserve original order
        return (1, 0, idx)

    files = [p for _, p in sorted(enumerate(files), key=sort_key)]
    if not files:
        raise ValueError("No audio files provided to merge")

    if out_path is None:
        out_path = files[0].with_name(f"{files[0].stem}_merged.mp3")
    else:
        out_path = Path(out_path)

    combined = AudioSegment.silent(duration=0)

    if _RICH:
        progress = Progress(
            TextColumn("Merging: {task.description}"),
            BarColumn(bar_width=None),
            "{task.completed}/{task.total}",
            TimeElapsedColumn(),
        )
        task = progress.add_task(description=out_path.name, total=len(files))
        with progress:
            for f in files:
                logger.info("Reading file %s", f)
                seg = AudioSegment.from_file(f)
                combined += seg
                combined += AudioSegment.silent(duration=gap_ms)
                progress.advance(task)
    else:
        for f in files:
            logger.info("Reading file %s", f)
            seg = AudioSegment.from_file(f)
            combined += seg
            combined += AudioSegment.silent(duration=gap_ms)

    # export to mp3
    combined.export(out_path, format="mp3")
    return out_path


if __name__ == "__main__":
    import sys

    if len(sys.argv) < 3:
        print("Usage: python audio_merger.py out.mp3 part1.mp3 part2.mp3 ...")
        raise SystemExit(2)

    out = Path(sys.argv[1])
    parts = [Path(p) for p in sys.argv[2:]]
    merged = merge_audio(parts, out_path=out)
    print(f"Merged audio written to: {merged}")
