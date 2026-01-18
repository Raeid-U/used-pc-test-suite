#!/usr/bin/env bash
# test-dmz.sh
# Quick connectivity smoke-test from a VM/LXC (e.g., DMZ guest) to key IPs/ports.
# - Installs curl + netcat if missing (Debian/Ubuntu via apt), and removes them after unless KEEP_PKGS=1.
# - Reports ICMP (ping) + TCP port checks + optional HTTP(S) HEAD probes.

set -euo pipefail

KEEP_PKGS="${KEEP_PKGS:-0}"    # set KEEP_PKGS=1 to keep any packages this script installs
TIMEOUT_SEC="${TIMEOUT_SEC:-2}"

# Targets
TARGETS=(
  "192.168.0.1|router|80,443"
  "192.168.0.160|proxmox|8006,22"
  "192.168.0.162|jetkvm|80,443"
  "192.168.0.161|opnsense-wan|443"
  "10.10.10.1|opnsense-lan|443,53"
)

# ---------- helpers ----------
say() { printf '%s\n' "$*"; }
hr()  { printf '%s\n' "------------------------------------------------------------"; }

have() { command -v "$1" >/dev/null 2>&1; }

as_root() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    "$@"
  elif have sudo; then
    sudo -n "$@"
  else
    say "ERROR: need root (or sudo) to install missing packages."
    exit 1
  fi
}

installed_now=()

apt_install_if_missing() {
  local pkg="$1"
  dpkg -s "$pkg" >/dev/null 2>&1 && return 0
  as_root apt-get update -y >/dev/null
  as_root apt-get install -y "$pkg" >/dev/null
  installed_now+=("$pkg")
}

ensure_tools() {
  # We prefer nc + curl. If missing, install on Debian/Ubuntu.
  if have nc && have curl; then
    return 0
  fi

  if have apt-get; then
    have nc   || apt_install_if_missing netcat-openbsd
    have curl || apt_install_if_missing curl
    return 0
  fi

  # Fallback: no package manager handler
  say "WARN: nc/curl missing and unsupported package manager. Proceeding with limited tests."
}

cleanup_tools() {
  (( KEEP_PKGS == 1 )) && return 0
  ((${#installed_now[@]} == 0)) && return 0

  say
  say "Cleaning up packages installed by this script: ${installed_now[*]}"
  if have apt-get; then
    as_root apt-get remove -y "${installed_now[@]}" >/dev/null || true
    as_root apt-get autoremove -y >/dev/null || true
  fi
}

ping_test() {
  local ip="$1"
  if have ping; then
    if ping -c 1 -W 1 "$ip" >/dev/null 2>&1; then
      echo "OK"
    else
      echo "FAIL"
    fi
  else
    echo "N/A"
  fi
}

tcp_test_nc() {
  local ip="$1" port="$2"
  # netcat-openbsd supports: nc -n -z -w <sec> <host> <port>
  if nc -n -z -w "$TIMEOUT_SEC" "$ip" "$port" >/dev/null 2>&1; then
    echo "OPEN"
  else
    echo "CLOSED"
  fi
}

tcp_test_bash() {
  local ip="$1" port="$2"
  # Best-effort /dev/tcp fallback (no timeout built-in; wrap with timeout if available)
  if have timeout; then
    if timeout "${TIMEOUT_SEC}" bash -c ">/dev/tcp/${ip}/${port}" >/dev/null 2>&1; then
      echo "OPEN"
    else
      echo "CLOSED"
    fi
  else
    # Risk: could hang if network blackholes; keep short by background + sleep
    ( bash -c ">/dev/tcp/${ip}/${port}" >/dev/null 2>&1 ) && echo "OPEN" || echo "CLOSED"
  fi
}

tcp_test() {
  local ip="$1" port="$2"
  if have nc; then
    tcp_test_nc "$ip" "$port"
  else
    tcp_test_bash "$ip" "$port"
  fi
}

http_head() {
  local scheme="$1" ip="$2" port="$3"
  # -k to tolerate self-signed certs (OPNsense/Proxmox/JetKVM often are)
  # --connect-timeout and -m to avoid hanging
  if ! have curl; then
    echo "N/A"
    return
  fi

  local url
  if [[ "$port" == "80" && "$scheme" == "http" ]]; then
    url="http://${ip}/"
  elif [[ "$port" == "443" && "$scheme" == "https" ]]; then
    url="https://${ip}/"
  else
    url="${scheme}://${ip}:${port}/"
  fi

  if curl -k -sS -I --connect-timeout "$TIMEOUT_SEC" -m "$((TIMEOUT_SEC+1))" "$url" >/tmp/testdmz_curl.$$ 2>/dev/null; then
    awk 'NR==1{print $2" "$3; exit}' /tmp/testdmz_curl.$$ 2>/dev/null || echo "OK"
  else
    echo "FAIL"
  fi
  rm -f /tmp/testdmz_curl.$$ >/dev/null 2>&1 || true
}

# ---------- main ----------
trap cleanup_tools EXIT

ensure_tools

say "DMZ connectivity test"
say "Host: $(hostname)"
say "Time: $(date -Is)"
hr
printf "%-15s %-14s %-6s  %s\n" "IP" "NAME" "PING" "PORT TESTS"
hr

for entry in "${TARGETS[@]}"; do
  IFS='|' read -r ip name ports_csv <<<"$entry"

  ping_res="$(ping_test "$ip")"

  # Build port results string like: 443=OPEN (https:200 OK)
  port_results=()
  IFS=',' read -r -a ports <<<"$ports_csv"
  for p in "${ports[@]}"; do
    state="$(tcp_test "$ip" "$p")"
    extra=""
    # Add quick HTTP(S) hint for common web ports
    if [[ "$p" == "80" ]]; then
      extra=" (http:$(http_head http "$ip" "$p"))"
    elif [[ "$p" == "443" ]]; then
      extra=" (https:$(http_head https "$ip" "$p"))"
    fi
    port_results+=("${p}=${state}${extra}")
  done

  printf "%-15s %-14s %-6s  %s\n" "$ip" "$name" "$ping_res" "${port_results[*]}"
done

hr
say "Notes:"
say "- PING can fail even when TCP works (ICMP blocked)."
say "- From a DMZ guest, you'd typically expect 192.168.0.x to be CLOSED/time out."
say "- OPNsense GUI on 10.10.10.1:443 should be OPEN only from jump VM; others should be CLOSED."
