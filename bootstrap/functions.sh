#!/usr/bin/env bash
set -euo pipefail

LOG_FILE=/var/log/bootstrap.log
ROCM_LOG=/var/log/bootstrap-rocm.log
OLLAMA_LOG=/var/log/bootstrap-ollama.log

log() { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*" | tee -a "$LOG_FILE"; }

ask_yn() {
  local prompt="$1" default="${2:-no}" ans
  local hint="[y/N]"; [[ "$default" == "yes" ]] && hint="[Y/n]"
  read -r -p "$prompt $hint: " ans
  ans="${ans:-$default}"
  [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]]
}

install_base_packages() {
  log "Updating apt and installing base packages"
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl wget git tmux htop ncdu ca-certificates gnupg lsb-release unzip jq \
    openssh-server ufw software-properties-common apt-transport-https \
    pciutils usbutils
}

set_timezone() {
  local tz="$1"
  timedatectl set-timezone "$tz"
  log "Timezone set to $tz"
}

enable_unattended_upgrades() {
  DEBIAN_FRONTEND=noninteractive apt-get install -y unattended-upgrades
  dpkg-reconfigure -f noninteractive unattended-upgrades || true
  systemctl enable --now unattended-upgrades || true
  log "Unattended upgrades enabled"
}

setup_dirs() {
  mkdir -p /opt/stacks /srv/models /srv/ollama
  chmod 755 /opt/stacks /srv/models /srv/ollama
  log "Created /opt/stacks and /srv model directories"
}

configure_ssh_and_ufw() {
  local lan_cidrs="$1"
  systemctl enable --now ssh

  ufw --force reset
  ufw default deny incoming
  ufw default allow outgoing

  IFS=',' read -ra cidrs <<< "$lan_cidrs"
  for c in "${cidrs[@]}"; do
    [[ -n "$c" ]] && ufw allow from "$c" to any port 22 proto tcp
  done

  ufw --force enable
  log "UFW configured. SSH allowed only from: $lan_cidrs"
}

add_ssh_key_if_requested() {
  local user="$1" key_value="$2" key_path="$3"
  local home_dir
  home_dir=$(getent passwd "$user" | cut -d: -f6)
  mkdir -p "$home_dir/.ssh"
  chmod 700 "$home_dir/.ssh"

  local key=""
  if [[ -n "$key_value" ]]; then
    key="$key_value"
  elif [[ -n "$key_path" && -f "$key_path" ]]; then
    key=$(cat "$key_path")
  fi

  if [[ -n "$key" ]]; then
    touch "$home_dir/.ssh/authorized_keys"
    grep -qxF "$key" "$home_dir/.ssh/authorized_keys" || echo "$key" >> "$home_dir/.ssh/authorized_keys"
    chmod 600 "$home_dir/.ssh/authorized_keys"
    chown -R "$user:$user" "$home_dir/.ssh"
    log "SSH public key installed for $user"
  fi
}

install_docker() {
  log "Installing Docker CE + Compose plugin"
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo \"$VERSION_CODENAME\") stable" > /etc/apt/sources.list.d/docker.list

  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  cat >/etc/docker/daemon.json <<'JSON'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "50m",
    "max-file": "3"
  }
}
JSON

  systemctl enable --now docker
  systemctl restart docker
  log "Docker installed and started"
}

docker_post_config() {
  local user="$1"
  usermod -aG docker "$user" || true
  docker run --rm hello-world >/dev/null 2>&1 || true
  log "Added $user to docker group (re-login required)"
}

install_tailscale() {
  log "Installing Tailscale"
  curl -fsSL https://tailscale.com/install.sh | sh
  systemctl enable --now tailscaled
}

print_tailscale_next_steps() {
  local enable_ssh="$1" expose="$2" mode="$3"
  log "Run this manually to authenticate Tailscale:"
  echo "  sudo tailscale up"
  if [[ "$enable_ssh" == "yes" ]]; then
    echo "  sudo tailscale up --ssh"
  fi
  echo "Check MagicDNS: tailscale status"
  if [[ "$expose" == "yes" ]]; then
    if [[ "$mode" == "https" ]]; then
      echo "Expose Ollama over HTTPS tailnet: sudo tailscale serve https / http://127.0.0.1:11434"
    else
      echo "Expose Ollama over TCP tailnet:  sudo tailscale serve tcp 11434 tcp://127.0.0.1:11434"
    fi
    echo "Serve status: tailscale serve status"
    echo "Disable serve: sudo tailscale serve reset"
  fi
}

