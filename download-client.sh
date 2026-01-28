#!/usr/bin/env bash
set -u

# ---- Config (hardcoded download destination) ----
DEST_DIR="$HOME/Downloads/download-client"

# Seconds to wait between downloads (helps avoid bursty VPN/server behavior)
SLEEP_BETWEEN=2

# Wget retry behavior
RETRY_COUNT=5
RETRY_DELAY=5

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
failed_file_created=0

# ---- Staging dir in /tmp (downloads happen here first) ----
STAGING_DIR="$(mktemp -d -t download-client.XXXXXX)"
cleanup() { rm -rf "$STAGING_DIR"; }
trap cleanup EXIT

# Read line-by-line; also handles last line w/o trailing newline
while IFS= read -r url || [[ -n "$url" ]]; do
  # Trim leading/trailing whitespace
  url="${url#"${url%%[![:space:]]*}"}"
  url="${url%"${url##*[![:space:]]}"}"

  # Skip blanks and comments
  [[ -z "$url" ]] && continue
  [[ "$url" =~ ^# ]] && continue

  ((found++))

  # Download sequentially into STAGING_DIR using wget (IPv4 only)
  # -4: force IPv4
  # --content-disposition: honor server-provided filenames
  # --trust-server-names: accept server name changes on redirects (useful for CDNs)
  # -c: continue/resume partial downloads
  # --tries/--waitretry: retry transient errors
  # -q: quiet (still returns proper exit codes)
  (
    cd "$STAGING_DIR" && \
    wget -4 \
      --content-disposition \
      --trust-server-names \
      -c \
      --tries="$RETRY_COUNT" \
      --waitretry="$RETRY_DELAY" \
      -q \
      "$url"
  )
  rc=$?

  if [[ "$rc" -eq 0 ]]; then
    # Determine the newest file in staging (wget doesn't reliably print final name in quiet mode)
    filename="$(ls -1t "$STAGING_DIR" 2>/dev/null | head -n 1)"
    src_path="$STAGING_DIR/$filename"

    if [[ -n "$filename" && -f "$src_path" ]]; then
      mv -f "$src_path" "$DEST_DIR/"
      ((success++))
    else
      ((failed++))
      if [[ "$failed_file_created" -eq 0 ]]; then
        : > "$FAILED_FILE"
        failed_file_created=1
      fi
      echo "$url" >> "$FAILED_FILE"
    fi
  else
    ((failed++))
    if [[ "$failed_file_created" -eq 0 ]]; then
      : > "$FAILED_FILE"
      failed_file_created=1
    fi
    echo "$url" >> "$FAILED_FILE"
  fi

  sleep "$SLEEP_BETWEEN"
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
