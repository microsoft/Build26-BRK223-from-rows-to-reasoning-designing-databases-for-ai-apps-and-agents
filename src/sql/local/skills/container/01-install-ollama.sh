#!/bin/sh        
# 01-install-ollama.sh — install Ollama into a SQL Server 2025 Linux container.
# Run as root inside the container.
set -e

if command -v ollama >/dev/null 2>&1; then
    echo "ollama already installed: $(ollama --version 2>&1 | head -1)"
    exit 0
fi

# Need curl + tar + ca-certificates; Azure Linux 3.0 base image has curl but
# only 3 CA certs (no Mozilla bundle) — install ca-certificates unconditionally.
if command -v apt-get >/dev/null 2>&1; then
    apt-get update && apt-get install -y --no-install-recommends curl ca-certificates zstd tar
elif command -v tdnf >/dev/null 2>&1; then
    tdnf install -y curl ca-certificates zstd tar
fi

curl -fsSL https://ollama.com/install.sh | sh

mkdir -p /var/lib/ollama /var/log/ai
echo "ollama installed: $(ollama --version 2>&1 | head -1)"
