"""PDF text extraction helper.

Provides `pdf_to_text(filepath: str) -> str` which returns all
text found in the PDF as a single string. Uses PyPDF2.
"""
from typing import List


def pdf_to_text(filepath: str) -> str:
    """Extracts and returns all textual content from the PDF at `filepath`.

    Args:
        filepath: Path to the PDF file.

    Returns:
        A single string with the concatenated text from all pages.

    Raises:
        RuntimeError: If the file cannot be read or extraction fails.
    """
    try:
        import pdfplumber
    except Exception as e:  # pragma: no cover - import/runtime error
        raise RuntimeError("pdfplumber is required. Install it with `pip install pdfplumber`.") from e
    # Normalize and resolve path (support ~, relative and absolute paths)
    from pathlib import Path

    p = Path(filepath).expanduser()
    if not p.is_absolute():
        p = (Path.cwd() / p).resolve()

    if not p.exists():
        raise FileNotFoundError(f"PDF not found: {p}")

    text_parts: List[str] = []
    try:
        with pdfplumber.open(str(p)) as pdf:
            for page in pdf.pages:
                page_text = page.extract_text()
                if page_text:
                    text_parts.append(page_text)
        return "\n".join(text_parts)
    except Exception as e:
        raise RuntimeError(f"Failed to extract text from PDF '{p}': {e}") from e


if __name__ == "__main__":
    import sys

    if len(sys.argv) != 2:
        print("Usage: python pdf_to_text.py <path-to-pdf>")
        sys.exit(2)

    path = sys.argv[1]
    try:
        text = pdf_to_text(path)
        print(text)
    except Exception as err:
        print(f"Error: {err}")
        sys.exit(1)
