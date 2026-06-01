# BRK223 — 6:30 Demo Flow

> Live on laptop. Three surfaces audience sees:
> **(1)** the **Zava On-Call Console** — a Blazor WebAssembly app served locally by the Aspire AppHost, fetching from DAB REST.
> **(2)** the **MSSQL extension** in VS Code — queries, Plan Visualizer, DAB UI, deployment.
> **(3)** **GitHub Copilot Chat** in agent mode — the agent surface, talking to DAB via MCP over HTTP.
>
> One DAB. Two protocols (REST + MCP). Same row. The website is the **frame**;
> SQL + the agent are what makes it real. One backup slide held for Q&A.
> Companion to `design.md`.
>
> Last update: 2026-05-08

## The flow

| # | Beat | Time | Window | Audience sees |
|---|---|---|---|---|
| 0 | Open on the website | 0:00–0:20 | Browser | Zava On-Call Console: SEV1 banner red, incident #5012 ACTIVE, AlertPayload empty / chips empty / AI panel empty ("No mitigation yet…"). *"For the next six minutes I'll show you the SQL that makes this page real."* |
| 1 | Schema check (designer, optional Copilot Chat) | 0:20–1:00 | MSSQL ext (Visualize and Design Schema; optional Copilot Chat) | Right-click connection → **Visualize and Design Schema** — canvas shows the 6 demo tables. Optional (internet): open embedded **Copilot Chat** and ask it to describe the schema in English. |
| 2 | Five-feature INSERT → refresh page | 1:00–2:00 | MSSQL ext + editor + browser refresh | Inline INSERT in `05_create_incident.sql`. Then alt-tab to browser, refresh: AlertPayload populates, three regex-derived chips light up, embedding-length verify in editor. |
| 3 | Hybrid search: two indexes, one statement | 2:00–3:00 | MSSQL ext (open proc + run query) + SSMS (plan view) | Open `01c_proc_hybrid_search.sql` and show `dbo.usp_HybridSearch` — vector side (`vector_distance` over `vec_archive_embedding`) UNION ALL JSON side (`OPENJSON` over `Runbook.Tags`), one statement. Then run `06_hybrid_search.sql` and show actual plan in SSMS: **Vector Index Seek** on `vec_archive_embedding` (DiskANN, incident side) AND **JSON Index Seek** on `ix_runbook_tags` ($.service, runbook side). |
| 4 | DAB → MCP → SKILL-driven agent loop → page lights up | 4:30–6:00 | `04a_proc_generate_mitigation.sql` + `dab-config.json` + Copilot Chat (agent mode, SKILL attached) + browser | (a) Show `usp_GenerateMitigation` first (signature + shape), then `dab-config.json`: REST + MCP from one config; `GenerateMitigation` + the three `dx_*` procs are stored-proc entities. (b) Copilot Chat: select `live-site-sql` agent, type *"Mitigate incident 5012 `@live-site-sql`"* (the `@`-mention forces deterministic skill load — own the choice on stage, see Beat 4(b)). The agent runs the protocol — hybrid_search → dx_index_exists / dx_resource_pressure / dx_deadlock_recent → generate_mitigation (with @DiagnosticsJson) → read back. (c) Alt-tab to browser — AI panel populates with summary, steps, citations, plus a "validated by 3 live diagnostics" badge |
| 5 | Same page, cloud-hosted backend | 6:00–6:30 | MSSQL ext split + browser | MSSQL ext split: container side (`OllamaMxbai` EXTERNAL MODEL + `sp_invoke` to local `phi4`) vs Hyperscale side (`AoaiTextEmbed3Small` EXTERNAL MODEL + `sp_invoke` to AOAI `gpt-4o-mini`). Open the cloud-hosted site (SWA/App Service) and refresh to show the same incident contract via cloud DAB. Same row. Same page shape. *"In production the page lives in SWA/App Service, DAB in Container Apps — lift-and-shift."* |

Total: 6:30. *(Append-only ledger discussion moved to the architecture talk — see [README.md §6](README.md) and [design.md](design.md). Beat 3 still has the reclaimed 1:30 buffer — spend it on Beat 4 or trim the talk.)*

---

## Stage runbook (concise, do this live)

Quick rehearsal shortcut (manual agent test):

- Run `./Reset-AgentTestState.ps1` from `src/sql/local/` to reset and reinsert incident 5012 in one command before Beat 4.

