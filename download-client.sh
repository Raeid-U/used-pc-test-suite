#!/usr/bin/env bash
set -u

# ---- Config (hardcoded download destination + throttling) ----
DEST_DIR="$HOME/Downloads/download-client"

# Start conservative. You can bump this up later (e.g. 2M, 3M).
RATE_LIMIT="500K"

# Seconds to wait between downloads (helps avoid bursty VPN/server behavior)
SLEEP_BETWEEN=2

# Curl retry behavior
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

  # Download sequentially into STAGING_DIR
  # -f: fail on HTTP errors (4xx/5xx)
  # -L: follow redirects
  # -O: save as remote filename
  # --limit-rate: throttle transfer speed (e.g. 500K, 2M, 3M)
  # -C -: resume partial downloads (within this run / same staging dir)
  # --retry...: retry transient errors (useful over VPNs)
  curl_out="$(
    cd "$STAGING_DIR" && \
    curl -fL -O "$url" \
      --limit-rate "$RATE_LIMIT" \
      -C - \
      --retry "$RETRY_COUNT" \
      --retry-delay "$RETRY_DELAY" \
      --retry-all-errors \
      -sS \
      -w '\n%{filename_effective}\n'
  )"
  rc=$?

  if [[ "$rc" -eq 0 ]]; then
    filename="$(printf '%s' "$curl_out" | tail -n 1)"
    src_path="$STAGING_DIR/$filename"

    if [[ -n "$filename" && -f "$src_path" ]]; then
      # Move into final destination (same name)
      mv -f "$src_path" "$DEST_DIR/"
      ((success++))
    else
      # Unexpected edge case: curl reported success but file isn't there
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
