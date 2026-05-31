# BRK223 — Design (Zava ERP Cloud, AI-Grounded Live-Site Response)

> **Working design doc.** Snapshot of locked decisions extracted from
> `../private/AzureSQL_Build2026_Demo_Proposal.md`, plus regex catalog and JSON-index
> spec decided in chat. The proposal stays the narrative source; this file is
> the buildable spec we cite when writing DDL, DAB config, .NET app, and slides.
>
> Last update: 2026-05-03

---

## 1. Scenario

- **Vertical:** Zava ERP Cloud — fictional enterprise multi-tenant ERP SaaS (Workday/Dynamics-class). Mission-critical for F500 tenants, regulated, multi-region.
- **Actor on stage:** Zava's internal SRE / live-site team. The .NET app is *their* incident-response console. Audience surrogate is a Zava on-call engineer building this tooling on Azure SQL.
- **Headline incident (sev1):** Payroll batch service for tenant **Zava Manufacturing** (50K employees) failing after deploy `payroll-engine v8.12.1`. Payday is tomorrow. Errors mention `Msg 1205` (deadlock) and `tax-svc-3.zava.io 504`. Multi-cause: deadlock regression + flaky tax-service dependency. Past incidents in corpus include 2–3 deliberate near-matches; runbook `Payroll.7 — Tax-service failover and retry strategy` exists.

## 2. Data sources (five, each earning a SQL feature)

| # | Source | Format | Lands in | Feature |
|---|---|---|---|---|
| 1 | Azure Monitor alert envelope | JSON | `Incident.AlertPayload json` | **JSON type + JSON index #1** |
| 2 | Engineer note (free text) | nvarchar(max) | `Incident.EngineerNote` → regex → `Incident.Tags json` | **Regex + JSON index #2** |
| 3 | App logs (`Zava.Payroll.*`) around alert window, ADLS | Parquet | `ext.AppLog` view over `OPENROWSET(... FORMAT='PARQUET')` | **External data virtualization** |
| 4 | Platform logs (App Service / AKS), ADLS | Parquet | `ext.PlatformLog` (same pattern) | **Same feature, second use** |
| 5 | ~500 resolved incidents + ~30 runbooks, ADLS, **embeddings pre-generated in parquet** | Parquet | Bulk-loaded once into `dbo.IncidentArchive` and `dbo.Runbook` | **Parquet → vector column → JSON index + DiskANN** |

`OPENROWSET`-over-parquet appears three times: live app-log context, live platform-log context, one-time corpus materialization. Plumbing: `DATABASE SCOPED CREDENTIAL` (Managed Identity preferred, SAS fallback) + `EXTERNAL DATA SOURCE` over `abs://...blob.core.windows.net`.

## 3. Schema shape

```
dbo.Incident
  IncidentId         int IDENTITY PK
  TenantId           nvarchar(100) NOT NULL    -- 'zava' | 'northwind' | ...
  Service            nvarchar(50)  NOT NULL    -- 'Payroll' | 'OrderEntry' | 'Auth' | ...
  Region             nvarchar(50)
  Severity           nvarchar(10)              -- 'sev1' | 'sev2' | 'sev3'
  Status             nvarchar(20) NOT NULL DEFAULT N'open'  -- open | mitigated | resolved
  AlertPayload       json NOT NULL              -- Azure Monitor envelope
  EngineerNote       nvarchar(max) NULL         -- on-call's first obs + log paste
  Tags               json NULL                  -- regex-extracted tokens
  Embedding          vector(N) NULL             -- of EngineerNote (N depends on model)
  ProposedMitigation json NULL                  -- agent-generated, with citations
  CreatedAtUtc       datetime2 NOT NULL DEFAULT sysutcdatetime()

dbo.IncidentArchive   -- materialized from past_incidents.parquet (pre-embedded)
  -- same shape + RootCause nvarchar(max), Mitigation nvarchar(max), ResolvedAtUtc

dbo.Runbook           -- materialized from runbooks.parquet (pre-embedded)
  RunbookId          varchar(20) PK             -- 'Payroll.7'
  Title              nvarchar(200)
  Content            nvarchar(max)
  Tags               json
  Embedding          vector(N)

ext.AppLog        -- view over OPENROWSET on app_logs.parquet
ext.PlatformLog   -- view over OPENROWSET on platform_logs.parquet
```

