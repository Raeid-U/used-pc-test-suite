#!/usr/bin/env bash
set -u
set -o pipefail

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  exec sudo -E bash "$0" "$@"
fi

ts="$(date +%s)"
out="test-stream-${ts}.txt"
exec > >(tee -a "$out") 2>&1

echo "==== STREAM TEST ===="
echo "Timestamp: $ts"
echo "Date:      $(date -Is)"
echo "Host:      $(hostname)"
echo "Kernel:    $(uname -a)"
echo

run() {
  echo
  echo "Running: $*"
  "$@"
  ec=$?
  echo "Exit code: $ec"
  return 0
}

run apt-get update -y
run apt-get install -y build-essential wget


tmpdir="$(mktemp -d /tmp/stream-bench.XXXXXX)"
echo
echo "Using temp dir: $tmpdir"
cd "$tmpdir"

# Download STREAM source
STREAM_URL="https://www.cs.virginia.edu/stream/FTP/Code/stream.c"
echo "Fetching: $STREAM_URL"
if ! wget -q "$STREAM_URL" -O stream.c; then
  echo "ERROR: Could not download stream.c (no internet?)."
  echo "Fix: put stream.c in this directory and rerun."
  exit 1
fi

# Build with OpenMP; array size chosen to be > cache but not huge
echo
echo "Compiling STREAM..."
echo "gcc -O3 -march=native -fopenmp -DSTREAM_ARRAY_SIZE=80000000 -DNTIMES=20 stream.c -o stream"
gcc -O3 -march=native -fopenmp -DSTREAM_ARRAY_SIZE=80000000 -DNTIMES=20 stream.c -o stream

# Pinning helps consistency
export OMP_NUM_THREADS=12
export OMP_PROC_BIND=true
export OMP_PLACES=cores

echo
echo "Running STREAM with OMP_NUM_THREADS=$OMP_NUM_THREADS"
./stream

echo
echo "Cleaning up temp dir: $tmpdir"
rm -rf "$tmpdir" || true

echo
echo "Saved: $out"

