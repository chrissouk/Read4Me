"""Generic file-to-speech dispatcher.

This module is structured to accommodate multiple input file types in the
future. For now it only supports PDF files by delegating to
`pdf_to_text.pdf_to_text` and `text_to_speech.text_to_speech`.

Public API:
  - `file_to_speech(file_path: str, ...) -> Path`

The function produces an MP3 saved in `./audio/` named after the input file's
stem (e.g. `document.pdf` -> `document.mp3`).
"""
from __future__ import annotations

from pathlib import Path
from typing import Optional

from pdf_to_text import pdf_to_text
from text_to_speech import text_to_speech
from audio_merger import merge_audio


def file_to_speech(
    file_path: str,
    voice: str = "onyx",
    model: str = "gpt-4o-mini-tts",
    instructions: Optional[str] = None,
    output_dir: str = "./audio/",
    merge: bool = True,
) -> list:
    """Convert a file to speech using a handler chosen by file type.

    Args:
        file_path: Path to the source file.
        voice: Voice name for TTS.
        model: TTS model identifier.
        instructions: Optional instructions for style/tone.
        output_dir: Directory to save the audio file.

    Returns:
        Path to the saved audio file.

    Raises:
        FileNotFoundError: If the input file does not exist.
        NotImplementedError: If the file type is not yet supported.
        RuntimeError: For other failures propagated from helpers.
    """
    src = Path(file_path)
    if not src.exists():
        raise FileNotFoundError(f"Input file not found: {file_path}")

    suffix = src.suffix.lower()

    # Dispatch based on suffix. In future this can be extended with a
    # registration mechanism or mapping table.
    if suffix == ".pdf":
        # Extract text from PDF and synthesize speech (chunked)
        text = pdf_to_text(str(src))
        parts = text_to_speech(
            text,
            out_stem=src.stem,
            voice=voice,
            model=model,
            instructions=instructions,
            output_dir=output_dir,
        )

        # If requested, merge parts into single file
        if merge and len(parts) > 1:
            merged_path = Path(output_dir) / f"{src.stem}.mp3"
            merged = merge_audio(parts, out_path=merged_path)
            # Optionally remove parts after merging
            for p in parts:
                try:
                    p.unlink()
                except Exception:
                    pass
            return [merged]

        return parts

    # Placeholder for future file types
    raise NotImplementedError(f"File type not supported yet: {suffix}")


if __name__ == "__main__":
    import sys

    if len(sys.argv) < 2:
        print("Usage: python file_to_speech.py path/to/file [optional-voice] [optional-output-dir]")
        raise SystemExit(2)

    input_file = sys.argv[1]
    voice_arg = sys.argv[2] if len(sys.argv) >= 3 else "onyx"
    out_dir_arg = sys.argv[3] if len(sys.argv) >= 4 else "./audio/"

    try:
        saved = file_to_speech(input_file, voice=voice_arg, output_dir=out_dir_arg)
        print(f"Saved audio to: {saved}")
    except Exception as err:
        print(f"Error: {err}")
        raise SystemExit(1)
