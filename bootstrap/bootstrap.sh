#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=checks.sh
source "$SCRIPT_DIR/checks.sh"
# shellcheck source=functions.sh
source "$SCRIPT_DIR/functions.sh"

require_root
require_ubuntu_24_04

[[ -f "${SCRIPT_DIR}/../.env" ]] && source "${SCRIPT_DIR}/../.env"

log_header "Local LLM + Automation Server Bootstrap"

HOSTNAME_NOW=$(hostname)
echo "Detected hostname: $HOSTNAME_NOW"
read -r -p "Confirm Ubuntu 24.04 host '$HOSTNAME_NOW'? [Y/n]: " host_ok
host_ok="${host_ok:-Y}"
[[ "${host_ok,,}" == "y" ]] || { echo "Aborted."; exit 1; }

DEFAULT_USER="${SUDO_USER:-$(logname 2>/dev/null || echo ubuntu)}"
read -r -p "Username to configure [$DEFAULT_USER]: " BOOTSTRAP_USERNAME
BOOTSTRAP_USERNAME="${BOOTSTRAP_USERNAME:-$DEFAULT_USER}"

read -r -p "Timezone (e.g. America/Chicago) [${TIMEZONE:-UTC}]: " TZ_IN
TIMEZONE="${TZ_IN:-${TIMEZONE:-UTC}}"

SUGGESTED_CIDRS=$(suggest_lan_cidrs)
read -r -p "LAN CIDR(s) for SSH (comma-separated) [${LAN_CIDRS:-$SUGGESTED_CIDRS}]: " CIDR_IN
LAN_CIDRS="${CIDR_IN:-${LAN_CIDRS:-$SUGGESTED_CIDRS}}"

ADD_KEY_DEFAULT="${ADD_SSH_KEY:-no}"
if ask_yn "Add SSH public key now?" "$ADD_KEY_DEFAULT"; then
  ADD_SSH_KEY="yes"
  read -r -p "SSH public key path (optional): " SSH_PUBLIC_KEY_PATH_IN || true
  SSH_PUBLIC_KEY_PATH="${SSH_PUBLIC_KEY_PATH_IN:-${SSH_PUBLIC_KEY_PATH:-}}"
  if [[ -z "${SSH_PUBLIC_KEY_PATH:-}" ]]; then
    read -r -p "Paste SSH public key (optional): " SSH_PUBLIC_KEY_VALUE_IN || true
    SSH_PUBLIC_KEY_VALUE="${SSH_PUBLIC_KEY_VALUE_IN:-${SSH_PUBLIC_KEY_VALUE:-}}"
  fi
else
  ADD_SSH_KEY="no"
fi

ENABLE_TS_SSH_DEFAULT="${ENABLE_TAILSCALE_SSH:-no}"
ask_yn "Enable Tailscale SSH?" "$ENABLE_TS_SSH_DEFAULT" && ENABLE_TAILSCALE_SSH=yes || ENABLE_TAILSCALE_SSH=no

ENABLE_SERVE_DEFAULT="${ENABLE_TAILSCALE_SERVE:-no}"
if ask_yn "Expose Ollama over Tailscale Serve?" "$ENABLE_SERVE_DEFAULT"; then
  ENABLE_TAILSCALE_SERVE=yes
  read -r -p "Serve mode https or tcp [${TAILSCALE_SERVE_MODE:-https}]: " SERVE_MODE_IN
  TAILSCALE_SERVE_MODE="${SERVE_MODE_IN:-${TAILSCALE_SERVE_MODE:-https}}"
else
  ENABLE_TAILSCALE_SERVE=no
fi

INSTALL_ROCM_DEFAULT="${INSTALL_ROCM_NOW:-yes}"
ask_yn "Install ROCm now?" "$INSTALL_ROCM_DEFAULT" && INSTALL_ROCM_NOW=yes || INSTALL_ROCM_NOW=no

RELOCATE_OLLAMA_DEFAULT="${RELOCATE_OLLAMA_TO_SRV:-yes}"
ask_yn "Relocate Ollama storage to /srv?" "$RELOCATE_OLLAMA_DEFAULT" && RELOCATE_OLLAMA_TO_SRV=yes || RELOCATE_OLLAMA_TO_SRV=no

read -r -p "Install optional stacks now or later? [${INSTALL_OPTIONAL_STACKS:-later}]: " STACKS_IN
INSTALL_OPTIONAL_STACKS="${STACKS_IN:-${INSTALL_OPTIONAL_STACKS:-later}}"

if ask_yn "Enable unattended-upgrades?" "${ENABLE_UNATTENDED_UPGRADES:-no}"; then
  ENABLE_UNATTENDED_UPGRADES=yes
else
  ENABLE_UNATTENDED_UPGRADES=no
fi

log_header "Applying base system setup"
install_base_packages
set_timezone "$TIMEZONE"
setup_dirs
[[ "$ENABLE_UNATTENDED_UPGRADES" == "yes" ]] && enable_unattended_upgrades

log_header "Applying SSH + UFW hardening"
configure_ssh_and_ufw "$LAN_CIDRS"
[[ "$ADD_SSH_KEY" == "yes" ]] && add_ssh_key_if_requested "$BOOTSTRAP_USERNAME" "${SSH_PUBLIC_KEY_VALUE:-}" "${SSH_PUBLIC_KEY_PATH:-}"

echo "[IMPORTANT] Password auth is left unchanged for safety. Disable only after key login is confirmed."

log_header "Installing Docker"
install_docker
docker_post_config "$BOOTSTRAP_USERNAME"

log_header "Installing Tailscale"
install_tailscale
print_tailscale_next_steps "$ENABLE_TAILSCALE_SSH" "$ENABLE_TAILSCALE_SERVE" "$TAILSCALE_SERVE_MODE"

if [[ "$INSTALL_ROCM_NOW" == "yes" ]]; then
  log_header "Installing ROCm"
  install_rocm
fi

log_header "Installing Ollama ROCm"
install_ollama_rocm

if [[ "$RELOCATE_OLLAMA_TO_SRV" == "yes" ]]; then
  relocate_ollama_storage
fi

write_verify_script

log_header "Optional Stacks"
if [[ "$INSTALL_OPTIONAL_STACKS" == "now" ]]; then
  log "Starter compose files available under /opt/stacks and repo docker/compose."
else
  log "Optional stacks deferred."
fi

if [[ "$INSTALL_ROCM_NOW" == "yes" ]]; then
  echo
  echo "ROCm was installed. Reboot is recommended now."
  echo "After reboot, run:"
  echo "  lsmod | grep amdgpu"
  echo "  /opt/rocm/bin/rocminfo || rocminfo"
  echo "  clinfo"
fi

echo
log "Bootstrap complete. Verify with: llm-server-verify"