**Embedding width** (`N`): 1024 in Azure SQL container path with Ollama (`mxbai-embed-large`), 1536 in Azure SQL Hyperscale path with Azure OpenAI (`text-embedding-3-small`). Single schema authored at one width; deploy script swaps the column type for the other path. DAB config and stored-proc bodies unchanged.

## 4. Indexing

| Index | Table.Column | Paths / params |
|---|---|---|
| **JSON Index #1** | `Incident.AlertPayload` | `$.tenantId`, `$.service`, `$.region`, `$.severity` |
| **JSON Index #1'** | `IncidentArchive.AlertPayload` | same |
| **JSON Index #2** | `Incident.Tags` | `$.errorCode`, `$.build`, `$.dependencyHost`, `$.correlationId`, `$.waitType`, `$.kbRef` |
| **JSON Index #2'** | `IncidentArchive.Tags` | same |
| **JSON Index #3** | `Runbook.Tags` | `$.service`, `$.tags[*]` |
| **DiskANN** | `Incident.Embedding`, `IncidentArchive.Embedding`, `Runbook.Embedding` | cosine |

**Tenant isolation lives in the index, not in app code.** Every hybrid query starts with a JSON-index seek on `tenantId`.

## 5. Regex catalog (committed)

Run server-side at INSERT time on `EngineerNote`. Output is shaped into `Tags json` and indexed by JSON Index #2.

| Tag | Regex (T-SQL string) | Example match |
|---|---|---|
| `errorCode` | `\bMsg\s+(\d{3,5})\b` (then `REPLACE(match_value,'Msg ','')`) | `1205` |
| `build` | `\bv?(\d+\.\d+\.\d+)\b` | `v8.12.1` |
| `dependencyHost` | `\b([a-z0-9-]+\.zava\.io)\b` | `tax-svc-3.zava.io` |
| `correlationId` | GUID pattern | `4f29fd1a-7c8e-4b1c-9ab0-9d2c6c8fefea` |
| `waitType` | `\b(LCK_M_\w+\|PAGELATCH_\w+\|WRITELOG)\b` | `LCK_M_X` |
| `kbRef` | `\b(KB\d{6,7})\b` | `KB5039862` |

Without these, `Tags` is decoration. With these + JSON Index #2, the regex output is **seekable** and joins to JSON Index #1 + DiskANN in one plan.

## 6. The five-feature INSERT

A single statement at incident-create time that uses **five Azure SQL features**:

1. `json` — `AlertPayload`
2. **Regex** — `REGEXP_MATCHES` on `EngineerNote`
3. `json` — `FOR JSON PATH` builds `Tags`
4. `vector` + `AI_GENERATE_EMBEDDINGS` — embed the note (1 row → 1 HTTP call)
5. JSON-indexed + DiskANN-indexed write to `Incident`

This is the on-stage moneyshot for the *write* path.

## 7. The three-index hybrid search

`usp_HybridSearch(@TenantId, @Question)` uses three indexes in one plan:

```
[JSON Index #1: tenantId+service]  →  filter rows for Zava Payroll
        ↓
[JSON Index #2: errorCode='1205']  →  narrow to deadlock-class
        ↓
[DiskANN over Embedding]            →  top-K by similarity to live note
```

Returns top-3 prior incidents + top-3 runbook chunks as a result set the agent uses as RAG context. This is the on-stage moneyshot for the *read* path.

## 8. Architecture (DAB as the single gateway: REST for the website, MCP for the agent)

