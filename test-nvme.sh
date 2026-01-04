#!/usr/bin/env bash
set -u
set -o pipefail

usage() {
  cat <<EOF
Usage:
  sudo ./test-nvme.sh /dev/nvme0
  sudo ./test-nvme.sh /dev/nvme0n1

Notes:
  - You may pass the controller (/dev/nvme0) or a namespace (/dev/nvme0n1).
  - The script will derive the controller path for logs that require it.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  exec sudo -E bash "$0" "$@"
fi


if [[ $# -ne 1 ]]; then
  echo "ERROR: Missing required device argument." >&2
  usage >&2
  exit 2
fi

dev="$1"

if [[ "$dev" != /dev/* ]]; then
  echo "ERROR: Device must be a /dev/... path (got: $dev)" >&2
  usage >&2
  exit 2
fi

if [[ ! -b "$dev" ]]; then
  echo "ERROR: $dev is not a block device (does it exist?)" >&2
  exit 2
fi

ts="$(date +%s)"
out="test-nvme-${ts}.txt"
exec > >(tee -a "$out") 2>&1

echo "==== NVMe HEALTH TEST ===="
echo "Timestamp: $ts"
echo "Date:      $(date -Is)"
echo "Host:      $(hostname)"
echo "Kernel:    $(uname -a)"
echo "Input dev: $dev"
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
run apt-get install -y nvme-cli smartmontools

# Derive controller device for logs that require it:
# /dev/nvme0n1 -> /dev/nvme0
ctrl="$dev"
if [[ "$dev" =~ ^(/dev/nvme[0-9]+)n[0-9]+$ ]]; then
  ctrl="${BASH_REMATCH[1]}"
fi

echo
echo "Derived controller for nvme-cli logs: $ctrl"

run nvme list
run nvme smart-log "$ctrl"
run nvme error-log "$ctrl"
run smartctl -a "$dev"

echo

echo "Approx TB written (from nvme smart-log data_units_written):"
duw="$(nvme smart-log "$ctrl" 2>/dev/null | awk '/data_units_written/ {print $3}' | head -n1 || true)"
if [[ -n "${duw:-}" ]]; then
  awk -v du="$duw" 'BEGIN{printf "data_units_written=%s -> Approx TB written: %.2f TB\n", du, (du*512000)/1e12}'
else
  echo "Could not parse data_units_written."
fi

echo
echo "Saved: $out"

