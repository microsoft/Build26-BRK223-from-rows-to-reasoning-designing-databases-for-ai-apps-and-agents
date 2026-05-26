#!/bin/sh        
# 02-install-caddy.sh — install Caddy into a SQL Server 2025 Linux container
# and stage Caddyfile at /etc/caddy/Caddyfile. Run as root inside the container.
set -e

CADDY_VERSION="${CADDY_VERSION:-2.11.2}"

if command -v caddy >/dev/null 2>&1; then
    echo "caddy already installed: $(caddy version)"
else
    ARCH="$(uname -m)"
    case "$ARCH" in
        x86_64)  CARCH=amd64 ;;
        aarch64) CARCH=arm64 ;;
        *) echo "unsupported arch: $ARCH" >&2; exit 1 ;;
    esac
    URL="https://github.com/caddyserver/caddy/releases/download/v${CADDY_VERSION}/caddy_${CADDY_VERSION}_linux_${CARCH}.tar.gz"
    cd /tmp
    curl -fsSL "$URL" -o caddy.tgz
    tar -xzf caddy.tgz caddy
    install -m 0755 caddy /usr/local/bin/caddy
    rm -f caddy.tgz caddy
    echo "caddy installed: $(caddy version)"
fi

mkdir -p /etc/caddy /var/log/ai
SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
cp "$SCRIPT_DIR/Caddyfile" /etc/caddy/Caddyfile
echo "/etc/caddy/Caddyfile staged."