```
┌────────────────────┐            ┌─────────────────────────┐
│  Zava On-Call │            │  GitHub Copilot Chat       │
│  Console (Blazor)│            │  in Agent mode             │
└───────┬─────────┘            └─────────────────────┬─────┘
        │ REST  (GET / POST)               │ MCP (HTTP /mcp)
        │ /api/Incident/...                │ tools auto-generated from dab-config
        ▼                                  ▼
┌───────────────────────────────────────────────────┐
│  Data API Builder (DAB) — one container, one config                   │
│    runtime.rest.enabled = true    runtime.mcp.enabled = true (HTTP)  │
│    Entities (table, view, stored-procedure) auto-projected to BOTH:   │
│      • Incident                            (table)                  │
│      • IncidentArchive                     (table, read-only)        │
│      • Runbook                             (table, read-only)        │
│      • HybridSearch                        (stored-procedure)       │
│      • LogTimeline                         (stored-procedure)       │
│      • GenerateMitigation                  (stored-procedure)  ← NEW │
│    RBAC by role; audit by DAB logs + SQL Audit                       │
└──────────────────────────────────────────┬────────────────┘
                                                  │ T-SQL
                                                  ▼
┌───────────────────────────────────────────────────┐
│  Azure SQL (Azure SQL container locally / Azure SQL Hyperscale cloud)│
│    • dbo.Incident   (json + vector(N))    • ext.AppLog   (parquet)  │
│    • dbo.IncidentArchive                  • ext.PlatformLog        │
│    • dbo.Runbook                                                    │
│    • usp_HybridSearch / usp_LogTimeline                              │
│    • usp_GenerateMitigation               ← calls sp_invoke         │
│    • EXTERNAL MODEL (embeddings only)     OllamaMxbai (container)   │
│                                            AoaiTextEmbed3Small (cloud)│
│    • Chat via sp_invoke_external_rest_endpoint                       │
│        local: https://localhost:8444/v1/chat/completions (phi4)     │
│        cloud: https://<aoai>.../chat/completions (gpt-4o-mini)      │
└────────────────────────────────────────────────────┘
```

**One DAB config. Two protocols. Same row.**

- **Aspire AppHost orchestrates the local stack.** A single-file `apphost.cs` in `dotnet/AppHost/` defines two resources: `dab` (the Data API Builder container) and `web` (the Blazor WASM project). `WithReference(dab)` injects DAB's randomized host port into the Blazor app's config so the app finds DAB without hard-coded URLs. The Aspire dashboard is disabled (`DisableDashboard = true`) — audience sees the Blazor page only. Launched via `Start-LiveSite.ps1` (which calls `dotnet run apphost.cs`). The `azsql-zavalivesite` SQL container is **not** an Aspire resource — it's long-lived and persists demo data across runs; AppHost simply connection-strings into it via `host.docker.internal,14330`.
- **REST** is the human surface. The Zava On-Call Console is a **Blazor WebAssembly** app (Fluent UI Blazor components). `Pages/Incident.razor` polls `GET /api/Incident/IncidentId/5012` every 2s and renders the JSON columns directly — DAB unwraps `json` to JSON, `Tags` chips light up, `AlertPayload` renders, `ProposedMitigation` populates the AI panel when it goes non-null.
- **MCP** is the agent surface. GHCP Chat in agent mode connects to DAB over **HTTP** at `/mcp` (configured via `.vscode/mcp.json`); the tool list is auto-projected from `dab-config.json` — every entity becomes MCP tools (CRUD for tables, `execute` for stored procedures). No glue code.
- **`usp_GenerateMitigation` is a stored-procedure entity.** That projects it as an MCP `execute_entity` tool (e.g. `GenerateMitigation` / `Incident_GenerateMitigation` depending on DAB ver). The proc body wraps `sp_invoke_external_rest_endpoint` against the chat endpoint URL (`https://localhost:8444/v1/chat/completions` with `phi4` in the container; the AOAI `gpt-4o-mini` deployment URL with `CREDENTIAL = AoaiCred` in the cloud), parses the response, and writes `Incident.ProposedMitigation`. **This is where `sp_invoke` lives in the demo — inside a proc that the agent invokes as an MCP tool.** Note that `EXTERNAL MODEL` only supports `MODEL_TYPE = EMBEDDINGS` today, so chat completions must go through `sp_invoke_external_rest_endpoint` rather than a chat-typed `EXTERNAL MODEL`.
- **No generic `run_sql` tool.** Agent gets typed CRUD + named procs only. RBAC by DAB roles; audit by DAB logs + SQL Audit.
- **EXTERNAL MODEL** is referenced by `AI_GENERATE_EMBEDDINGS` (write-time embedding) **and** by `sp_invoke_external_rest_endpoint` inside `usp_GenerateMitigation` (chat completion). Same indirection mechanism, both paths.

## 9. On-stage flow

Rehearsal helper: run `src/sql/local/Reset-AgentTestState.ps1` to reset and reinsert incident 5012 in one command before manual agent testing.

