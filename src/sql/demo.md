# BRK223 — 7-Minute Demo Flow

## Presenter cheat sheet (one page)

- Beat 0 (0:00-0:20)
  - Tool: Browser
  - Run: `./Open-LiveSite.ps1`
  - Do: Show empty state.
  - Say: "One SQL row will light up this page."

- Beat 1 (0:20-1:00)
  - Tool: VS Code + MSSQL extension
  - Open: Schema Designer on `localhost,14330 / zavalivesitedb`
  - Do: Run `SELECT @@VERSION;` (call out that it reports Azure SQL), then right-click connection -> Visualize and Design Schema; ask embedded Copilot Chat to describe the schema.
  - Say: "Azure SQL engine, six demo tables, one data story."

- Beat 2 (1:00-2:00)
  - Tool: VS Code + MSSQL extension
  - Open file: `src/sql/local/sqlscripts/05_create_incident.sql`
  - Do: Run INSERT, run verify, refresh browser.
  - Say: "JSON + regex + embeddings in one statement."

- Beat 3 (2:00-3:00)
  - Tool (run): VS Code + MSSQL extension
  - Tool (plan): SSMS Actual Execution Plan
  - Open file: `src/sql/local/sqlscripts/06_hybrid_search.sql`
  - Do: Run proc; in SSMS point to `Vector Index Seek` (`vec_archive_embedding`) and `Index Seek` (`ix_runbook_tags`).
  - Say: "One query, two index families; SSMS is used because VS Code plan rendering is inconsistent for vector operators."

- Beat 4 (4:30-5:00)
  - Tool: VS Code + MSSQL extension
  - Open file: `src/sql/local/sqlscripts/07_log_timeline.sql`
  - Do: Run timeline query for incident 5012.
  - Say: "Tamper-evident ledger timeline, no external pipeline."

- Beat 5 (5:00-6:30)
  - Tool: VS Code editor + Copilot Chat (agent mode) + Browser
  - Open file: `src/sql/azure/hosting/dab/dab-config.json`
  - Do: Show `runtime.rest` + `runtime.mcp`; new chat; select `live-site-sql`; run `Mitigate incident 5012 @live-site-sql`; after the response, show Chat Debug View with tool-call trace; switch to browser and show mitigation.
  - Say: "Grounded plan from corpus + live diagnostics in one loop."

- Beat 6 (6:30-7:00)
  - Tool: VS Code editor split + MSSQL extension (Hyperscale)
  - Open files:
    - `src/sql/local/sqlscripts/04a_proc_generate_mitigation.sql`
    - `src/sql/azure/sqlscripts/04a_proc_generate_mitigation_direct.sql`
    - `src/sql/azure/sqlscripts/04a_proc_generate_mitigation_gateway.sql`
  - Do: Show same proc shape across local/direct/gateway; run cloud summary select for incident 5012.
  - Say: "Same row and JSON contract across local and cloud endpoints."

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
| 1 | Schema check (version + designer + Copilot Chat) | 0:20–1:00 | MSSQL ext (query + Visualize and Design Schema + Copilot Chat) | Run `SELECT @@VERSION;` and call out that the engine reports Azure SQL, then right-click connection → **Visualize and Design Schema** — canvas shows the 6 demo tables; open embedded **Copilot Chat** and ask it to describe the schema in English. |
| 2 | Five-feature INSERT → refresh page | 1:00–2:00 | MSSQL ext + editor + browser refresh | Inline INSERT in `05_create_incident.sql`. Then alt-tab to browser, refresh: AlertPayload populates, three regex-derived chips light up, embedding-length verify in editor. |
| 3 | Hybrid search: two indexes, one statement | 2:00–3:00 | MSSQL ext (run query) + SSMS (plan view) | Run `06_hybrid_search.sql`, then show actual plan in SSMS: **Vector Index Seek** on `vec_archive_embedding` (DiskANN, incident side) AND **JSON Index Seek** on `ix_runbook_tags` ($.service, runbook side). |
| 4 | Ledger timeline | 4:30–5:00 | MSSQL ext: `07_log_timeline.sql` | `SELECT TOP 10 * FROM dbo.AppLog WHERE IncidentId=5012 ORDER BY ts;` — append-only ledger, tamper-evident, no external storage |
| 5 | DAB → MCP → SKILL-driven agent loop → page lights up | 5:00–6:30 | `dab-config.json` + Copilot Chat (agent mode, SKILL attached) + browser | (a) Show `dab-config.json`: REST + MCP from one config; `GenerateMitigation` + the three `dx_*` procs are stored-proc entities. (b) Copilot Chat: select `live-site-sql` agent, type *"Mitigate incident 5012 `@live-site-sql`"* (the `@`-mention forces deterministic skill load — own the choice on stage, see Beat 5(b)). The agent runs the protocol — hybrid_search → dx_index_exists / dx_resource_pressure / dx_deadlock_recent → generate_mitigation (with @DiagnosticsJson) → read back. (c) Alt-tab to browser — AI panel populates with summary, steps, citations, plus a "validated by 3 live diagnostics" badge |
| 6 | Same page, cloud-hosted backend | 6:30–7:00 | MSSQL ext split + browser | MSSQL ext split: container side (`OllamaMxbai` EXTERNAL MODEL + `sp_invoke` to local `phi4-mini`) vs Hyperscale side (`AoaiTextEmbed3Small` EXTERNAL MODEL + `sp_invoke` to AOAI `gpt-4o-mini`). Open the cloud-hosted site (SWA/App Service) and refresh to show the same incident contract via cloud DAB. Same row. Same page shape. *"In production the page lives in SWA/App Service, DAB in Container Apps — lift-and-shift."* |

