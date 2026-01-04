#!/usr/bin/env bash
set -u
set -o pipefail

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  exec sudo -E bash "$0" "$@"
fi

ts="$(date +%s)"
out="test-cpu-${ts}.txt"

exec > >(tee -a "$out") 2>&1

echo "==== CPU TEST ===="
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
run apt-get install -y stress-ng

# Optional: set governor to performance (helps consistency)
run apt-get install -y linux-cpupower || true
if command -v cpupower >/dev/null 2>&1; then
  run cpupower frequency-set -g performance || true
fi

# Optional: turbostat availability (nice to have)
run apt-get install -y linux-tools-common linux-tools-generic || true

echo
echo "Running CPU load test (15 minutes): stress-ng --cpu 12 --cpu-method matrixprod --timeout 15m --metrics-brief"
echo "Tip: run ./sensors.sh in another terminal to watch temps."
echo


# If turbostat exists, run it in the background for the duration
if command -v turbostat >/dev/null 2>&1; then
  echo "turbostat detected: will log turbostat summary during stress run."
  turbostat --Summary --interval 5 >"turbostat-${ts}.txt" 2>&1 &

  tpid=$!
else
  tpid=""
fi

stress-ng --cpu 12 --cpu-method matrixprod --timeout 15m --metrics-brief
ec=$?
echo "Exit code: $ec"

if [[ -n "${tpid:-}" ]]; then
  echo "Stopping turbostat pid=$tpid"
  kill "$tpid" 2>/dev/null || true
  echo "Saved: turbostat-${ts}.txt"
fi

echo
echo "Saved: $out"

