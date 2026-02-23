#!/usr/bin/env bash
set -euo pipefail

require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] Run as root (sudo)." >&2
    exit 1
  fi
}

require_ubuntu_24_04() {
  if [[ ! -f /etc/os-release ]]; then
    echo "[ERROR] Cannot detect OS." >&2
    exit 1
  fi
  . /etc/os-release
  if [[ "${ID:-}" != "ubuntu" || "${VERSION_ID:-}" != "24.04" ]]; then
    echo "[WARN] This script is designed for Ubuntu 24.04. Detected: ${PRETTY_NAME:-unknown}"
    read -r -p "Continue anyway? [y/N]: " ans
    [[ "${ans,,}" == "y" ]] || exit 1
  fi
}

suggest_lan_cidrs() {
  ip -4 -o addr show scope global | awk '{print $4}' | paste -sd ',' -
}

log_header() {
  echo
  echo "============================================================"
  echo "$1"
  echo "============================================================"
}
