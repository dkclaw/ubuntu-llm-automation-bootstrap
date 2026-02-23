# Ubuntu 24.04 Local LLM + Automation Bootstrap

Idempotent bootstrap for a fresh **headless Ubuntu Server 24.04 LTS** to become:
- AMD ROCm + Ollama local model host
- Tailscale-accessible private inference endpoint
- SSH/tmux coding host
- Docker host for automation stacks

## What this config does

- System updates + essential packages
- SSH + UFW hardening (LAN-only SSH by default)
- Docker CE + Compose plugin (official Docker repo)
- Docker log limits (`max-size=50m`, `max-file=3`)
- Tailscale install + guided interactive `tailscale up`
- Optional ROCm install (with reboot checkpoint)
- Ollama ROCm tarball install bound to `127.0.0.1:11434`
- Optional Ollama storage relocation to `/srv/ollama`
- Optional starter stack template (`n8n + postgres + redis`)

## Repo structure

- `bootstrap/bootstrap.sh` - main interactive bootstrap entrypoint
- `bootstrap/functions.sh` - idempotent install/config helpers
- `bootstrap/checks.sh` - OS/root/sanity checks
- `systemd/ollama.override.conf` - sample override
- `docker/daemon.json` - log policy
- `docker/compose/n8n-stack/compose.yml` - optional stack template
- `docs/setup.md` - post-install steps
- `docs/troubleshooting.md` - common fixes
- `config.example.env` - optional prefilled defaults

## One-command usage

```bash
git clone <THIS-REPO-URL>
cd ubuntu-llm-automation-bootstrap
cp config.example.env .env   # optional
sudo bash bootstrap/bootstrap.sh
```

## Interactive questions asked up front

1. Ubuntu/hostname confirmation
2. Username to configure
3. Timezone
4. LAN CIDR(s) allowed for SSH
5. Add SSH public key now? (value or path)
6. Enable Tailscale SSH?
7. Expose Ollama via Tailscale Serve? (HTTPS or TCP)
8. Install ROCm now?
9. Relocate Ollama storage to `/srv`?
10. Install optional starter stacks now or later?
11. Enable unattended-upgrades?

## Verify health

After bootstrap (and reboot if ROCm installed):

```bash
sudo llm-server-verify
```

or

```bash
make verify
```

## Notes

- Script is safe to re-run (idempotent patterns, no duplicate key lines).
- It **does not** disable SSH password auth automatically.
- Tailscale auth is intentionally manual (secure interactive flow).
- Logs:
  - `/var/log/bootstrap.log`
  - `/var/log/bootstrap-rocm.log`
  - `/var/log/bootstrap-ollama.log`

## Optional stack launch

```bash
cd docker/compose/n8n-stack
docker compose up -d
```

Update secrets/passwords in the compose file before production use.
