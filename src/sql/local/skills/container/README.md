# AI Container SKILL Artifacts

These scripts install and configure Ollama (embedding model server) and Caddy (TLS reverse proxy) inside the SQL Server 2025 Linux container during the demo bootstrap.

## Problem Solved

The Build.ps1 bootstrap was failing when copying these scripts from an external path (`c:\bwsql\ollama\container`) to the Docker container:

1. **CRLF line ending issue**: Windows PowerShell automatically converted LF to CRLF. The container's `sh` interpreter then treated `set -e\r` as an invalid flag `set -e\r` → "invalid option" error.

2. **Missing system dependencies**: Azure Linux 3.0 minimal container image ships only ~3 CA certificates and lacks `zstd`, `tar`, and other tools.
   - `ca-certificates`: Required for SSL/TLS cert validation (curl needs Mozilla's CA bundle)
   - `zstd`: Required for decompressing Ollama installer
   - `tar`: Required for extracting Caddy tarball

## Scripts

| Script | Purpose |
|--------|---------|
| `01-install-ollama.sh` | Install Ollama (embedding model server); unconditionally install ca-certificates, zstd, tar for both apt-get and tdnf. |
| `02-install-caddy.sh` | Install Caddy (TLS reverse proxy) from GitHub releases; stage Caddyfile at `/etc/caddy/Caddyfile`. |
| `03-start-services.sh` | Start Ollama and Caddy as background daemons (idempotent — skips if already running). |
| `04-pull-model.sh` | Pull the embedding model (default: mxbai-embed-large). |
| `05-trust-caddy-ca.sh` | Copy Caddy's self-signed CA certificate to `/var/opt/mssql/security/ca-certificates/` so SQL Server's sp_invoke_external_rest_endpoint trusts the Caddy-fronted endpoint. |
| `Caddyfile` | Caddy configuration: reverse proxy for Ollama on port 8444 with internal TLS. |

## Usage

These scripts are called automatically by [Prepare-AiContainer.ps1](../Prepare-AiContainer.ps1) as part of the Build.ps1 bootstrap (Step 11). All scripts run as root inside the running SQL Server container.

## Validation Baseline

These scripts have been validated end-to-end (Build.ps1 → Verify-Build.ps1 → Start-LiveSite.ps1 → full MCP agent triage workflow). Per AGENTS.md:

> **Validated baselines — do not "improve" without measuring.** Mirror their patterns; do not rewrite them from memory.

If modifying these scripts, test the entire `Build.ps1` → `Verify-Build.ps1` → `Start-LiveSite.ps1` workflow and confirm models load, embeddings work, and diagnostic procs execute successfully.

## Key Implementation Details

- **All scripts must be LF, not CRLF** (no carriage returns).
- **ca-certificates, zstd, tar must be installed unconditionally** — Azure Linux 3.0 minimal doesn't include them.
- **Ollama runs as background daemon with OLLAMA_KEEP_ALIVE=-1** to preserve models in memory during MCP calls.
- **Caddy uses internal TLS** (`tls internal`) with a self-signed local CA — the CA cert must be installed in SQLPAL's trust store after Caddy starts for the first time.
- **Container restart is required** after `05-trust-caddy-ca.sh` so SQL Server re-reads the CA certificate store at startup.