1. **Beat 0 (Browser):** Run `./Open-LiveSite.ps1`.
  - Tool: Browser
  - Show: empty/placeholder state for incident 5012.

2. **Beat 1 (VS Code, MSSQL extension):** Open schema designer.
  - Tool: VS Code + MSSQL extension
  - Action: right-click `localhost,14330 / zavalivesitedb` -> **Visualize and Design Schema**.
  - Action (optional, internet): ask embedded Copilot Chat for a plain-English schema summary.
  - Show: `Incident`, `IncidentArchive`, `Runbook`, `RunbookChunk`, `AppLog`, `PayrollBatch`.

3. **Beat 2 (VS Code, MSSQL extension):** Insert incident row.
  - Tool: VS Code + MSSQL extension
  - File: `src/sql/local/sqlscripts/05_create_incident.sql`
  - Action: execute INSERT batch, then execute the one-line verify query in the same file.
  - Switch to browser and refresh.

4. **Beat 3 (VS Code + SSMS):** Show hybrid search proc, run it, show plan in SSMS.
  - Tool (proc): VS Code editor
  - Tool (run): VS Code + MSSQL extension
  - Tool (plan): SSMS (Actual Execution Plan)
  - Files:
    - `src/sql/local/sqlscripts/01c_proc_hybrid_search.sql` (open and show body of `dbo.usp_HybridSearch` — vector side + JSON side in one statement)
    - `src/sql/local/sqlscripts/06_hybrid_search.sql` (execute)
  - Action: open the proc, point to the vector/JSON union; execute `06_hybrid_search.sql`; in SSMS actual plan, point to:
    - `Vector Index Seek` on `vec_archive_embedding`
    - `Index Seek` on `ix_runbook_tags`

5. **Beat 4a (VS Code editor):** Show `usp_GenerateMitigation`, then DAB REST + MCP config.
  - Tool: VS Code editor
  - Files:
    - `src/sql/local/sqlscripts/04a_proc_generate_mitigation.sql`
    - `src/sql/azure/hosting/dab/dab-config.json`
  - Show: `dbo.usp_GenerateMitigation` signature and JSON writeback shape, then `runtime.rest`, `runtime.mcp`, and stored-proc entities (`GenerateMitigation`, `DxIndexExists`, `DxResourcePressure`, `DxDeadlockRecent`).
  - Say: "DAB is the contract layer: Blazor reads incidents from `/api`, and the agent uses `/mcp` on the same DAB service."
  - Say: "Blazor calls `api/Incident/IncidentId/{id}` through DAB REST."

6. **Beat 4b (Copilot Chat agent mode):** Run mitigation loop.
  - Tool: GitHub Copilot Chat (agent mode)
  - Action: select `live-site-sql` agent and run prompt: `Mitigate incident 5012 @live-site-sql`
  - Show: tool sequence (`hybrid_search`, `dx_*`, `generate_mitigation`) in Chat Debug View after the agent response.

7. **Beat 4c (Browser):** Confirm page lights up.
  - Tool: Browser
  - Show: mitigation summary, steps, citations, and diagnostics badge.

8. **Beat 5a (VS Code editor split):** Show same proc pattern, local vs cloud.
  - Tool: VS Code editor (3-pane split)
  - Files:
    - `src/sql/local/sqlscripts/04a_proc_generate_mitigation.sql`
    - `src/sql/azure/sqlscripts/04a_proc_generate_mitigation.sql`
  - Show: identical shape; URL/credential target differs (local, APIM/AOAI cloud).

9. **Beat 5b (MSSQL extension):** Show cloud row values.
   - Tool: VS Code + MSSQL extension (Hyperscale connection)
   - Action: run `SELECT IncidentId, JSON_VALUE(ProposedMitigation,'$.summary'), JSON_VALUE(ProposedMitigation_v2,'$.summary') FROM dbo.Incident WHERE IncidentId=5012;`

10. **Close:** same row, same contract, local and cloud paths.

## Beat-by-beat detail (concise operator script)

Use this section during rehearsal and on stage. It mirrors the runbook above but keeps one short spoken line per beat.

### Beat 0 — Open on the website (0:20)

- Tool: Browser
- Run: `./Open-LiveSite.ps1`
- Show: empty state (no mitigation yet, placeholder chips/fields)
- Say: *"This is the on-call console. In 30 seconds, one SQL INSERT will light up this page."*

