#!/bin/sh        
# 03-start-services.sh — start Ollama and Caddy as background daemons.
# Idempotent: skips anything already running. Run as root inside the container.
set -e
mkdir -p /var/lib/ollama /var/log/ai

if ! pgrep -f "ollama serve" >/dev/null 2>&1; then
    OLLAMA_HOST=127.0.0.1:11434 OLLAMA_MODELS=/var/lib/ollama \
    OLLAMA_KEEP_ALIVE=-1 \
        nohup /usr/local/bin/ollama serve >/var/log/ai/ollama.log 2>&1 < /dev/null &
    disown 2>/dev/null || true
    echo "started ollama (keep_alive=-1)"
else
    echo "ollama already running (pid $(pgrep -f 'ollama serve' | head -1))"
fi

if ! pgrep -f 'caddy run' >/dev/null 2>&1; then
    nohup /usr/local/bin/caddy run --config /etc/caddy/Caddyfile \
        >/var/log/ai/caddy.log 2>&1 < /dev/null &
    disown 2>/dev/null || true
    echo "started caddy"
else
    echo "caddy already running (pid $(pgrep -f 'caddy run' | head -1))"
fi

sleep 3
echo "ollama  : $(curl -fsS http://127.0.0.1:11434/api/version 2>/dev/null || echo DOWN)"
echo "caddy   : $(curl -fsSk https://127.0.0.1:8444/api/version 2>/dev/null || echo DOWN)"
echo "models  : $(curl -fsSk https://127.0.0.1:8444/v1/models 2>/dev/null | head -c 200 || echo DOWN)"
