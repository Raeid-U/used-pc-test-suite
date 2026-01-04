#!/usr/bin/env bash
set -u

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  exec sudo -E bash "$0" "$@"
fi

echo "Running: apt-get update"
apt-get update -y

echo "Running: apt-get install -y lm-sensors"
apt-get install -y lm-sensors


echo "Running: sensors-detect --auto"
sensors-detect --auto || true

echo
echo "Starting: watch -n1 sensors"
echo "(Ctrl+C to stop)"
watch -n1 sensors