### Beat 1 — Schema check (0:40)

- Tool: VS Code + MSSQL extension
- Open: Schema Designer on `localhost,14330 / zavalivesitedb`
- Show: `Incident`, `IncidentArchive`, `Runbook`, `RunbookChunk`, `AppLog`, `PayrollBatch`
- Optional (internet): ask embedded Copilot Chat to summarize the schema in plain English
- Say: *"Six demo tables, one data story."*

### Beat 2 — INSERT then refresh (1:00)

- Tool: VS Code + MSSQL extension
- Open file: `src/sql/local/sqlscripts/05_create_incident.sql`
- Run: INSERT batch, then the one-line verify query in the same file
- Switch: browser refresh
- Show: alert JSON, chips (`1205`, `9114.10212`, `LCK_M_X`), engineer note
- Say: *"One statement used JSON, regex, FOR JSON shaping, and embeddings to create the incident row."*

### Beat 3 — Hybrid search + plan (1:00)

- Tool (run): VS Code + MSSQL extension
- Tool (plan): SSMS Actual Execution Plan
- Open file: `src/sql/local/sqlscripts/06_hybrid_search.sql`
- Run: `EXEC dbo.usp_HybridSearch ...`
- In SSMS plan, point to:
  - `Vector Index Seek` on `vec_archive_embedding`
  - `Index Seek` on `ix_runbook_tags`
- Say: *"Same query, two specialized index families, one optimizer plan. I am showing the plan in SSMS because VS Code plan rendering is currently inconsistent for vector operators."*

### Beat 4 — Agent loop + page update (1:30)

- Tool: VS Code editor + Copilot Chat agent mode + Browser
- Open files:
  - `src/sql/local/sqlscripts/04a_proc_generate_mitigation.sql`
  - `src/sql/azure/hosting/dab/dab-config.json`
- Show: `dbo.usp_GenerateMitigation` signature and JSON writeback flow first, then `runtime.rest`, `runtime.mcp`, and proc entities (`GenerateMitigation`, `DxIndexExists`, `DxResourcePressure`, `DxDeadlockRecent`)
- Say: *"DAB is the contract layer: Blazor reads from `/api`, and the agent uses `/mcp` on the same service."*
- Say: *"Blazor calls `api/Incident/IncidentId/{id}` through DAB REST."*
- Copilot Chat:
  - Open a **new chat**
  - Select agent `live-site-sql`
  - Run prompt: `Mitigate incident 5012 @live-site-sql`
  - After the response lands, open Chat Debug View and point to the tool-call trace
- Show: tool sequence (`hybrid_search`, `dx_index_exists`, `dx_resource_pressure`, `dx_deadlock_recent`, `generate_mitigation`)
- Switch: browser
- Show: mitigation summary, citations, diagnostics badge
- Say: *"The agent grounded each step in corpus evidence plus live diagnostics from the same database."*

### Beat 5 — Local vs cloud path (0:30)

- Tool: VS Code editor split + MSSQL extension (Hyperscale)
- Open files in split view:
  - `src/sql/local/sqlscripts/04a_proc_generate_mitigation.sql`
  - `src/sql/azure/sqlscripts/04a_proc_generate_mitigation.sql`
- Show: same proc shape; only endpoint/credential path differs (local vs cloud APIM/AOAI)
- Run on Hyperscale:

```sql
SELECT  IncidentId,
      JSON_VALUE(ProposedMitigation,    '$.summary') AS direct_summary,
      JSON_VALUE(ProposedMitigation_v2, '$.summary') AS gateway_summary
FROM    dbo.Incident
WHERE   IncidentId = 5012;
```

- Say: *"Same row and JSON contract across local and cloud endpoints."*

## Post-reboot quick start (back to Beat 0)

If you reboot before presenting, run this from `src/sql/local` to return to Beat 0:

1. `docker start azsql-zavalivesite`
2. `./Reset-ForBeat2.ps1`
3. `./Warmup-Ai.ps1 -ContainerName azsql-zavalivesite`
4. `./Verify-Build.ps1`
5. `./Start-LiveSite.ps1`
6. `./Open-LiveSite.ps1`

If step 1 fails because the container is missing, run `./prepare-demo.ps1` once, then continue from Beat 0.
