"""Text-to-speech helper using OpenAI's TTS API.

Provides `text_to_speech(text: str, filename: Optional[str]=None, ...) -> Path`
which loads an OpenAI API key from a `.env` file (or the environment), sends
the text to OpenAI's TTS model, and saves the resulting audio under
`./audio/` (creates the directory if needed).
"""
from __future__ import annotations

from pathlib import Path
from typing import Optional, List
import os
from datetime import datetime

from dotenv import load_dotenv
from openai import OpenAI


def text_to_speech(
    text: str,
    filename: Optional[str] = None,
    out_stem: Optional[str] = None,
    max_chars: int = 3500,
    voice: str = "onyx",
    model: str = "gpt-4o-mini-tts",
    instructions: Optional[str] = None,
    output_dir: str = "./audio/",
) -> List[Path]:
    """Convert `text` to speech using OpenAI and save to `output_dir`.

    Args:
        text: The input text to synthesize.
        filename: Optional filename (e.g. "hello.mp3"). If omitted a timestamped
            name will be generated.
        voice: Voice name to use with the TTS model.
        model: The TTS model identifier.
        instructions: Optional instructions for style/tone.
        output_dir: Directory to save audio files (created if missing).

    Returns:
        A list of `Path` objects to the saved audio file(s). If the text
        is small it will be a single-element list; large text will be split
        into multiple chunks and multiple files will be returned.

    Raises:
        RuntimeError: If the OpenAI API key is not available or the request fails.
    """
    # Load .env into the environment so OpenAI client can read the key
    load_dotenv()

    api_key = os.getenv("OPENAI_API_KEY") or os.getenv("OPENAI_API_KEY")
    if not api_key:
        raise RuntimeError(
            "OPENAI_API_KEY not found. Add it to a .env file or export it in the environment."
        )

    client = OpenAI()

    out_dir = Path(output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    # Simple sentence-aware chunking: split on sentence boundaries then accumulate
    import re

    sentences = [s.strip() for s in re.split(r'(?<=[\.\!?])\s+', text) if s.strip()]

    chunks: List[str] = []
    cur = ""
    for sent in sentences:
        if cur and len(cur) + 1 + len(sent) > max_chars:
            chunks.append(cur.strip())
            cur = sent
        else:
            cur = (cur + " " + sent).strip() if cur else sent
    if cur:
        chunks.append(cur.strip())

    # If no sentences (very short text) fallback
    if not chunks:
        chunks = [text]

    saved_paths: List[Path] = []

    # Determine base stem for part filenames
    if out_stem:
        base_stem = out_stem
    elif filename:
        base_stem = Path(filename).stem
    else:
        base_stem = datetime.utcnow().strftime("speech_%Y%m%d%H%M%S")

    for i, chunk in enumerate(chunks, start=1):
        if len(chunks) == 1:
            # single-file naming
            if filename:
                out_path = out_dir / filename
            else:
                out_path = out_dir / f"{base_stem}.mp3"
        else:
            out_path = out_dir / f"{base_stem}_part{i:03d}.mp3"

        try:
            with client.audio.speech.with_streaming_response.create(
                model=model,
                voice=voice,
                input=chunk,
                instructions=instructions or "be fluent & clear, like a podcast narrator",
            ) as response:
                response.stream_to_file(out_path)
        except Exception as e:
            raise RuntimeError(f"Text-to-speech request failed for chunk {i}: {e}") from e

        saved_paths.append(out_path)

    return saved_paths


if __name__ == "__main__":
    import sys

    if len(sys.argv) < 2:
        print("Usage: python text_to_speech.py 'Some text to speak' [optional-output-filename]")
        raise SystemExit(2)

    input_text = sys.argv[1]
    out_name = sys.argv[2] if len(sys.argv) >= 3 else None

    try:
        paths = text_to_speech(input_text, filename=out_name)
        for p in paths:
            print(f"Saved audio to: {p}")
    except Exception as err:
        print(f"Error: {err}")
        raise SystemExit(1)
