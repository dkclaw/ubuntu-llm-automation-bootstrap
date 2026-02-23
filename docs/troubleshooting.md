# Troubleshooting

## Docker permission denied
Log out and back in after bootstrap (docker group membership refresh), then run:
```bash
docker ps
```

## Ollama not reachable
```bash
systemctl status ollama --no-pager
journalctl -u ollama -n 200 --no-pager
curl -v http://127.0.0.1:11434/api/tags
```

## ROCm tools missing
```bash
cat /var/log/bootstrap-rocm.log
apt-cache policy rocm rocminfo
```

## UFW locked you out
Use console/KVM access and adjust allowed CIDRs:
```bash
sudo ufw status numbered
sudo ufw allow from <your-cidr> to any port 22 proto tcp
```

## Tailscale not exposing
```bash
sudo systemctl status tailscaled --no-pager
tailscale status
tailscale serve status
```