Total: 7:00. *(Beat 3 reclaimed 1:30 from the old slow→fast version — spend it on Beat 5 or trim the talk.)*

---

## Stage runbook (concise, do this live)

Quick rehearsal shortcut (manual agent test):

- Run `./Reset-AgentTestState.ps1` from `src/sql/local/` to reset and reinsert incident 5012 in one command before Beat 5.

1. **Beat 0 (Browser):** Run `./Open-LiveSite.ps1`.
  - Tool: Browser
  - Show: empty/placeholder state for incident 5012.

2. **Beat 1 (VS Code, MSSQL extension):** Open schema designer.
  - Tool: VS Code + MSSQL extension
  - Action: run `SELECT @@VERSION;` and call out Azure SQL in the result, then right-click `localhost,14330 / zavalivesitedb` -> **Visualize and Design Schema**.
  - Show: `Incident`, `IncidentArchive`, `Runbook`, `RunbookChunk`, `AppLog`, `PayrollBatch`.

3. **Beat 2 (VS Code, MSSQL extension):** Insert incident row.
  - Tool: VS Code + MSSQL extension
  - File: `src/sql/local/sqlscripts/05_create_incident.sql`
  - Action: execute INSERT batch, then execute the one-line verify query in the same file.
  - Switch to browser and refresh.

4. **Beat 3 (VS Code + SSMS):** Run hybrid search, show plan in SSMS.
  - Tool (run): VS Code + MSSQL extension
  - Tool (plan): SSMS (Actual Execution Plan)
  - File: `src/sql/local/sqlscripts/06_hybrid_search.sql`
  - Action: execute proc; in SSMS actual plan, point to:
    - `Vector Index Seek` on `vec_archive_embedding`
    - `Index Seek` on `ix_runbook_tags`

5. **Beat 4 (VS Code, MSSQL extension):** Show ledger timeline.
  - Tool: VS Code + MSSQL extension
  - File: `src/sql/local/sqlscripts/07_log_timeline.sql`
  - Action: execute query and show append-only timeline rows for incident 5012.

6. **Beat 5a (VS Code editor):** Show DAB REST + MCP config.
  - Tool: VS Code editor
  - File: `src/sql/azure/hosting/dab/dab-config.json`
  - Show: `runtime.rest`, `runtime.mcp`, and stored-proc entities (`GenerateMitigation`, `DxIndexExists`, `DxResourcePressure`, `DxDeadlockRecent`).

7. **Beat 5b (Copilot Chat agent mode):** Run mitigation loop.
  - Tool: GitHub Copilot Chat (agent mode)
  - Action: select `live-site-sql` agent and run prompt: `Mitigate incident 5012 @live-site-sql`
  - Show: tool sequence (`hybrid_search`, `dx_*`, `generate_mitigation`) in Chat Debug View after the agent response.

8. **Beat 5c (Browser):** Confirm page lights up.
  - Tool: Browser
  - Show: mitigation summary, steps, citations, and diagnostics badge.

9. **Beat 6a (VS Code editor split):** Show same proc pattern, three URL targets.
  - Tool: VS Code editor (3-pane split)
  - Files:
    - `src/sql/local/sqlscripts/04a_proc_generate_mitigation.sql`
    - `src/sql/azure/sqlscripts/04a_proc_generate_mitigation_direct.sql`
    - `src/sql/azure/sqlscripts/04a_proc_generate_mitigation_gateway.sql`
  - Show: identical shape; URL/credential target differs (local, AOAI direct, APIM gateway).

