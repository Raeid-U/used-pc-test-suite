#!/usr/bin/env bash
set -u
set -o pipefail

usage() {
  cat <<EOF
Usage:
  sudo ./log-telemetry.sh <interval_seconds> [outfile]

Examples:
  sudo ./log-telemetry.sh 10
  sudo ./log-telemetry.sh 15 /tmp/telemetry-$(date +%s).log

Notes:
  - Designed for Ubuntu Live USB.
  - Requires internet on first run to apt install tools (if missing).
  - Logs turbostat + sensors data every interval.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  exec sudo -E bash "$0" "$@"
fi

if [[ $# -lt 1 ]]; then
  echo "ERROR: Missing <interval_seconds>." >&2
  usage >&2
  exit 2
fi

interval="$1"
out="${2:-/tmp/telemetry-$(date +%s).log}"

if ! [[ "$interval" =~ ^[0-9]+$ ]] || [[ "$interval" -lt 1 ]]; then
  echo "ERROR: interval must be a positive integer (got: $interval)" >&2
  exit 2
fi

# Install deps only if missing (nice for Live USB)
need_apt=0
command -v sensors >/dev/null 2>&1 || need_apt=1
command -v turbostat >/dev/null 2>&1 || need_apt=1

if [[ "$need_apt" -eq 1 ]]; then
  echo "Installing tools (lm-sensors + turbostat) ..."
  apt-get update -y >/dev/null
  apt-get install -y lm-sensors linux-tools-common linux-tools-generic >/dev/null
fi

# Auto-detect sensors (safe if it fails; we'll still log what we can)
sensors-detect --auto >/dev/null 2>&1 || true

echo "Logging every ${interval}s -> ${out}"
echo "Ctrl+C to stop."

{
  echo "==== TELEMETRY LOG START ===="
  echo "Start:   $(date -Is)"
  echo "Host:    $(hostname)"
  echo "Kernel:  $(uname -a)"
  echo "Interval:${interval}s"
  echo

  echo "[lscpu summary]"
  lscpu | sed -n '1,25p'
  echo
} >> "$out"

# Capture a turbostat header once (and a first sample)
tb_first="$(timeout 2s turbostat --quiet --Summary --interval 1 2>/dev/null || true)"
tb_header="$(echo "$tb_first" | head -n1)"
tb_data="$(echo "$tb_first" | tail -n1)"

{
  echo "---- TURBOSTAT HEADER ----"
  echo "$tb_header"
  echo "--------------------------"
  echo
} >> "$out"

sample=0
while true; do
  sample=$((sample + 1))
  now_iso="$(date -Is)"
  now_epoch="$(date +%s)"

  # Take a quick 1s turbostat sample and keep only the last line (data)
  tb_line="$(timeout 2s turbostat --quiet --Summary --interval 1 2>/dev/null | tail -n1 || true)"

  # Grab key temperature lines (Intel usually has Package id 0 / Core N)
  sens_lines="$(sensors 2>/dev/null | egrep -i 'Package id|Core [0-9]+|Tctl|Tdie|Composite' || true)"

  # Lightweight context
  loadavg="$(cat /proc/loadavg 2>/dev/null || true)"
  mem_line="$(free -h 2>/dev/null | awk 'NR==2{print "Mem: used="$3" free="$4" avail="$7}' || true)"

  {
    echo "=== SAMPLE ${sample} ==="
    echo "TS_ISO:   ${now_iso}"
    echo "TS_EPOCH: ${now_epoch}"
    echo "LOADAVG:  ${loadavg}"
    echo "${mem_line}"
    echo
    echo "TURBOSTAT:"
    echo "${tb_header}"
    echo "${tb_line}"
    echo
    echo "SENSORS:"
    echo "${sens_lines}"
    echo "========================="
    echo
  } >> "$out"

  sleep "$interval"
done

