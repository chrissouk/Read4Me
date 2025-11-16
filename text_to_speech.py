"""Text-to-speech helper using OpenAI's TTS API.

Provides `text_to_speech(text: str, filename: Optional[str]=None, ...) -> Path`
which loads an OpenAI API key from a `.env` file (or the environment), sends
the text to OpenAI's TTS model, and saves the resulting audio under
`./audio/` (creates the directory if needed).
"""
from __future__ import annotations

from pathlib import Path
from typing import Optional
import os
from datetime import datetime

from dotenv import load_dotenv
from openai import OpenAI


def text_to_speech(
    text: str,
    filename: Optional[str] = None,
    voice: str = "onyx",
    model: str = "gpt-4o-mini-tts",
    instructions: Optional[str] = None,
    output_dir: str = "./audio/",
) -> Path:
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
        Path to the saved audio file.

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

    if filename:
        out_path = out_dir / filename
    else:
        ts = datetime.utcnow().strftime("%Y%m%d%H%M%S")
        out_path = out_dir / f"speech_{ts}.mp3"

    try:
        with client.audio.speech.with_streaming_response.create(
            model=model,
            voice=voice,
            input=text,
            instructions=instructions or "be fluent & clear, like a podcast narrator",
        ) as response:
            response.stream_to_file(out_path)
    except Exception as e:
        raise RuntimeError(f"Text-to-speech request failed: {e}") from e

    return out_path


if __name__ == "__main__":
    import sys

    if len(sys.argv) < 2:
        print("Usage: python text_to_speech.py 'Some text to speak' [optional-output-filename]")
        raise SystemExit(2)

    input_text = sys.argv[1]
    out_name = sys.argv[2] if len(sys.argv) >= 3 else None

    try:
        path = text_to_speech(input_text, filename=out_name)
        print(f"Saved audio to: {path}")
    except Exception as err:
        print(f"Error: {err}")
        raise SystemExit(1)
