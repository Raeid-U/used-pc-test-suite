#!/usr/bin/env bash
set -u

# ---- Config (hardcoded download destination) ----
DEST_DIR="$HOME/Downloads/download-client"

# ---- Input ----
INPUT_FILE="${1:-}"
if [[ -z "$INPUT_FILE" || ! -f "$INPUT_FILE" ]]; then
  echo "Usage: $0 <links.txt>"
  exit 1
fi

# Ensure destination exists
mkdir -p "$DEST_DIR"

BASENAME="$(basename "$INPUT_FILE")"
STEM="${BASENAME%.*}"
TIMESTAMP="$(date +"%Y%m%d-%H%M%S")"

# failed-... file in the *current working directory* (where script was called from)
FAILED_FILE="failed-${STEM}-${TIMESTAMP}.txt"

found=0
success=0
failed=0

# We'll only create FAILED_FILE if we actually have failures
failed_file_created=0

# Read line-by-line; also handles last line w/o trailing newline
while IFS= read -r url || [[ -n "$url" ]]; do
  # Trim leading/trailing whitespace
  url="${url#"${url%%[![:space:]]*}"}"
  url="${url%"${url##*[![:space:]]}"}"

  # Skip blanks and comments
  [[ -z "$url" ]] && continue
  [[ "$url" =~ ^# ]] && continue

  ((found++))

  # Download sequentially into DEST_DIR
  # -f: fail on HTTP errors (4xx/5xx)
  # -L: follow redirects
  # -O: save as remote filename
  # -sS: silent but still show errors (optional; remove if you want full curl output)
  if (cd "$DEST_DIR" && curl -fL -O "$url"); then
    ((success++))
  else
    ((failed++))
    if [[ "$failed_file_created" -eq 0 ]]; then
      : > "$FAILED_FILE"
      failed_file_created=1
    fi
    echo "$url" >> "$FAILED_FILE"
  fi
done < "$INPUT_FILE"

echo "Target File: $BASENAME"
echo "Found links: $found"
echo "Download Status:"
echo "    - Success: $success"
echo "    - Failed: $failed"

if [[ "$failed" -gt 0 ]]; then
  echo
  echo "Failed links have been put in $FAILED_FILE"
fi
