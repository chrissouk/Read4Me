# Read4Me

Because Speechify costs too much money

Read4Me converts documents to speech
using OpenAI TTS and a small, local pipeline.

**Repository layout**
- `file_to_speech.py`: dispatcher (future-proof) — converts files to speech.
- `pdf_to_text.py`: PDF extractor (uses `pdfplumber`).
- `text_to_speech.py`: chunking + OpenAI TTS caller (returns list of MP3s).
- `audio_merger.py`: merges MP3 parts into one file using `pydub`/`ffmpeg`.
- `.env`: hold `OPENAI_API_KEY=sk-...` (not checked in).
- `audio/`: generated audio output.
- `files/`: input documents (PDFs, etc.).

## Quickstart

1. Create and activate a virtualenv (recommended):
```bash
python -m venv .venv
source .venv/bin/activate
```
2. Install Python dependencies:
```bash
pip install -r requirements.txt
```
3. Install system dependency `ffmpeg` (required by `pydub`):
```bash
# macOS (Homebrew)
brew install ffmpeg
# Ubuntu/Debian
sudo apt update && sudo apt install -y ffmpeg
# conda
conda install -c conda-forge ffmpeg
```
4. Add your OpenAI API key to a `.env` file at the repo root:
```bash
echo "OPENAI_API_KEY=sk-REPLACE_WITH_YOUR_KEY" > .env
```

## Usage examples

- Convert a PDF to speech (quoted because path may contain spaces):
```bash
python file_to_speech.py "files/My Doc (v1).pdf"
```
- The pipeline will chunk long text, create per-part MP3 files, then merge
	them into `./audio/<pdf-stem>.mp3` by default.
- If you only want the parts (no merge) call the `file_to_speech` function
	from Python with `merge=False`.

## Troubleshooting
- If merging fails with `FileNotFoundError: 'ffprobe'` or warnings about
	`ffmpeg`, install `ffmpeg` as shown above and ensure it's on your `PATH`.
- If you get errors from the OpenAI client about unexpected kwargs, check for a
	local file named `openai.py` shadowing the real package and inspect the
	installed package:
```bash
python - <<'PY'
import openai, inspect
from openai import OpenAI
print('openai module:', openai.__file__)
print('OpenAI.__init__:', inspect.signature(OpenAI.__init__))
PY
```

## Notes
- Chunking reduces per-request size but creates multiple TTS calls (cost
	increases with length). The project merges parts locally using `pydub`.
- Feel free to move modules into a package (e.g. `src/read4me/`) when
	converting this into a backend service.

If you'd like, I can add a CI check, a small demo PDF, or a CLI flag for
`--no-merge` to preserve parts. 