1. Sev1 alert lands → incident row inserted (the five-feature INSERT in §6).
2. Engineer types: *"Zava payroll job failing since 14:30 UTC. Sev1, payday is tomorrow. Errors mention `Msg 1205 deadlock victim` and `tax-svc-3.zava.io 504`. Last successful run was on `payroll-engine v8.12.1`."*
3. Agent calls `HybridSearch(tenantId='zava', question=...)` → top-3 prior incidents + top-3 runbook chunks, all tenant-scoped.
4. Agent calls `LogTimeline(incidentId)` → joins `ext.AppLog` + `ext.PlatformLog` (parquet via `OPENROWSET`) for the 15-min window around the alert.
5. Agent reasons over RAG context + log timeline, calls `Incident_update` to log proposed mitigation with citations.
6. Console renders: *"Likely cause: deadlock regression in `payroll-engine v8.12.1` + tax-svc-3 timeout. Cited: Incident #4421 (Mar 2026, tenant Northwind, same code path); Runbook `Payroll.7` (Tax-service failover). Recommended: roll back `v8.12.1` and failover to `tax-svc-1`. Logged as Incident #5012."*

## 10. Local-to-cloud dev arc

| Path | Database | Embeddings (EXTERNAL MODEL) | Chat (sp_invoke target) | Notes |
|---|---|---|---|---|
| **Local dev** | **Azure SQL container** | `OllamaMxbai` — `mxbai-embed-large`, `vector(1024)`, `https://localhost:8444/v1/embeddings` (Caddy + Ollama in-container) | `phi4` via `https://localhost:8444/v1/chat/completions` (no credential — Caddy on localhost) | See `ollama/container/SKILL.md` for the trust-store setup; `Prepare-AiContainer.ps1` automates it |
| **Cloud deploy** | **Azure SQL Hyperscale** | `AoaiTextEmbed3Small` — `text-embedding-3-small`, `vector(1536)`, AOAI deployment URL with `CREDENTIAL = AoaiCred` | `gpt-4o-mini` via AOAI `chat/completions` deployment URL with `@credential = AoaiCred` | Same DAB config and procs; the chat URL + credential and the embedding EXTERNAL MODEL identifier change |

**Same product, two surfaces.** The Azure SQL container is the local dev surface for Azure SQL; Hyperscale is the production cloud surface. The Blazor WASM app, `dab-config.json`, MCP tools, and the agent prompt are byte-identical. The proc body changes two strings per call site: the embedding model name (`USE MODEL OllamaMxbai` → `USE MODEL AoaiTextEmbed3Small`) and the `sp_invoke` chat URL (local Caddy → AOAI deployment, plus `@credential = AoaiCred`). The DB column type changes (`vector(1024)` → `vector(1536)`).

**Why distinct names per side, not the same name across both sides:** swapping by name lets both EXTERNAL MODELs coexist in the same database (no drop/recreate on stage), matches what real customers do during migration, and lets a hybrid setup (cloud chat over local DB, or vice versa) exist without renaming.

**Website hosting.** The Blazor WASM app is a viewer; it doesn't move. In the demo it's served locally by the Aspire AppHost (`Start-LiveSite.ps1`). In production, the same compiled `wwwroot` deploys unchanged to Azure Static Web Apps or App Service; DAB runs in Azure Container Apps. The narration calls this out; one Q&A backup slide shows the cloud topology.

## 11. Enterprise pitch (threaded throughout)

- **Multi-tenant:** `TenantId` JSON-index seeks first, every query.
- **RBAC:** DAB roles per entity; agent identity is narrow.
- **Audit:** DAB request logs + SQL Audit; every MCP tool call traceable. *"You can prove what the model did."*
- **DR / HA:** incidents, runbooks, embeddings inherit DB durability. No new data plane to certify.
- **Sovereign / disconnected:** Foundry Local + the Azure SQL container prove it — same product as the cloud, runs on the laptop.
- **Lift-and-shift to Azure:** website to Azure Static Web Apps or App Service, DAB to Container Apps, DB to Hyperscale, chat + embeddings to Azure OpenAI. Same HTML, same DAB config, same procs.

## 12. Talk-title candidates

- AI-Grounded Live-Site Response on Azure SQL
- Same Database, New Capability: Hybrid Search and Agents for the On-Call Engineer
- Live Site at Enterprise Scale: Azure SQL, MCP, and the Agent Framework

## 13. Decisions ledger

