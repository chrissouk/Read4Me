"""PDF text extraction helper.

Provides `pdf_to_text(filepath: str) -> str` which returns all
text found in the PDF as a single string. Uses PyPDF2.
"""
from typing import List
import logging

try:  # optional rich progress for nicer progress bars
    from rich.progress import Progress, BarColumn, TextColumn, TimeElapsedColumn
    _RICH = True
except Exception:
    _RICH = False

logger = logging.getLogger(__name__)
if not logging.getLogger().hasHandlers():
    logging.basicConfig(level=logging.INFO)


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
        logger.info("Opening PDF: %s", p)
        with pdfplumber.open(str(p)) as pdf:
            pages = pdf.pages
            total = len(pages)
            logger.info("PDF has %d pages", total)

            if _RICH:
                progress = Progress(
                    TextColumn("[{task.fields[filename]}] {task.description}"),
                    BarColumn(bar_width=None),
                    "{task.completed}/{task.total}",
                    TimeElapsedColumn(),
                )
                task = progress.add_task("Extracting pages", total=total, filename=p.name)
                with progress:
                    for page in pages:
                        page_text = page.extract_text()
                        if page_text:
                            text_parts.append(page_text)
                        progress.advance(task)
            else:
                for i, page in enumerate(pages, start=1):
                    page_text = page.extract_text()
                    if page_text:
                        text_parts.append(page_text)
                    logger.debug("Extracted page %d/%d", i, total)

        logger.info("Extraction complete, %d text blocks collected", len(text_parts))
        return "\n".join(text_parts)
    except Exception as e:
        logger.exception("Failed to extract text from PDF '%s'", p)
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
