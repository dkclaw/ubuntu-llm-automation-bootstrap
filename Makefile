.PHONY: bootstrap tailscale docker ollama verify status

bootstrap:
	sudo bash bootstrap/bootstrap.sh

docker:
	sudo systemctl status docker --no-pager
	docker --version

tailscale:
	tailscale status || true
	sudo tailscale serve status || true

ollama:
	systemctl status ollama --no-pager || true
	curl -s http://127.0.0.1:11434/api/tags || true

verify:
	sudo llm-server-verify

status:
	systemctl --user status openclaw-gateway --no-pager || true
	systemctl status docker ollama ssh tailscaled --no-pager || true
