# AI Agent Guidelines

This file contains instructions and guidelines for AI agents working on this repository.

## 🔒 Security Best Practices

**Never commit sensitive information to this repository:**
- API keys, tokens, or credentials
- Personal access tokens (PATs)
- Database connection strings with passwords
- Environment-specific configuration values

**For MCP configuration files (`mcp.json`):**
- Use placeholder values like `"YOUR_API_KEY_HERE"` or `"${API_KEY}"`
- Reference environment variables for sensitive data
- Include documentation about required environment variables

## 📋 Repository Guidelines

### Purpose
This repository is a Microsoft Build 2026 session content repository and should:
- Provide clear, actionable content for session attendees
- Support self-guided learning for remote/at-home learners
- Follow the structure established by GUIDANCE.md

### What NOT to modify without permission:
- License files (`LICENSE`, `LICENSE-DOCS`, `CODE_OF_CONDUCT.md`)
- Security files (`SECURITY.md`)
- GitHub workflow files in `.github/` directory

### Content Rules
- No large binary files (PowerPoint decks, videos, recordings) in the repo
- Links to slides and recordings are fine — just don't host the actual files
- All README files should be kept up to date
- Unused folders (containing only a placeholder README) should be removed before release

### Issue Management
When a user reports a problem, asks a question that should be tracked, or wants to file an issue:

1. **Discover available templates** — Check `.github/ISSUE_TEMPLATE/` for any `.yml` or `.md` template files. Read them to understand what fields and labels each template expects.
2. **Match the request to a template** — Based on what the user is describing, pick the best-fit template. If no templates exist, create a plain issue.
3. **Help the user fill in the fields** — Walk through the template's required fields interactively, proposing answers where possible.
4. **Create the issue** — Use `gh issue create --template <template-file>` if a template matches, or `gh issue create` for a plain issue.
5. **Apply labels** — Check `gh label list` to see what labels exist in the repo. Apply relevant labels based on the issue type. Don't try to apply labels that don't exist.

When reviewing open issues at the start of each phase, summarize them and propose actions — this behavior already exists in the Issue Tracking and Commits section of GUIDANCE.md.

### Getting Started
If this repo still has a `GUIDANCE.md` file, that means setup isn't complete yet. Read it and follow the instructions to prepare the repo for publication.

---

## Per-Demo Guidance

Each top-level folder under `src/` is its own self-contained demo with its
own conventions. Read the section that matches the folder you're editing.
If you add a new demo (e.g. `src/cosmosdb/`, `src/horizondb/`), append a
peer section here.

### SQL Demo (`src/sql/`)

End-to-end Azure SQL + AI agent demo. Read [src/sql/README.md](src/sql/README.md)
first before changing anything under that tree.

**Validated baselines — do not "improve" without measuring.**
These files have been validated end-to-end (Build → Verify → Start → Insert
→ agent triage). Mirror their patterns; do not rewrite them from memory.

- `.github/agents/live-site-sql.agent.md` — agent system prompt + MCP tool list
- `.github/skills/live-site-sql/SKILL.md` — 7-step triage protocol
- `src/sql/local/Build.ps1` — 13-step one-shot bootstrap
- `src/sql/local/Common.ps1` — shared helpers (`Get-Sqlsim`, `Invoke-SqlsimScript`)
- `src/sql/local/sqlscripts/*.sql` — numbered deploy scripts; order is encoded in `deploy-prestage.ps1`

**T-SQL authoring rules.**

- `CREATE EXTERNAL MODEL` — `MODEL_TYPE` is `EMBEDDINGS` only. There is no
  `CHAT_COMPLETIONS` value; chat goes through `sp_invoke_external_rest_endpoint`.
- `API_FORMAT` valid values: `Ollama`, `Azure OpenAI`, `OpenAI`, `ONNX Runtime`.
  Local uses `Ollama`; cloud uses `Azure OpenAI`.
- If you replace `sqlsim` with `sqlcmd`, prepend
  `SET QUOTED_IDENTIFIER ON; SET ANSI_NULLS ON; SET ARITHABORT ON;
  SET CONCAT_NULL_YIELDS_NULL ON; SET ANSI_PADDING ON; SET ANSI_WARNINGS ON;
  SET NUMERIC_ROUNDABORT OFF;` or JSON / DiskANN index creation will fail
  Msg 1934. `sqlsim` sets these automatically.

**Tooling resolution.**

- **sqlsim**: always go through `Common.ps1::Get-Sqlsim`. Never hardcode
  an absolute path. The bundled `src/sql/local/utilities/sqlsim.exe` is
  the default; `$env:SQLSIM_PATH` overrides it.
- **SQL container image**: `Build.ps1` requires `-SqlImage` or
  `$env:BRK223_SQL_IMAGE`. There is no public default by design — the
  authoring image is a private Microsoft Azure SQL preview;
  `mcr.microsoft.com/mssql/server:2025-latest` is the documented public
  alternative.

**Ports and wiring** (changing any of these means updating every consumer):

| Port | Service | Set in |
|---|---|---|
| `14330` | SQL (host) → `1433` (container) | `Start-AzureSqlContainer.ps1` |
| `8080` | Blazor WASM | `apphost.cs` |
| `8765` | DAB REST + MCP (user-facing) | `apphost.cs` (`WithHttpEndpoint port: 8765, targetPort: 5000`) |

The MCP URL `http://localhost:8765/mcp` is referenced by `.vscode/mcp.json`
and (via the `zavalivesite-sql` toolset) by
`.github/agents/live-site-sql.agent.md`. Changing the port means updating
all three.

**Files that look deletable but aren't.**

- `src/sql/azure/bicep/*.json` — compiled ARM, referenced by
  `Prep-Cloud.ps1 -p @params.json`. Keep next to the `.bicep` sources.
- `src/sql/local/utilities/sqlsim.exe` — checked-in binary the demo
  depends on. Keep.
- `src/sql/local/sqlscripts/_bootstrap_login.sql`,
  `src/sql/local/sqlscripts/_reset_for_beat2.sql` — leading underscore
  means "interactive / out-of-band," not "unused." Both are referenced
  from `deploy-prestage.ps1` / `Reset-ForBeat2.ps1`.

