#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $(basename "$0") <input.pdf> [output_dir]"
  echo ""
  echo "Convert each page of a PDF into a PNG image."
  echo ""
  echo "Arguments:"
  echo "  input.pdf    Path to the input PDF file"
  echo "  output_dir   Directory for output images (default: same directory as input)"
  echo ""
  echo "Options:"
  echo "  -d, --dpi DPI   Resolution in DPI (default: 300)"
  echo "  -h, --help      Show this help message"
  exit "${1:-0}"
}

DPI=300

# Parse options
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help) usage 0 ;;
    -d | --dpi)
      DPI="$2"
      shift 2
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage 1
      ;;
    *)
      break
      ;;
  esac
done

if [[ $# -lt 1 ]]; then
  echo "Error: No input PDF specified." >&2
  usage 1
fi

INPUT_PDF="$1"
if [[ ! -f "$INPUT_PDF" ]]; then
  echo "Error: File not found: $INPUT_PDF" >&2
  exit 1
fi

# Determine output directory
if [[ $# -ge 2 ]]; then
  OUTPUT_DIR="$2"
else
  OUTPUT_DIR="$(dirname "$INPUT_PDF")"
fi
mkdir -p "$OUTPUT_DIR"

# Base name for output files (strip .pdf extension)
BASENAME="$(basename "$INPUT_PDF" .pdf)"

# Require one of: pdftoppm (poppler) or magick/convert (ImageMagick)
if command -v pdftoppm >/dev/null 2>&1; then
  echo "Using pdftoppm (poppler-utils) at ${DPI} DPI..."
  pdftoppm -png -r "$DPI" "$INPUT_PDF" "${OUTPUT_DIR}/${BASENAME}"
elif command -v magick >/dev/null 2>&1; then
  echo "Using ImageMagick (magick) at ${DPI} DPI..."
  magick -density "$DPI" "$INPUT_PDF" "${OUTPUT_DIR}/${BASENAME}-%03d.png"
elif command -v convert >/dev/null 2>&1; then
  echo "Using ImageMagick (convert) at ${DPI} DPI..."
  convert -density "$DPI" "$INPUT_PDF" "${OUTPUT_DIR}/${BASENAME}-%03d.png"
else
  echo "Error: No PDF-to-image tool found." >&2
  echo "Install one of:" >&2
  echo "  - poppler-utils  (provides pdftoppm)  — recommended" >&2
  echo "  - imagemagick     (provides magick/convert)" >&2
  exit 1
fi

echo "Done. Images saved to: $OUTPUT_DIR"