10. **Beat 6b (MSSQL extension):** Show cloud row values.
   - Tool: VS Code + MSSQL extension (Hyperscale connection)
   - Action: run `SELECT IncidentId, JSON_VALUE(ProposedMitigation,'$.summary'), JSON_VALUE(ProposedMitigation_v2,'$.summary') FROM dbo.Incident WHERE IncidentId=5012;`

11. **Close:** same row, same contract, local and cloud paths.

## Beat-by-beat detail (concise operator script)

Use this section during rehearsal and on stage. It mirrors the runbook above but keeps one short spoken line per beat.

### Beat 0 — Open on the website (0:20)

- Tool: Browser
- Run: `./Open-LiveSite.ps1`
- Show: empty state (no mitigation yet, placeholder chips/fields)
- Say: *"This is the on-call console. In 30 seconds, one SQL INSERT will light up this page."*

### Beat 1 — Schema check (0:40)

- Tool: VS Code + MSSQL extension
- Run: `SELECT @@VERSION;`
- Say: *"This is Azure SQL."*
- Open: Schema Designer on `localhost,14330 / zavalivesitedb`
- Show: `Incident`, `IncidentArchive`, `Runbook`, `RunbookChunk`, `AppLog`, `PayrollBatch`
- Ask embedded Copilot Chat to summarize the schema in plain English
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

### Beat 4 — Ledger timeline (0:30)

- Tool: VS Code + MSSQL extension
- Open file: `src/sql/local/sqlscripts/07_log_timeline.sql`
- Run: timeline query for incident 5012
- Show: append-only deadlock sequence around 14:30 UTC
- Say: *"Tamper-evident app timeline in SQL ledger, no external pipeline."*

### Beat 5 — Agent loop + page update (1:30)

- Tool: VS Code editor + Copilot Chat agent mode + Browser
- Open file: `src/sql/azure/hosting/dab/dab-config.json`
- Show: `runtime.rest`, `runtime.mcp`, and proc entities (`GenerateMitigation`, `DxIndexExists`, `DxResourcePressure`, `DxDeadlockRecent`)
- Copilot Chat:
  - Open a **new chat**
  - Select agent `live-site-sql`
  - Run prompt: `Mitigate incident 5012 @live-site-sql`
  - After the response lands, open Chat Debug View and point to the tool-call trace
- Show: tool sequence (`hybrid_search`, `dx_index_exists`, `dx_resource_pressure`, `dx_deadlock_recent`, `generate_mitigation`)
- Switch: browser
- Show: mitigation summary, citations, diagnostics badge
- Say: *"The agent grounded each step in corpus evidence plus live diagnostics from the same database."*

Plan B fallback:
- If smoke test fails, play `fallback/beat4_agent_lights_up_page.mp4` and continue at Beat 5c.

### Beat 6 — Local vs cloud path (0:40)

- Tool: VS Code editor split + MSSQL extension (Hyperscale)
- Open files in 3-pane split:
  - `src/sql/local/sqlscripts/04a_proc_generate_mitigation.sql`
  - `src/sql/azure/sqlscripts/04a_proc_generate_mitigation_direct.sql`
  - `src/sql/azure/sqlscripts/04a_proc_generate_mitigation_gateway.sql`
- Show: same proc shape; only endpoint/credential path differs (local, AOAI direct, APIM gateway)
- Run on Hyperscale:

```sql
SELECT  IncidentId,
      JSON_VALUE(ProposedMitigation,    '$.summary') AS direct_summary,
      JSON_VALUE(ProposedMitigation_v2, '$.summary') AS gateway_summary
FROM    dbo.Incident
WHERE   IncidentId = 5012;
```

- Say: *"Same row and JSON contract across local and cloud endpoints."*

## Fallback recordings

- `beat0_open_website.mp4` — nice-to-have
- `beat1_insert_then_refresh.mp4` — nice-to-have
- `beat2_slow_to_fast.mp4` — high priority (plan visualizer + `@mssql` + retune is live-risk-prone)
- **`beat4_agent_lights_up_page.mp4` — MANDATORY.** Plan B for Beat 5. Open in VLC paused on monitor 2 before doors. Includes the chat conversation through to the final mitigation answer; ends *before* the browser tab is shown so 5(c) flows in identically.
- `beat5_three_panes_and_select.mp4` — nice-to-have. Captures the 3-pane editor split scroll + the Hyperscale `SELECT JSON_VALUE(...) FROM Incident WHERE IncidentId=5012` returning both `direct_summary` and `gateway_summary`.
