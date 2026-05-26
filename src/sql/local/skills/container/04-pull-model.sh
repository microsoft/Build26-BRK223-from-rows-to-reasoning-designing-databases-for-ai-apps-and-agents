#!/bin/sh        
# 04-pull-model.sh — pull an embedding model. Default: mxbai-embed-large (1024 dim).
# Override with first arg or MODEL env var. Run as root inside the container.
set -e
MODEL="${1:-${MODEL:-mxbai-embed-large}}"

if ! pgrep -f "ollama serve" >/dev/null 2>&1; then
    echo "ollama is not running; run 03-start-services.sh first" >&2
    exit 1
fi

ollama pull "$MODEL"
ollama list