install_rocm() {
  log "Installing AMD ROCm (Ubuntu 24.04)"
  : > "$ROCM_LOG"
  {
    apt-get install -y "linux-headers-$(uname -r)" "linux-modules-extra-$(uname -r)" || true
    wget -qO - https://repo.radeon.com/rocm/rocm.gpg.key | gpg --dearmor > /usr/share/keyrings/rocm-archive-keyring.gpg
    echo 'deb [arch=amd64 signed-by=/usr/share/keyrings/rocm-archive-keyring.gpg] https://repo.radeon.com/rocm/apt/debian/ jammy main' > /etc/apt/sources.list.d/rocm.list
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y rocm rocminfo clinfo || true
    usermod -aG render,video "$SUDO_USER" || true
  } >> "$ROCM_LOG" 2>&1

  log "ROCm install attempted. Reboot required before verification."
}

install_ollama_rocm() {
  log "Installing Ollama ROCm tarball"
  : > "$OLLAMA_LOG"
  {
    local tmpd
    tmpd=$(mktemp -d)
    cd "$tmpd"
    curl -fL -o ollama.tgz https://ollama.com/download/ollama-linux-amd64-rocm.tgz
    tar -xzf ollama.tgz
    install -m 755 bin/ollama /usr/local/bin/ollama

    id -u ollama >/dev/null 2>&1 || useradd -r -s /usr/sbin/nologin -m -d /var/lib/ollama ollama

    cat >/etc/systemd/system/ollama.service <<'UNIT'
[Unit]
Description=Ollama Service
After=network-online.target

[Service]
ExecStart=/usr/local/bin/ollama serve
User=ollama
Group=ollama
Restart=always
RestartSec=3
Environment=OLLAMA_HOST=127.0.0.1:11434

[Install]
WantedBy=multi-user.target
UNIT

    systemctl daemon-reload
    systemctl enable --now ollama
  } >> "$OLLAMA_LOG" 2>&1

  curl -sf http://127.0.0.1:11434/api/tags >/dev/null && log "Ollama reachable on localhost"
}

relocate_ollama_storage() {
  log "Relocating Ollama data to /srv/ollama"
  systemctl stop ollama || true
  mkdir -p /srv/ollama
  if [[ -d /var/lib/ollama && ! -L /var/lib/ollama ]]; then
    rsync -a /var/lib/ollama/ /srv/ollama/ || true
  fi
  chown -R ollama:ollama /srv/ollama

  mkdir -p /etc/systemd/system/ollama.service.d
  cat >/etc/systemd/system/ollama.service.d/override.conf <<'CONF'
[Service]
Environment=OLLAMA_MODELS=/srv/ollama/models
Environment=OLLAMA_HOST=127.0.0.1:11434
CONF

  mkdir -p /srv/ollama/models
  chown -R ollama:ollama /srv/ollama
  systemctl daemon-reload
  systemctl start ollama
  log "Ollama storage relocation configured"
}

write_verify_script() {
cat >/usr/local/bin/llm-server-verify <<'VERIFY'
#!/usr/bin/env bash
set -euo pipefail

echo "== Host =="
echo "Hostname: $(hostname)"
echo "Uptime: $(uptime -p)"

echo "\n== SSH/UFW =="
systemctl is-active ssh || true
ufw status || true

echo "\n== Tailscale =="
command -v tailscale >/dev/null && tailscale status | head -n 20 || echo "tailscale not installed"

echo "\n== Docker =="
systemctl is-active docker || true
docker --version 2>/dev/null || true
docker ps --format 'table {{.Names}}\t{{.Status}}' 2>/dev/null || true

echo "\n== ROCm/GPU =="
lsmod | grep amdgpu || true
command -v rocminfo >/dev/null && rocminfo | head -n 40 || echo "rocminfo not found"

echo "\n== Ollama =="
systemctl is-active ollama || true
curl -s http://127.0.0.1:11434/api/tags || echo "ollama API not reachable"
VERIFY
chmod +x /usr/local/bin/llm-server-verify
}
