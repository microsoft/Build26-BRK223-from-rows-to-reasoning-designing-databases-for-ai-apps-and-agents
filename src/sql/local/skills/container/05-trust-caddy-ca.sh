#!/bin/sh        
# 05-trust-caddy-ca.sh — install Caddy's local-CA root cert into the SQLPAL
# trust folder so sp_invoke_external_rest_endpoint will trust the
# Caddy-fronted endpoint.
#
# This is the step that fixes "Msg 31608 ... HRESULT: 0x80070008".
#
# After running this you MUST restart the container so sqlservr re-reads
# /var/opt/mssql/security/ca-certificates/ at startup. The errorlog will print:
#     Server      Installing Client TLS certificates to the store.
#
# Run as root inside the container.
set -e

# Caddy must have run at least once so the local CA exists.
CA_SRC="$(find / -path '*caddy*/pki/authorities/local/root.crt' 2>/dev/null | head -1)"
if [ -z "$CA_SRC" ]; then
    echo "Caddy local-CA root.crt not found. Start Caddy at least once first." >&2
    exit 1
fi
echo "found Caddy CA at: $CA_SRC"

DST_DIR=/var/opt/mssql/security/ca-certificates
mkdir -p "$DST_DIR"
cp "$CA_SRC" "$DST_DIR/caddy-local.crt"
chown -R mssql:mssql /var/opt/mssql/security
chmod 600 "$DST_DIR/caddy-local.crt"

ls -la "$DST_DIR"
echo
echo "Now restart the container:  docker restart <container-name>"
echo "Then re-run 03-start-services.sh (Caddy + Ollama do not auto-start)."
