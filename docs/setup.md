# Setup Notes

## Post-bootstrap reboot flow (if ROCm installed)
1. Reboot the machine.
2. Verify GPU/ROCm:
   - `lsmod | grep amdgpu`
   - `/opt/rocm/bin/rocminfo || rocminfo`
   - `clinfo`
3. Verify Ollama:
   - `systemctl status ollama`
   - `curl http://127.0.0.1:11434/api/tags`

## Tailscale serve examples

### HTTPS tailnet endpoint (recommended)
```bash
sudo tailscale serve https / http://127.0.0.1:11434
```

### Raw TCP endpoint
```bash
sudo tailscale serve tcp 11434 tcp://127.0.0.1:11434
```

Check/disable:
```bash
tailscale serve status
sudo tailscale serve reset
```
