#!/usr/bin/env bash
set -u
set -o pipefail

usage() {
  cat <<EOF
Usage:
  sudo ./test-sata.sh /dev/sda
  sudo ./test-sata.sh /dev/sdb

Notes:
  - Pass the disk device (e.g. /dev/sda), not a partition (e.g. /dev/sda1).
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

# Soft warning if they pass a partition
if [[ "$dev" =~ [0-9]+$ ]]; then
  echo "WARNING: $dev looks like a partition. Prefer the whole disk (e.g. /dev/sda)."
fi

ts="$(date +%s)"
out="test-sata-${ts}.txt"

exec > >(tee -a "$out") 2>&1

echo "==== SATA HEALTH TEST ===="
echo "Timestamp: $ts"
echo "Date:      $(date -Is)"
echo "Host:      $(hostname)"
echo "Kernel:    $(uname -a)"
echo "Device:    $dev"

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
run apt-get install -y smartmontools

run smartctl -a "$dev"

echo
echo "Saved: $out"