| # | Item | Decision |
|---|---|---|
| 4 | `AI_GENERATE_EMBEDDINGS` batches? | **No.** Pre-embed corpus offline; on-stage embeddings are single-row only. |
| Regex catalog | Final 6-tag set | Locked (§5). |
| JSON indexes | Count, paths | Locked (§4) — 5 JSON indexes total + 3 DiskANN. |
| 6 | Fate of `sp_invoke_external_rest_endpoint` | **Resolved.** Lives inside `usp_GenerateMitigation`, exposed via DAB as a stored-procedure entity → MCP `execute_entity` tool. Agent never sees `sp_invoke` directly. |
| EXTERNAL MODEL names | container vs cloud | Locked: `OllamaMxbai` (container) and `AoaiTextEmbed3Small` (cloud) for embeddings — distinct names per side, no drop/recreate on stage. Chat is **not** an EXTERNAL MODEL (Azure SQL only supports `MODEL_TYPE = EMBEDDINGS` today); it goes through `sp_invoke_external_rest_endpoint` against `https://localhost:8444/v1/chat/completions` (phi4, container) or the AOAI `gpt-4o-mini` deployment URL with `AoaiCred` (cloud). |
| Website hosting | local on stage, Azure-eligible in prod | Locked: Blazor WASM app served locally by Aspire AppHost (`Start-LiveSite.ps1`) during demo; query-param swap of DAB base URL for Beat 5; one Q&A slide shows production hosting (SWA / App Service / Container Apps). |
| Local orchestrator | how the stack starts on stage | Locked: **.NET Aspire AppHost** (`dotnet/AppHost/apphost.cs`) launched via `dotnet run apphost.cs` (NOT `aspire run` — the CLI requires the dashboard URL). Resources: `dab` (DAB container) + `web` (Blazor WASM). Aspire dashboard disabled (`DisableDashboard = true`) — audience sees the Blazor page only. `azsql-zavalivesite` is intentionally **outside** Aspire so demo data persists across runs. SQL container exposed on host port 14330 to escape the Windows MSSQLSERVER DAC port collision on 1434. Wrappers: `Start-LiveSite.ps1` / `Stop-LiveSite.ps1`. |
| Trigger | how the agent gets called | **You** are the trigger in the live demo (you type the prompt into GHCP Chat). Narration: *"In production this fires from the alert pipeline; today I'm the pager."* No CDC / triggers / external listener in the live path. |

## 14. Open items

1. Canonical `AlertPayload` JSON shape (exact Azure-Monitor-style field list).
2. Canonical `Tags` JSON shape (mostly implied by §5; commit the schema string).
3. Embedding dims both ways: 1024 (Foundry mxbai) vs 1536 (Azure OpenAI). Pick authoring width + describe the swap in deploy script. *Lean: author at 1024 in container, recreate at 1536 in Hyperscale; corpus re-embedded against AOAI as part of cloud deploy.*
4. ~~`AI_GENERATE_EMBEDDINGS` batching~~ — **resolved (no)**.
5. ~~On-stage incident: inline INSERT vs .NET POST.~~ **Resolved:** inline INSERT only; no .NET app.
6. ~~Fate of `sp_invoke_external_rest_endpoint`.~~ **Resolved:** wrapped inside `usp_GenerateMitigation`, exposed as MCP tool via DAB stored-procedure entity (see §8, §13).
7. Ad-hoc Q&A mode (ask questions without an active incident) as bonus beat.
8. Pin DAB version + MCP-mode docs (re-test before May 2026 stage). DAB ≥ 1.7 required.
9. **Azure assets to pre-provision before the talk:**
   - Azure SQL Hyperscale DB (schema-identical to container, `vector(1536)`, corpus re-embedded against AOAI, incident #5012 pre-loaded).
   - Azure OpenAI resource with `text-embedding-3-small` and `gpt-4o-mini` deployments.
   - Second local DAB process pre-launched on `:5002` pointed at Hyperscale (alongside container DAB on `:5001`).
   - Q&A backup slide: cloud topology (SWA → Container Apps DAB → Hyperscale → AOAI).
10. **Website spec:** Blazor WebAssembly app (`dotnet/Web/ZavaLiveSite.Web.csproj`) using Microsoft.FluentUI.AspNetCore.Components 4.14.1. Single page (`Pages/Incident.razor`) calls one configured DAB base URL (`DabBaseUrl`). Polls `GET /api/Incident/IncidentId/5012` every 2 sec; renders `AlertPayload`, `Tags` chips, `ProposedMitigation` panel.
