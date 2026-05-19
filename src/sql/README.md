# BRK223 — *Azure SQL: From Database to Live Site, with AI Agents in the Loop*

An end-to-end sample showing how Azure SQL (vector + JSON + ledger + AI)
grounds an incident-triage agent. One container. One web page. One AI agent.

The two folders that matter:

- **[local/](local/)** — run the entire demo on a laptop. Single Docker container hosts SQL + Ollama + a Caddy TLS proxy; an Aspire AppHost wires up the Blazor WASM UI and the DAB REST/MCP endpoint.
- **[azure/](azure/)** — lift the same demo to Azure (Hyperscale + Azure OpenAI + APIM + Container Apps), all driven by Bicep.

Reference docs sit next to this README: **[design.md](design.md)** (locked design spec — schema, beats, contracts), **[demo.md](demo.md)** (the on-stage walkthrough). The inventory of every script and folder is in [What's in here](#whats-in-here) below.

---

## The T-SQL on display

This demo isn't a Blazor app that happens to call a database — it's a tour of the **Azure SQL / SQL Server 2025 AI surface**, and almost every interesting line is T-SQL. Highlights, with links to where they actually run:

### 1. One `INSERT` exercises **five** new T-SQL features at once

The on-stage "incident lands" moment ([local/sqlscripts/05_create_incident.sql](local/sqlscripts/05_create_incident.sql)) is a single `INSERT` that does:

```sql
INSERT dbo.Incident (..., AlertPayload, Tags, Embedding)
SELECT 5012,
       JSON_VALUE(@alert, '$.tenantId'),                  -- (1) JSON_VALUE on json type
       ...
       @alert,                                            -- (2) json column (not nvarchar(max))
       (SELECT COALESCE(
              JSON_VALUE(@alert, '$.errorCode'),
              (SELECT TOP 1 REPLACE(m.match_value, 'Msg ', '')
                 FROM REGEXP_MATCHES(@note,
                       '\bMsg\s+\d{3,5}\b') m))         -- (3) REGEXP_MATCHES
              AS errorCode, ...
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),            -- (4) FOR JSON PATH shape-on-the-fly
       AI_GENERATE_EMBEDDINGS(@note USE MODEL OllamaMxbai); -- (5) AI_GENERATE_EMBEDDINGS → vector(1024)
```

Five SQL Server 2025 / Azure SQL features in one statement: native `json` type, `REGEXP_MATCHES`, `FOR JSON PATH`, `AI_GENERATE_EMBEDDINGS ... USE MODEL`, and the `vector(N)` data type. No app-side glue, no separate embedding call, no JSON parsing in a middle tier.

### 2. `CREATE EXTERNAL MODEL` binds the database to an embedding model

[local/sqlscripts/01_schema.sql](local/sqlscripts/01_schema.sql) — one DDL statement points the database at the model that `AI_GENERATE_EMBEDDINGS` resolves:

```sql
CREATE EXTERNAL MODEL OllamaMxbai
WITH (
    LOCATION   = 'https://localhost:8444/v1/embeddings',
    API_FORMAT = 'OpenAI',
    MODEL_TYPE = EMBEDDINGS,
    MODEL      = 'mxbai-embed-large'
);
```

In cloud (Azure SQL Hyperscale), the same DDL points at Azure OpenAI `text-embedding-3-small` with `API_FORMAT = 'Azure OpenAI'`. Application code never changes — the model is a database object.

### 3. Hybrid search: **one statement, two specialized access paths**

[local/sqlscripts/01_schema.sql](local/sqlscripts/01_schema.sql) `usp_HybridSearch` is the centerpiece. One stored procedure call returns ranked incidents *and* runbooks, with the optimizer composing two completely different index paths:

| Side | Index used | Why |
|---|---|---|
| `IncidentArchive` (~150k rows, weakly tagged) | **DiskANN Vector Index Seek** via `VECTOR_SEARCH(... METRIC = 'cosine')` with `TOP (@k) WITH APPROXIMATE` | Approximate nearest neighbor over a large corpus; structured filters (`TenantId`, `errorCode`) run as residual predicates on the bookmark side. |
| `Runbook` (~20 docs / ~6k chunks, well tagged) | **JSON Index Seek** on `Tags ($.service)`, then exact `vector_distance('cosine', ...)` over the chunks | Structured filter narrows the candidate set to a few dozen rows — DiskANN isn't worth it on that size. |

Both halves merge in a single result set ordered by cosine distance. The proc body is in [local/sqlscripts/01_schema.sql](local/sqlscripts/01_schema.sql); the demo invocation is [local/sqlscripts/06_hybrid_search.sql](local/sqlscripts/06_hybrid_search.sql).

```sql
-- DiskANN side
SELECT TOP (@k) WITH APPROXIMATE ...
FROM   VECTOR_SEARCH(
         TABLE = dbo.IncidentArchive AS a,
         COLUMN = Embedding,
         SIMILAR_TO = @qvec,
         METRIC = 'cosine') AS r
WHERE  a.TenantId = @lTenantId
   AND JSON_VALUE(a.Tags, '$.errorCode') = @lErrorCode;

-- JSON Index Seek + exact distance side
SELECT TOP (@k) ..., vector_distance('cosine', rc.Embedding, @qvec) AS distance
FROM   dbo.Runbook      rb
JOIN   dbo.RunbookChunk rc ON rc.RunbookId = rb.RunbookId
WHERE  JSON_VALUE(rb.Tags, '$.service') = @lService
ORDER  BY distance;
```

### 4. `CREATE JSON INDEX` + `CREATE VECTOR INDEX` side by side

[local/sqlscripts/01_schema.sql](local/sqlscripts/01_schema.sql) and [local/sqlscripts/03_vector_indexes.sql](local/sqlscripts/03_vector_indexes.sql):

```sql
CREATE JSON INDEX ix_runbook_tags
    ON dbo.Runbook (Tags)
    FOR ('$.service', '$.tags');

CREATE VECTOR INDEX vec_archive_embedding
    ON dbo.IncidentArchive (Embedding)
    WITH (METRIC = 'cosine');
```

Two brand-new index types, both first-class in T-SQL DDL, both used in the same proc.

### 5. `sp_invoke_external_rest_endpoint` calls the chat model from T-SQL

`MODEL_TYPE = EMBEDDINGS` is the only value `CREATE EXTERNAL MODEL` accepts today, so chat completions go through `sp_invoke_external_rest_endpoint` — and the demo does the entire RAG flow from inside [local/sqlscripts/04a_proc_generate_mitigation.sql](local/sqlscripts/04a_proc_generate_mitigation.sql):

```sql
DECLARE @body nvarchar(max) = (
    SELECT  @ChatModel                          AS [model],
            0.2                                 AS [temperature],
            JSON_OBJECT('type': 'json_object')  AS [response_format],
            JSON_ARRAY(
                JSON_OBJECT('role': 'system', 'content': @system),
                JSON_OBJECT('role': 'user',   'content': @user))   AS [messages]
    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

EXEC @ret = sp_invoke_external_rest_endpoint
    @url = @ChatUrl, @method = 'POST', @headers = @headers,
    @payload = @body, @timeout = 180, @response = @response OUTPUT;

-- Parse and persist into a json column.
DECLARE @assistant nvarchar(max) =
    JSON_VALUE(@response, '$.result.choices[0].message.content');
IF ISJSON(@assistant) = 0 RAISERROR('...');

UPDATE dbo.Incident
   SET ProposedMitigation = CAST(@assistant AS json),
       Status             = N'mitigating'
 WHERE IncidentId = @IncidentId;
```

`JSON_OBJECT` / `JSON_ARRAY` build the OpenAI-shaped request body without any string concatenation; `JSON_VALUE` extracts the assistant's response; `ISJSON` guards against malformed JSON; the result lands in a typed `json` column — the entire RAG round trip runs in one stored procedure.

### 6. Append-only ledger as the audit trail

`dbo.AppLog` is declared `WITH (LEDGER = ON (APPEND_ONLY = ON))` in [local/sqlscripts/01_schema.sql](local/sqlscripts/01_schema.sql). Every time the agent writes a mitigation, [local/sqlscripts/04a_proc_generate_mitigation.sql](local/sqlscripts/04a_proc_generate_mitigation.sql) appends a row — cryptographically chained, impossible to update or backdate. Beat 3 closes the loop by `SELECT`ing the agent's action straight out of the ledger.

### 7. Azure SQL cloud defaults, applied to the box engine

[local/sqlscripts/00_setup.sql](local/sqlscripts/00_setup.sql) flips on the modern engine defaults so the local container behaves like Azure SQL Database:

```sql
ALTER DATABASE zavalivesitedb SET ACCELERATED_DATABASE_RECOVERY = ON;
ALTER DATABASE zavalivesitedb SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE;
ALTER DATABASE zavalivesitedb SET OPTIMIZED_LOCKING = ON;     -- requires ADR + RCSI
ALTER DATABASE SCOPED CONFIGURATION SET PREVIEW_FEATURES = ON; -- VECTOR_SEARCH / CREATE VECTOR INDEX
```

ADR → RCSI → Optimized Locking in that order (OL has the other two as prerequisites). Optimized Locking is what keeps the Beat 1 five-feature `INSERT` from blocking the page's 2-second poller against a multi-thousand-row corpus.

### 8. Diagnostic procs designed for MCP

Three procs in [local/sqlscripts/04b_diagnostic_procs.sql](local/sqlscripts/04b_diagnostic_procs.sql) — `usp_DxIndexExists`, `usp_DxResourcePressure`, `usp_DxDeadlockRecent` — each returns **one row** whose first column is `finding` (kebab-case verdict: `index_present`, `index_missing`, `pressure_high`, `no_deadlock_history`, …) plus evidence columns from DMVs (`sys.indexes`, `sys.dm_os_wait_stats`, the system deadlock XEvent ring buffer). That shape is what makes them usable as MCP tools — DAB exposes them as `dx_index_exists` / `dx_resource_pressure` / `dx_deadlock_recent`, and the agent reads `finding` to branch its plan.

### Cheat sheet — which feature lights up on which beat

| Beat | Headline T-SQL features | Script |
|---|---|---|
| **1** Incident lands | `json`, `JSON_VALUE`, `REGEXP_MATCHES`, `FOR JSON PATH`, `AI_GENERATE_EMBEDDINGS`, `vector(1024)` | [05_create_incident.sql](local/sqlscripts/05_create_incident.sql) |
| **2** Hybrid search | `VECTOR_SEARCH` + DiskANN, `vector_distance`, `CREATE JSON INDEX`, JSON Index Seek, `CREATE EXTERNAL MODEL` | [01_schema.sql `usp_HybridSearch`](local/sqlscripts/01_schema.sql), [03_vector_indexes.sql](local/sqlscripts/03_vector_indexes.sql), [06_hybrid_search.sql](local/sqlscripts/06_hybrid_search.sql) |
| **3** Timeline | `LEDGER = ON (APPEND_ONLY = ON)`, `sys.database_ledger_*` | [01_schema.sql `AppLog`](local/sqlscripts/01_schema.sql), [07_log_timeline.sql](local/sqlscripts/07_log_timeline.sql) |
| **4** Agent triages + mitigates | `sp_invoke_external_rest_endpoint`, `JSON_OBJECT`, `JSON_ARRAY`, `ISJSON`, writeback to `json`, `sys.dm_*` DMVs in `usp_Dx*` | [04a_proc_generate_mitigation.sql](local/sqlscripts/04a_proc_generate_mitigation.sql), [04b_diagnostic_procs.sql](local/sqlscripts/04b_diagnostic_procs.sql) |

---

## What's in here

### `local/`

Scripts are PowerShell unless noted. Run them from `src/sql/local/`.

| Purpose | Scripts |
|---|---|
| **Bootstrap (run once)** | [`Build.ps1`](local/Build.ps1) — one-shot 13-step setup: build the SQL+AI container image, start it, deploy schema/corpus/embeddings, build the .NET solution. [`Verify-Build.ps1`](local/Verify-Build.ps1) — post-build smoke checks. |
| **Demo lifecycle** | [`Start-LiveSite.ps1`](local/Start-LiveSite.ps1) / [`Stop-LiveSite.ps1`](local/Stop-LiveSite.ps1) — start/stop the Aspire AppHost (Blazor WASM + DAB). [`Open-LiveSite.ps1`](local/Open-LiveSite.ps1) — open the browser to the running page. [`Prep-Demo.ps1`](local/Prep-Demo.ps1) — pre-stage everything immediately before going on stage. |
| **On-stage actions** | [`Insert-Incident.ps1`](local/Insert-Incident.ps1) — Beat 1: fire the five-feature INSERT that creates incident 5012. [`Generate-Mitigation.ps1`](local/Generate-Mitigation.ps1) — Beat 4 fallback if you want to run mitigation from the shell instead of from the agent. |
| **Reset between rehearsals** | [`Reset-ForBeat2.ps1`](local/Reset-ForBeat2.ps1) — rewind to the "just after incident landed" state. [`Reset-Incident.ps1`](local/Reset-Incident.ps1) — wipe 5012 and re-seed. [`Teardown-LiveSite.ps1`](local/Teardown-LiveSite.ps1) — remove the container entirely. |
| **Container internals** | [`Start-AzureSqlContainer.ps1`](local/Start-AzureSqlContainer.ps1) — bring up the SQL container (called by `Build.ps1`; runnable on its own). [`Prepare-AiContainer.ps1`](local/Prepare-AiContainer.ps1) — install Ollama + Caddy and pull the embedding/chat models inside the container. [`Restart-AiServices.ps1`](local/Restart-AiServices.ps1) / [`Warmup-Ai.ps1`](local/Warmup-Ai.ps1) — kick the AI side awake before a run. |
| **Diagnostics** | [`Test-AzureSqlConnection.ps1`](local/Test-AzureSqlConnection.ps1) — round-trip a query through the bundled `sqlsim` client. [`Test-AgentPath.ps1`](local/Test-AgentPath.ps1) — verify the MCP/DAB endpoint the agent hits. [`Test-DomainAllowlist.sql`](local/Test-DomainAllowlist.sql) — confirm `sp_invoke_external_rest_endpoint` will accept the Ollama URL. [`List-CopilotModels.ps1`](local/List-CopilotModels.ps1) — list the chat models VS Code Copilot has available. |
| **Shared helpers** | [`Common.ps1`](local/Common.ps1) — dot-sourced by other scripts. Owns `Get-Sqlsim` (sqlsim path resolution) and `Invoke-SqlsimScript` (consistent script execution). |
| **T-SQL deploy order** | [`sqlscripts/`](local/sqlscripts/) — numbered 00→07 in execution order. `00_setup` (DB-level options) → `01_schema` (tables, external model, ledger, `usp_HybridSearch`) → `02*_seed*` (incident + runbook corpus) → `03_vector_indexes` + `03b_runbook_chunks` → `04a_proc_generate_mitigation` + `04b_diagnostic_procs` → `05_create_incident` (Beat 1) → `06_hybrid_search` (Beat 2) → `07_log_timeline` (Beat 3). Files with a leading underscore (`_bootstrap_login`, `_reset_for_beat2`) are interactive/out-of-band helpers called from PowerShell, not part of the linear deploy. |
| **.NET solution** | [`dotnet/`](local/dotnet/) — `AppHost/` is the Aspire orchestrator (Blazor WASM on :8080, DAB on :8765), `Web/` is the Blazor page. |
| **Other** | [`utilities/`](local/utilities/) — bundled `sqlsim.exe` (preferred SQL client; sets the right `SET` options automatically and handles `:setvar` substitution, so the deploy scripts run identically to how they would in SSMS). **🆕 First look** — `sqlsim` is a new Microsoft client coming soon publicly; this repo includes a copy so the demo works today. [`web/`](local/web/) — static assets served by the page. |

### `azure/`

| Purpose | Files |
|---|---|
| **Data tier (Beats 1–4 minimum)** | [`Prep-Cloud.ps1`](azure/Prep-Cloud.ps1) — deploy Hyperscale + Azure OpenAI + APIM via [`bicep/main.bicep`](azure/bicep/main.bicep), then apply [`sqlscripts/`](azure/sqlscripts/) (cloud variant of the local deploy — Azure OpenAI as the external model, APIM as the proxy). Parameters live in [`bicep/params.json`](azure/bicep/params.json). |
| **App tier (optional)** | [`Prep-Cloud-Hosting.ps1`](azure/Prep-Cloud-Hosting.ps1) — adds Container Apps hosting for the Blazor + DAB layer via [`bicep/hosting.bicep`](azure/bicep/hosting.bicep). [`README-HOSTING.md`](azure/README-HOSTING.md) — what this layer does and why it's separate. [`hosting/`](azure/hosting/) — DAB Dockerfile, cloud DAB config, MCP server descriptor, and SQL grant for the managed identity. |
| **APIM policy** | [`apim-policies/aoai-api.xml`](azure/apim-policies/aoai-api.xml) — the inbound policy that fronts Azure OpenAI (auth, rate limit, model routing). |
| **Reset / teardown** | [`Reset-Stack.ps1`](azure/Reset-Stack.ps1) — rewind cloud state for another rehearsal. [`Cleanup-Cloud.ps1`](azure/Cleanup-Cloud.ps1) — delete data-tier resources. [`Teardown-Cloud-Hosting.ps1`](azure/Teardown-Cloud-Hosting.ps1) — delete app-tier resources. |

The custom Copilot Chat agent (`live-site-sql`) lives in `../.github/agents/` and `../.github/skills/` at the repo root — see [The `live-site-sql` agent](#the-live-site-sql-agent) below for how VS Code discovers and wires it up.

---

## Sneak peek: the new Azure SQL container

> 🆕 **Coming soon — a publicly distributable Azure SQL container.** This demo
> is one of the first end-to-end samples authored against it. The image
> brings the **Azure SQL engine** (not SQL Server) to your laptop —
> Hyperscale-style storage, the modern AI surface (`vector`, DiskANN,
> `AI_GENERATE_EMBEDDINGS`, `CREATE EXTERNAL MODEL`, `sp_invoke_external_rest_endpoint`),
> JSON type + JSON indexes, append-only ledger, and the Azure SQL
> defaults (ADR, RCSI, Optimized Locking) all in a single `docker run`.
> Watch [aka.ms/azure-sql-container](https://aka.ms/azure-sql-container)
> for the public registry path.

## Important: about the SQL container used by this demo

The local demo was authored against an **Azure SQL preview container**
(*"first look"*) that, at the time this source ships, **is not yet
publicly available**. When the public image lands, the path at
[aka.ms/azure-sql-container](https://aka.ms/azure-sql-container) will
be the one to use.

Because of that, the `Start-AzureSqlContainer.ps1` script in this repo
points at an image you almost certainly cannot pull yet. You have two
practical options:

1. **Wait for the public Azure SQL container** and update the image
   reference in `Start-AzureSqlContainer.ps1` to the new public path
   when announced.
2. **Run the demo against the public SQL Server 2025 container today**
   (see the next section). Most of the demo lights up there — SQL Server
   2025 ships the same `vector`, JSON, `REGEXP_*`, `AI_GENERATE_EMBEDDINGS`,
   and `CREATE EXTERNAL MODEL` surface that Beats 1–4 rely on.

---

## Running this against the SQL Server 2025 container (for developers)

The shipped scripts target Azure SQL, but the T-SQL surface used in
steps 1–4 is shared with SQL Server 2025 GA, so a developer can swap
the image with minimal local edits. The notes below are pointers,
not ready-to-run code.

### What stays the same on SQL Server 2025

These features are available in both Azure SQL preview and SQL Server 2025:

| Feature | Used in |
|---|---|
| `json` data type | `01_schema.sql`, `02_seed_corpus.sql` |
| `REGEXP_MATCHES` / `REGEXP_LIKE` | `05_create_incident.sql` |
| `vector(N)` data type + cosine search | `01_schema.sql`, `06_hybrid_search.sql` |
| `AI_GENERATE_EMBEDDINGS ... USE MODEL` | `02_seed_corpus.sql` |
| `CREATE EXTERNAL MODEL ... MODEL_TYPE = EMBEDDINGS` | `00_setup.sql` |
| `sp_invoke_external_rest_endpoint` (chat) | `04a_proc_generate_mitigation.sql` |
| `CREATE JSON INDEX` | hybrid search tuning |
| `DiskANN` vector index | hybrid search tuning |
| Ledger tables (`AppLog`) | incident timeline |

### What a developer would change to use the SQL Server 2025 container

> Treat this as a recipe sketch. Do **not** apply these changes to the
> shipped scripts unless you are running locally against SQL Server 2025.

1. **Image in [local/Start-AzureSqlContainer.ps1](local/Start-AzureSqlContainer.ps1):**
   replace the default `$Image` value with the public SQL Server 2025
   image, e.g.:

   ```powershell
   [string]$Image = 'mcr.microsoft.com/mssql/server:2025-latest'
   ```

2. **Skip the ACR login.** `Start-AzureSqlContainer.ps1` does an
   `az acr login` to pull the Azure SQL preview image. The public MCR
   image needs no auth — comment out the ACR login block and let
   `docker pull` go straight to MCR.

3. **Container env vars.** Both containers accept the same
   `MSSQL_SA_PASSWORD` / `ACCEPT_EULA` / `MSSQL_PID=Developer` variables.
   No change needed.

4. **External REST endpoint allowlist.** Both engines require URLs called
   from `sp_invoke_external_rest_endpoint` to be allow-listed via
   `sp_invoke_external_rest_endpoint_allowlist`. The demo's allowlist
   setup is in `00_setup.sql` — keep it as-is.

5. **`EXTERNAL MODEL` enum sanity.**
   - `MODEL_TYPE = EMBEDDINGS` — the only valid value on both engines.
     There is no `CHAT_COMPLETIONS` model type; chat goes through
     `sp_invoke_external_rest_endpoint`.
   - `API_FORMAT` accepts `Ollama` (local), `Azure OpenAI`, `OpenAI`,
     `ONNX Runtime`. The demo uses `Ollama` locally and `Azure OpenAI`
     in cloud.

6. **`sqlcmd` SET options.** If you replace `sqlsim` with `sqlcmd` for
   any of the deploy scripts, prepend the standard preamble so JSON
   indexes don't fail Msg 1934:

   ```sql
   SET QUOTED_IDENTIFIER ON;
   SET ANSI_NULLS ON;
   SET ARITHABORT ON;
   SET CONCAT_NULL_YIELDS_NULL ON;
   SET ANSI_PADDING ON;
   SET ANSI_WARNINGS ON;
   SET NUMERIC_ROUNDABORT OFF;
   ```

   `sqlsim` (used by [Build.ps1](local/Build.ps1)) sets these
   automatically via `Common.ps1::Invoke-SqlsimScript`.

7. **What likely will NOT work as-is on SQL 2025:** any feature still
   exclusive to the Azure SQL preview build at the time of the talk.
   Beats 1–4 of the demo do not depend on any such feature today.

---

## Prerequisites

- Windows 11 + PowerShell 7.x
- Docker Desktop (`winget install Docker.DockerDesktop`)
- .NET 10 SDK
- Node.js LTS (for the Static Web App / SWA CLI in the cloud path)
- Azure CLI, logged in (`az login`) — only needed if you are pulling a
  preview Azure SQL image from a private registry; not needed for the
  public SQL Server 2025 path
- (Optional) GitHub Copilot CLI for the agent beat

---

## Quick start — local

```powershell
cd src/sql/local

# Tell Build.ps1 which SQL image to use. Required — no default.
# Public path:
$env:BRK223_SQL_IMAGE = 'mcr.microsoft.com/mssql/server:2025-latest'
# (Microsoft-internal Azure SQL preview path goes here instead, if you have access.)

.\Build.ps1
# Cold run: ~12-15 min (image pull + Ollama model pull + corpus embed + dotnet build)
# Warm run: ~30 sec (everything probed and skipped)

.\Verify-Build.ps1     # health check — green = ready
.\Start-LiveSite.ps1   # Aspire AppHost: DAB on :8765/mcp + Blazor WASM on :8080
.\Open-LiveSite.ps1    # opens http://localhost:8080 in the default browser
```

You should see the **empty-state** Zava On-Call Console (no SEV1 banner,
dashes in every slot). Then create incident #5012 and watch the page
fill in:

```powershell
.\Insert-Incident.ps1  # the five-feature INSERT (Beat 1). Page lights up within 2 sec.
```

Then drive the agent (Beat 4). In VS Code:

1. Open Copilot Chat (`Ctrl+Alt+I`), **start a NEW chat** (`+` icon).
2. Command Palette → *MCP: List Servers* — confirm `zavalivesite-sql` is **Started**.
3. Pick the **live-site-sql** agent from the agent dropdown.
4. Type: `Mitigate incident 5012 @live-site-sql`

The agent runs `read_records → hybrid_search → dx_index_exists →
dx_resource_pressure → dx_deadlock_recent → generate_mitigation`
(~110-120 s on phi4-mini), then the page's AI mitigation panel populates
on the next 2-second poll.

To tear down:

```powershell
.\Stop-LiveSite.ps1    # stops AppHost + DCP-managed DAB. Leaves the SQL container running.
```

Useful Build.ps1 switches:

| Switch | Effect |
|---|---|
| `-Force` | Drop & recreate container + reseed corpus + rebuild dotnet |
| `-SkipWinget` | Skip dev-tooling install (Docker / Node / dotnet / az) |
| `-SkipAi` | Skip Ollama + Caddy install in the container |
| `-SkipDeploy` | Skip `deploy-prestage.ps1` |
| `-SkipDotnet` | Skip `dotnet restore + build` |
| `-Fast` | Implies `-SkipWinget -SkipAi -SkipDotnet` for a warm laptop |

> **Embedding seed retry.** Build.ps1 step 12 retries `deploy-prestage.ps1`
> up to 3 times. `AI_GENERATE_EMBEDDINGS` in the 500-row seed loop has no
> per-row catch, so a single transient Ollama hiccup can abort the batch
> — the retry wrapper re-runs the (idempotent) prestage deploy to recover.

---

## Quick start — cloud (Azure)

```powershell
cd presentations/build2026/BRK223/sql/azure
.\Prep-Cloud-Hosting.ps1 -NameSuffix <yoursuffix>
```

This deploys:

- Azure SQL logical server + Hyperscale Premium database
- Azure Container Registry + Container Apps Environment + DAB Container App
- Azure Static Web App (Blazor WASM frontend)
- Azure OpenAI deployments (`text-embedding-3-small`, chat model)
- API Management front door
- Managed identity + RBAC + Key Vault references

See [azure/README.md](azure/README.md) and
[azure/README-HOSTING.md](azure/README-HOSTING.md) for details.

---

## The `live-site-sql` agent

This repo ships a **custom VS Code agent** so the incident-triage flow
is reproducible, not a freeform chat. There are two files that make it
work, both under `BRK223/.github/`:

| File | What it is | What it does |
|---|---|---|
| [`.github/agents/live-site-sql.agent.md`](../.github/agents/live-site-sql.agent.md) | A **custom agent** definition (VS Code feature) | YAML frontmatter (`description`, `tools: [zavalivesite-sql/*]`) plus a system-prompt body. When you open `BRK223/` in VS Code, Copilot Chat auto-discovers this file and adds **live-site-sql** to the agent dropdown. Selecting it pins the agent's tool set to the `zavalivesite-sql` MCP server and applies the body as the system prompt. |
| [`.github/skills/live-site-sql/SKILL.md`](../.github/skills/live-site-sql/SKILL.md) | A **skill** (VS Code feature — [open `agentskills.io` spec](https://agentskills.io/specification)) | Required frontmatter (`name`, `description`) plus the 7-step triage protocol, the diagnostic-tool catalog (`dx_index_exists`, `dx_resource_pressure`, `dx_deadlock_recent`), and the JSON output contract. VS Code discovers all `.github/skills/*/SKILL.md` files globally and advertises each one's `description` to the model in ~100 tokens. The model then *chooses* to load the body via a `load_skill` tool call when the user's prompt matches. **There is no `skills:` field in `.agent.md`** — agents and skills are discovered independently; the agent's system prompt biases the model toward picking the right skill. |

**How they cooperate at runtime:**

1. VS Code opens the `BRK223/` workspace and discovers `.github/agents/` and
   `.github/skills/` **independently**. Every skill is available to every
   agent — there is no declarative binding between them.
2. The user selects **live-site-sql** from the Copilot Chat agent
   dropdown — no `@file` attach, no copy-paste prompt.
3. The agent body is now the system prompt: *"diagnose Azure SQL incidents
   using live-site tooling — run the six-tool MCP protocol."* That wording
   is deliberate — it overlaps with the live-site-sql skill's `description`,
   priming the model to call `load_skill("live-site-sql")` on turn 1.
4. When the user types **"Mitigate incident 5012"**, the model reads
   (a) the system prompt from `.agent.md`, (b) the ~100-token skill
   advertisement, (c) the user prompt — and decides to fire `load_skill`
   *itself*. VS Code returns the protocol body as the tool result. **The
   model picked the skill; the agent file only biased the decision.**
5. The SKILL now provides the *protocol* (steps + tool order + output
   contract). The agent body provides the *role* (when to invoke, what NOT
   to do, deployment timing expectations). The `tools:` array in
   `.agent.md` pins which MCP tools are in scope — that part *is*
   declarative.
6. Every diagnostic call (`read_records`, `hybrid_search`, `dx_*`,
   `generate_mitigation`) is routed through the `zavalivesite-sql` MCP
   server, which is fronted by DAB → SQL.

**Why this matters:** the agent is deployment-agnostic. The *same*
`live-site-sql` agent works against the local Ollama deployment
(80–120 s per mitigation) and the cloud AOAI deployment (15–20 s).
Switching deployments only changes which MCP server endpoint DAB points
at, not which agent the user selects.

### How `SKILL.md` actually works at runtime (progressive disclosure)

This is what makes the SKILL story more than "another markdown file." The
**agent host parses `SKILL.md`, not the model.** The model only ever sees
what the host chooses to inject. Sequence per turn:

1. **At startup** the host (VS Code Copilot Chat today; `AgentSkillsProvider`
   in MAF tomorrow) scans `.github/skills/*/SKILL.md`, parses YAML
   frontmatter only, and injects a **~100-token advertisement** into the
   system prompt: *"Available skills: live-site-sql — Diagnoses Azure SQL
   incidents using live-site tooling. Load with `load_skill('live-site-sql')`."*
   The 7-step protocol body stays on disk.
2. **At startup** the host also exposes three synthetic tools to the model:
   `load_skill(name)`, `read_skill_resource(skill, path)`, and
   `run_skill_script(skill, path, args)`.
3. **The user prompt arrives** ("Mitigate incident 5012"). The model sees the
   system prompt + the ~100-token skill ad + the MCP tools + the three
   skill tools. **It has not seen the body yet.**
4. **The model decides the skill is relevant** and issues a tool call:
   `load_skill("live-site-sql")`. The host catches this call (it never
   reaches an external service), reads the full body off disk, and returns
   it as the tool result. *Now* the 7-step protocol enters context — once,
   only when needed.
5. **The model executes the protocol** — `read_records` → `hybrid_search`
   → `dx_index_exists` → `dx_resource_pressure` → `dx_deadlock_recent`
   → `generate_mitigation` — each call going out through MCP to DAB to SQL.

Net effect on context-window economics:

| Strategy | Tokens in context per turn |
|---|---|
| Hardcoded protocol in system prompt | ~600, always — even for unrelated questions |
| `SKILL.md`, never loaded this turn | ~100 (just the ad) |
| `SKILL.md`, loaded this turn | ~100 + ~600, this turn only |
| 10 skills registered, 1 loaded this turn | ~1000 (ads) + ~600 (this skill body) = ~1600, this turn only |

A hand-rolled "stuff every protocol into the system prompt" approach for 10
protocols pays the full token cost on **every** call. With SKILL.md it's the
difference between a small local model like `phi4-mini` being viable at the
edge versus needing a 128k-context cloud model just to hold your own prompts.

The parser is unglamorous: standard YAML frontmatter parse + `File.ReadAllText`
on the body when `load_skill` is called. The cleverness is in *the protocol*
— the three synthetic tools and the progressive-disclosure pattern — not in
the parsing. About 200 lines of host code, and the same byte-for-byte
`SKILL.md` runs under VS Code today and `AgentSkillsProvider` in MAF tomorrow.

### The honest tradeoff: composability vs. determinism

Progressive disclosure has one design cost that's worth naming explicitly:
**the model decides whether to call `load_skill`, based on description-vs-prompt
keyword overlap.** That's a probabilistic selection, not a declarative
binding. Two real failure modes follow:

1. **Skill not loaded when it should be** \u2014 the user's phrasing drifts from
   the skill description and the model answers freeform, silently skipping
   the protocol.
2. **Wrong skill loaded** \u2014 two skills have overlapping descriptions and
   the model picks the less-relevant one.

The framework chose composability (one skill registry; any agent can use
any skill; the model arbitrates) over determinism (one agent hard-bound
to one skill). For a workspace of 50 skills this is the only thing that
scales; for a single high-stakes always-on protocol like ours it's the
wrong end of the curve.

Three escape hatches, in order of strength:

| Mechanism | Determinism | Where it lives |
|---|---|---|
| **`@skill-name` mention** in the user prompt | Fully deterministic \u2014 user forces it | VS Code Copilot Chat (today) |
| **System-prompt biasing** via the agent body | Strong but soft | `.agent.md` body \u2014 our current approach |
| **Force-load the skill body into `Instructions=`** at agent construction | Fully deterministic, pays ~600 tokens always | MAF only (`ChatClientAgentOptions.Instructions`) \u2014 not available in VS Code |

The agent body in this repo is engineered so the model picks
`live-site-sql` on its own from a prompt like *"mitigate incident 5012"*.
The `@skill-name` mention is available as a forcing function if you ever
need it.

In the MAF production migration the right answer is option 3:
**force-load the always-on skill into `Instructions=`** and only use
progressive disclosure for *optional* skills that are relevant a small
fraction of the time. You eat the token cost where determinism matters
and save tokens where it doesn't.

> If VS Code doesn't show **live-site-sql** in the agent dropdown, either
> open the `BRK223/` folder directly as the workspace, or enable
> `chat.useCustomizationsInParentRepositories` so VS Code looks up the tree
> from a parent workspace.

---

## Walkthrough

The complete keyboard-level walkthrough lives in **[demo.md](demo.md)** —
every SQL statement, file to open, MSSQL extension click, and agent prompt
is there.

Quick recap of what the five steps prove:

1. Create incident data in SQL (JSON payload + regex-derived tags + embedding).
2. Run hybrid retrieval against incident archive and runbooks — slow plan, then a JSON-index-tuned plan ~20× faster.
3. Persist immutable incident timeline entries (ledger).
4. Drive mitigation generation through the `live-site-sql` agent → MCP → DAB → SQL stored procs (including `sp_invoke_external_rest_endpoint` to the LLM).
5. Re-run the same page against cloud data/services (Hyperscale + Azure OpenAI) by swapping the DAB endpoint — no code change.

Agent triage protocol that drives step 4:
[../.github/skills/live-site-sql/SKILL.md](../.github/skills/live-site-sql/SKILL.md).

---

## Architecture

```
   Browser  ─REST─►  ┐
                     ├─►  DAB  ─►  SQL (preview / 2025)  ◄─►  Ollama / Caddy
   Copilot  ─MCP──►  ┘            (vector + JSON              (in container)
                                   + ledger + AI)
```

| Layer | Local | Cloud |
|---|---|---|
| Frontend | Blazor WASM via Aspire AppHost | Azure Static Web Apps |
| API | DAB container | DAB on Container Apps |
| Database | Azure SQL preview container *(or SQL Server 2025)* | Azure SQL Hyperscale |
| Embedding | `mxbai-embed-large` (Ollama) | `text-embedding-3-small` (AOAI) |
| Chat | `phi4-mini` (Ollama) | chat model via Azure OpenAI |

---

## Troubleshooting

- **`docker pull` denied / "unauthorized"** — you're trying to pull a
  private preview image. Change the image reference in
  `Start-AzureSqlContainer.ps1` to a SQL image you can actually pull
  (e.g. `mcr.microsoft.com/mssql/server:2025-latest`).
- **`HRESULT: 0x80070008` from `sp_invoke_external_rest_endpoint`** —
  the URL pre-validator rejected the call before it left SQL. Usually
  means the host isn't in `sp_invoke_external_rest_endpoint_allowlist`.
  See [local/Test-DomainAllowlist.sql](local/Test-DomainAllowlist.sql).
- **`HRESULT: 0x80072efd` from `AI_GENERATE_EMBEDDINGS`** — Ollama isn't
  reachable from inside the container. Run
  `.\Restart-AiServices.ps1` then re-run `Build.ps1`.
- **`Msg 1934` ("the SET options are incorrect")** on `CREATE JSON INDEX`
  via `sqlcmd` — set `QUOTED_IDENTIFIER ON` / `ANSI_NULLS ON` /
  `ARITHABORT ON` at the top of the script. `sqlsim` already does this.
- **Seed aborts mid-loop** — handled by the retry wrapper in
  [Build.ps1](local/Build.ps1) step 12 (3 attempts). If it fails 3
  times, verify Ollama is healthy:
  `docker exec <container> curl -s http://127.0.0.1:11434/api/tags`.

---

## Productionizing — replace VS Code with Microsoft Agent Framework

> **Only the agent host swaps.** `SKILL.md`, the DAB MCP server, and every
> SQL capability behind it (stored procs, hybrid search, JSON index, vector
> index, ledger, `sp_invoke_external_rest_endpoint` to the LLM) carry over
> byte-for-byte. The migration is *deleting one box*, not rewriting the demo.

In this repo, **VS Code Copilot Chat is the agent host**. That's fine for
development, but not how you ship to on-call engineers. The good news:
the migration is mostly *deleting the VS Code dependency*, not rewriting
the app. Almost every artifact under this repo is reusable as-is by a
real app built on **[Microsoft Agent Framework (MAF)](https://learn.microsoft.com/agent-framework/)**.

### What VS Code is doing today, and what replaces it

| Concern | VS Code (today) | Production app (MAF) |
|---|---|---|
| LLM call loop (prompt → tool → result → next prompt) | Copilot Chat agent mode | `ChatClientAgent` (C#) |
| Tool catalog | `.vscode/mcp.json` → MCP server | `MCPStreamableHTTPTool` pointed at the same MCP server URL |
| Tool-set restriction | `tools: [zavalivesite-sql/*]` in `.agent.md` frontmatter | `tools=[mcp_client]` in agent constructor |
| Protocol / playbook | `.github/skills/live-site-sql/SKILL.md` | **Same file**, loaded by `SkillsProvider` / `AgentSkillsProvider` |
| System prompt | Body of `.agent.md` | `instructions=` string at agent creation |
| Conversation surface | Copilot Chat panel | Your app's UI (button on incident page, chat pane, etc.) |
| Human in the loop | VS Code user (developer) | On-call engineer + MAF approval middleware |

### The big reuse win: `SKILL.md` is an open spec

The `SKILL.md` format we use isn't a VS Code-only convention — it's the
**open [Agent Skills](https://agentskills.io/) specification**, with
first-class loaders built into Microsoft Agent Framework. Our
[`.github/skills/live-site-sql/SKILL.md`](../.github/skills/live-site-sql/SKILL.md)
is portable byte-for-byte: drop the directory under a `skills/` path in
your MAF app and the framework discovers it automatically.

MAF uses **progressive disclosure** so the full protocol doesn't sit in
context on every turn:

1. **Advertise** (~100 tokens): only `name` + `description` from the
   frontmatter are injected into the system prompt.
2. **Load** (on demand): when the agent decides the task matches the
   skill, it calls a built-in `load_skill` tool to pull the full body
   (<5 000 tokens recommended).
3. **Read resources** / **run scripts** (on demand): if the skill
   directory has `references/`, `assets/`, or `scripts/` subfolders,
   MAF exposes `read_skill_resource` and `run_skill_script` tools.

That's why our SKILL's `description:` is written with keyword density —
it's the discovery surface the agent uses to decide whether to load the
protocol.

### What MAF code actually looks like

In C# — `AgentSkillsProvider(skillsRoot)` registered via
`UseAIContextProviders(skills)` on the `IChatClient` builder, then a
`ChatClientAgent` with `Instructions =` set to the body of `.agent.md`
and `ChatOptions.Tools` populated from the MCP client. Full sample
further down in *Replacing `.agent.md` in production*. See the
[MAF Agent Skills docs](https://learn.microsoft.com/agent-framework/agents/skills)
for the exhaustive reference.

### What carries over unchanged

- **`SKILL.md`** — open spec, MAF loads it natively.
- **The `zavalivesite-sql` MCP server** — same DAB instance exposing the
  same stored-proc tools (`read_records`, `hybrid_search`, `dx_*`,
  `generate_mitigation`).
- **SQL schema, stored procs, JSON index, vector index, ledger,
  `sp_invoke_external_rest_endpoint` to the LLM** — all unchanged. The
  agent host doesn't see any of it; it just calls MCP tools.
- **EXTERNAL MODEL bindings** for embeddings — unchanged. The
  mitigation-generation LLM call stays *inside* the stored proc, not
  in the agent loop.

### Replacing `.agent.md` in production

**Keep `.agent.md` in development** — it's what makes the agent show up
in the VS Code Copilot Chat agent dropdown, which is the chat surface
for iterating on the prompt and the skill.

For a real customer-facing app (a website, on-call console, Teams bot —
anything where VS Code is *not* the UI) `.agent.md` has no runtime role.
It is a **VS Code Copilot dev-surface artifact**, not a cross-product
agent definition. There is no `ChatAgent.from_agent_md(...)` in MAF, and
there isn't going to be one — the cross-product agent-definition format
Microsoft is standardizing on is **[AgentSchema / `agent.yaml`](https://microsoft.github.io/AgentSchema/)**
(YAML, used by Foundry, Copilot Studio, and `azd ai agent init`), not
markdown-with-frontmatter.

Three honest patterns for what replaces `.agent.md` when you ship:

| Pattern | What you do | When to pick it |
|---|---|---|
| **Inline the prompt** | Paste the body of `.agent.md` into a C# string literal passed as `Instructions =`. Delete the file from the production deployment. | Simple app, one agent, prompt rarely changes. Lowest friction. |
| **Load `.agent.md` at startup** | Keep the file. ~10 lines of glue: parse YAML frontmatter, use the body as `instructions=`. Same file VS Code reads in dev, same file MAF reads in prod. | You want one source of truth for the system prompt so dev iteration in VS Code and production behavior stay in sync. |
| **Adopt `agent.yaml`** | Replace `.agent.md` with an [AgentSchema](https://microsoft.github.io/AgentSchema/) `agent.yaml`. Wire it with `azd ai agent init` for Foundry deploys, or load it from MAF code. | You want the agent definition to be portable across Foundry, Copilot Studio, and `azd` — not just MAF. The cross-product story. |

The quickest path for our codebase is **load `.agent.md` at startup**:

```csharp
using System.Text.RegularExpressions;
using Azure.AI.OpenAI;
using Azure.Identity;
using Microsoft.Agents.AI;
using Microsoft.Extensions.AI;
using ModelContextProtocol.Client;
using YamlDotNet.Serialization;

// 1. Parse .agent.md once at startup.
record AgentMd(string Name, string Description, string[] Tools, string Body);

static AgentMd LoadAgentMd(string path)
{
    var text  = File.ReadAllText(path);
    var match = Regex.Match(text, @"^---\s*\n(.*?)\n---\s*\n(.*)$",
                            RegexOptions.Singleline);
    var meta  = new DeserializerBuilder().Build()
                   .Deserialize<Dictionary<string, object>>(match.Groups[1].Value);
    return new AgentMd(
        Name:        (string)meta["name"],
        Description: (string)meta["description"],
        Tools:       ((List<object>)meta["tools"]).Select(o => o.ToString()!).ToArray(),
        Body:        match.Groups[2].Value.Trim());
}

var md = LoadAgentMd(".github/agents/live-site-sql.agent.md");

// 2. Bind the same MCP server VS Code talks to.
await using var mcp = await McpClient.CreateAsync(
    new SseClientTransport(new() { Endpoint = new Uri("http://dab.internal/mcp") }));
var mcpTools = await mcp.ListToolsAsync();

// 3. Build a chat client that loads SKILL.md via context providers.
var skills = new AgentSkillsProvider(skillsRoot: ".github/skills");

IChatClient chatClient = new AzureOpenAIClient(
        new Uri("https://<your-aoai>.openai.azure.com"), new DefaultAzureCredential())
    .GetChatClient("gpt-4o-mini")
    .AsIChatClient()
    .AsBuilder()
    .UseAIContextProviders(skills)
    .Build();

// 4. Wire everything into one ChatClientAgent.
var agent = new ChatClientAgent(chatClient, new ChatClientAgentOptions
{
    Name        = md.Name,           // "live-site-sql"
    Description = md.Description,
    Instructions = md.Body,          // body of .agent.md, verbatim
    ChatOptions  = new() { Tools = [.. mcpTools] },
});
```

Net effect: VS Code reads `.agent.md` directly, MAF reads the same file
via ~15 lines of glue. Edit the markdown once — both surfaces pick it up.

Note that the `tools:` frontmatter field (`tools: [zavalivesite-sql/*]`)
is a *VS Code wiring directive*, not a portable concept. Your MAF loader
uses it as a sanity check ("confirm the MCP server we're about to bind
matches what the markdown declared") rather than as the binding
mechanism. The actual binding still happens via `ChatOptions.Tools` in
code.

### Where does the MAF process run?

**MAF is a library, not a runtime.** In VS Code, Copilot Chat is the
host — it owns the process, the UI, the loop, the tool invocation. In
production, *you* own all of that. The `ChatClientAgent` is just a class
instance inside a .NET process you start. Where that process runs is
your call.

| Host | What it looks like | When to pick |
|---|---|---|
| **ASP.NET Core Web API** | One endpoint like `POST /diagnose` that takes the incident JSON, calls `agent.RunAsync(...)`, streams the response back. Deploy to Azure App Service or Azure Container Apps. | Customer-facing UI (web page, on-call console, Teams app) calls the agent over HTTP. The 99% case. |
| **Worker Service** | A `BackgroundService` polls a queue / Event Grid / Service Bus for incident events, runs the agent, writes results back. Deploy to AKS or Container Apps. | Event-driven incident response — no UI, the agent reacts to alerts. |
| **Azure Functions** (isolated worker) | HTTP trigger or Service Bus trigger; the function body builds the `ChatClientAgent` once (singleton DI) and calls `RunAsync`. | Bursty traffic, pay-per-call, zero idle cost. Keep the agent in a singleton to amortize cold start. |
| **Console app** | Single-shot CLI. Same code, no host. | Internal dev tools, scheduled jobs (cron / GitHub Actions) — the equivalent of "an engineer at a terminal." |
| **Embedded in an existing service** | The `ChatClientAgent` lives inside your current backend — no new deployable. | You already have a service the on-call console talks to; the agent is just one more method on it. |
| **Foundry Agent Service** | You don't host MAF at all. Define the agent in Foundry, point it at the same MCP server, call it via the Foundry SDK from your app. | You want the agent loop to be a managed dependency. Tradeoff: less control over middleware/observability. |

The architectural picture in one line: **VS Code Copilot Chat is the
host today. In production, the host is whatever .NET process exposes
`agent.RunAsync(...)` to your real chat surface — most commonly an
ASP.NET Core API in a container.** The agent code, the MCP client, the
SKILL loader, the SQL stored procs — all unchanged. Only the outer
shell swaps.

### What else changes

- **The chat surface** — VS Code's panel is replaced by whatever UI
  your app exposes (a button on the incident page, a chat pane in the
  on-call console, a Teams app, etc.).
- **Observability and approvals** — add MAF's OpenTelemetry tracing
  and approval middleware between tool-call and tool-execute so an
  on-call engineer can review the agent's plan before it runs
  `generate_mitigation`.

### Alternative host: Foundry Agent Service

If you don't want to run the MAF runtime yourself, **Foundry Agent
Service** is the managed-agent path. Define the agent in Foundry, point
it at the same MCP server, call it from your app via the Foundry SDK.
Same SKILL, same MCP, same SQL — Foundry just hosts the agent loop.
Pick MAF for code-level control, Foundry Agent Service for a hosted
dependency.

### The takeaway

The agent host is the *only* layer that swaps. The SQL grounding, the
retrieval, the protocol file, the MCP tool plane, and the mitigation
LLM call all carry over. That's the architectural point in one line:
**the durable parts of an AI app live in the data tier and the tool
plane, not in the agent host**.

---

## License & attribution

Source under this folder is part of the public `bwsql` repo and follows
the repo-level license. Embedded model weights are pulled at runtime
from Ollama and remain under their upstream licenses.
