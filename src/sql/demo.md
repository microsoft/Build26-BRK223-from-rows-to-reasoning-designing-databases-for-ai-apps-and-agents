# BRK223 — 7-Minute Demo Flow

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

---

## Cuts (do not attempt on stage)

- ❌ Live `CREATE VECTOR INDEX` (100-row min, slow, boring) — pre-built.
- ❌ Building schema / DAB config / EXTERNAL MODEL — pre-deployed before doors open.
- ❌ **Separate .NET Zava On-Call Console (custom backend).** The frontend lives, but as a Blazor WASM app served by the Aspire AppHost — no custom HTTP backend. Reads DAB REST directly. **(2)** GitHub Copilot Chat in agent mode talks to the same DAB over HTTP MCP. Same architecture (`agent → MCP → DAB → SQL` and `browser → REST → DAB → SQL`), one fewer process to babysit, no hotel-wifi risk for the front-end.
- ❌ Graphical query plans — at most one `STATISTICS IO` print to prove index seeks.
- ❌ Two incidents (inline INSERT *and* .NET POST) — keep just the inline INSERT.
- ❌ **`sp_invoke_external_rest_endpoint` as a standalone beat.** It's *in the demo* — inside `usp_GenerateMitigation`, which DAB exposes as a stored-procedure MCP tool the agent calls. We don't run `sp_invoke` from the editor; we let the proc do it.

---

## The flow

| # | Beat | Time | Window | Audience sees |
|---|---|---|---|---|
| 0 | Open on the website | 0:00–0:20 | Browser | Zava On-Call Console: SEV1 banner red, incident #5012 ACTIVE, AlertPayload empty / chips empty / AI panel empty ("No mitigation yet…"). *"For the next six minutes I'll show you the SQL that makes this page real."* |
| 1 | Schema check + five-feature INSERT → refresh page | 0:20–2:00 | MSSQL ext (Visualize and Design Schema + Copilot Chat) + editor + browser refresh | (a) Right-click connection → **Visualize and Design Schema** — canvas shows the 6 demo tables; open the embedded **Copilot Chat** and ask it to describe the schema in English. (b) Inline INSERT in `05_create_incident.sql`. Then alt-tab to browser, refresh: AlertPayload populates, three regex-derived chips light up, embedding-length verify in editor |
| 2 | Hybrid search: two indexes, one statement | 2:00–3:00 | MSSQL ext + **Actual Plan ON** | `EXEC usp_HybridSearch` returns prior incidents + matching runbook. Plan tab shows **Vector Index Seek** on `vec_archive_embedding` (DiskANN, incident side) AND **JSON Index Seek** on `ix_runbook_tags` ($.service, runbook side) — two specialized access paths composed in one query. |
| 3 | Ledger timeline | 4:30–5:00 | MSSQL ext: `07_log_timeline.sql` | `SELECT TOP 10 * FROM dbo.AppLog WHERE IncidentId=5012 ORDER BY ts;` — append-only ledger, tamper-evident, no external storage |
| 4 | DAB → MCP → SKILL-driven agent loop → page lights up | 5:00–6:30 | `dab-config.json` + Copilot Chat (agent mode, SKILL attached) + browser | (a) Show `dab-config.json`: REST + MCP from one config; `GenerateMitigation` + the three `dx_*` procs are stored-proc entities. (b) Copilot Chat: select `live-site-sql` agent, type *"Mitigate incident 5012 `@live-site-sql`"* (the `@`-mention forces deterministic skill load — own the choice on stage, see Beat 4(b)). The agent runs the protocol — hybrid_search → dx_index_exists / dx_resource_pressure / dx_deadlock_recent → generate_mitigation (with @DiagnosticsJson) → read back. (c) Alt-tab to browser — AI panel populates with summary, steps, citations, plus a "validated by 3 live diagnostics" badge |
| 5 | Same page, swap DAB to Hyperscale + AOAI | 6:30–7:00 | MSSQL ext split + browser | MSSQL ext split: container side (`OllamaMxbai` EXTERNAL MODEL + `sp_invoke` to local `phi4-mini`) vs Hyperscale side (`AoaiTextEmbed3Small` EXTERNAL MODEL + `sp_invoke` to AOAI `gpt-4o-mini`). Browser URL bar: `?dab=local` → `?dab=cloud`, refresh; footer flips to *"Powered by Azure SQL Hyperscale + Azure OpenAI."* Same row. Same page. *"In production the page lives in SWA, DAB in Container Apps — lift-and-shift."* |

Total: 7:00. *(Beat 2 reclaimed 1:30 from the old slow→fast version — spend it on Beat 4 or trim the talk.)*

---

## Beat-by-beat detail

### Beat 0 — Open on the website (0:20)

**No slide.** Browser tab is the first thing audience sees: `http://localhost:8080/?dab=local`. Chrome, full-screen, dev tools closed.

**The empty-state UI** — the page polls DAB every 2 seconds, so before Beat 1 it renders the frame with placeholders so the audience can read the layout:

- Title: **"Zava Live Site Incident Systems"**.
- Top-right: a small identity chip — avatar circle **BW** + **Bob Ward · On-call engineer**. The audience sees the operator is "logged in".
- Refresh button + "Last refreshed HH:mm:ss" so they know it's live.
- **No SEV1 banner yet** — the red banner only paints once a row exists, so the page doesn't lie about state.
- **Identity card:** neutral `—` severity badge, `— — —` for Service / Tenant, `—` for status; under it, three labelled placeholders for Tenant / Service / Region all showing `—`.
- **Engineer note card:** "(no engineer note yet)" in muted grey.
- **Proposed mitigation card:** "No mitigation yet. The on-call agent will draft one when it sees similar past incidents and a matching runbook."
- **Alert payload card:** "(no payload yet — populated when the incident is created)."
- **Tags row:** three grey pill chips `errorCode: —`, `build: —`, `waitType: —`.
- Footer (always rendered): *"Powered by Azure SQL · DAB REST · MCP · live data."*

Once Beat 1 runs, the polling loop picks the row up and every placeholder swaps to its real value at once — severity badge turns red, header changes to `Incident #5012 — Payroll batch Msg 1205 surge after 9114.10212 deploy` (pulled from `AlertPayload.description`), tags chips light blue with the regex-derived values, engineer-note prose appears.

Spoken cue (~20 s): *"This is the Zava on-call console. I'm logged in as Bob Ward, the on-call engineer. Right now everything's quiet — empty frame, dashes in every slot, no SEV1 banner. In about thirty seconds I'm going to insert one row into SQL Server, and you'll watch these cards fill in: severity, identity, the alert JSON, regex-derived tags, the engineer note, and a slot for the AI mitigation. One INSERT. One Blazor WASM page polling DAB REST every two seconds. No backend glue in between."*

> The page is a Blazor WASM SPA hosted by the Aspire AppHost. It polls `/api/Incident/IncidentId/5012` against DAB every 2 seconds, so as soon as Beat 1's INSERT lands the row, the empty cards fill in without a manual refresh. The `?dab=` query string can flip to the Hyperscale-backed DAB but **Beat 5 doesn't use it** — Beat 5 reads the Hyperscale row directly from MSSQL ext (see Beat 5(b)). The "live data" line in the footer is the truth.

### Beat 1 — Schema check + five-feature INSERT (1:30)

#### 1(a) Schema check via MSSQL ext (~20 s)

Before we touch a row, audience should see **what database we're writing to** — and see it through the *tooling*, not a slide.

**Pre-stage:** In the MSSQL extension sidebar, the `localhost,14330 / zavalivesitedb` connection is already expanded.

**On stage:**

1. **Right-click the connection** → **Visualize and Design Schema**. The Schema Designer canvas opens with the six demo tables laid out: `Incident`, `IncidentArchive`, `Runbook`, `RunbookChunk`, `AppLog`, `PayrollBatch`. Zoom-to-fit so all six are readable. Point the cursor at three things — *don't read the columns out loud, let the audience read*:
   - **`Incident` / `IncidentArchive`** — same shape; live queue + 150k archived rows. `Embedding vector` column on both.
   - **`Runbook` / `RunbookChunk`** — document + chunks, both with `Embedding vector`. This is the corpus the agent retrieves over in Beat 2.
   - **`AppLog`** — note the two `ledger_start_*` system columns; that's how you spot an append-only ledger table at a glance. Beat 3 reads this.
2. **Open Copilot Chat from inside the designer.** The chat panel ships with a built-in **"overview the schema"** action — click it, no typing. The agent walks the canvas and writes a plain-English summary of the tables, what each one is for, and which columns hold embeddings vs structured fields. Let it stream; don't read it aloud, the audience can read.

Spoken cue (~20 s): *"Before I write a single row — this is the database. Six tables. Two are the incident queue, live and archived. Two are runbooks and their chunks. One is a ledger app log. And one is the business table — payroll batches. I didn't draw this — the MSSQL extension reads it straight off the server. And I can ask Copilot for an overview, in English, with one click. Same database, two ways to look at it. Now let's write to it."*

> **Stage tip.** Keep the Schema Designer tab open in a background tab group — you'll alt-tab back to it once during Beat 2 if anyone in Q&A asks how `Runbook` connects to `RunbookChunk`. Don't promise FK arrows; the demo schema uses logical keys, not declared foreign keys (call that out only if asked).

#### 1(b) Five-feature INSERT (~70 s)

**File:** `05_create_incident.sql`. Cursor pre-positioned. One run, then one verify.

The single INSERT uses **five Azure SQL features**:

```sql
DECLARE @alert json = JSON_OBJECT(
    'tenantId':'zava', 'service':'Payroll', 'region':'eastus2',
    'severity':'sev1', 'incidentId':5012, 'object':'dbo.PayrollBatch',
    'description':'Payroll batch Msg 1205 surge after 9114.10212 deploy');

DECLARE @note nvarchar(max) = N'Zava payroll batch failing since 14:30 UTC,
payday tomorrow (sev1). Msg 1205: Transaction was deadlocked on lock resources
with another process and has been chosen as the deadlock victim. Wait type
LCK_M_X on dbo.PayrollBatch key (TenantId, RunDate). Started right after
rolling Build 9114.10212. Last clean rev was 9114.10180.';

INSERT dbo.Incident (IncidentId, TenantId, Service, Region, Severity, AlertPayload,
                     EngineerNote, Tags, Embedding)
SELECT
    5012,
    JSON_VALUE(@alert, '$.tenantId'),                   -- (1) json
    JSON_VALUE(@alert, '$.service'),
    JSON_VALUE(@alert, '$.region'),
    JSON_VALUE(@alert, '$.severity'),
    @alert,                                              -- (1) json column
    @note,
    (SELECT                                              -- (2) regex → (3) FOR JSON
        (SELECT TOP 1 m.match_value FROM REGEXP_MATCHES(@note, '\bMsg\s+(\d{3,5})\b') m)   AS errorCode,
        (SELECT TOP 1 m.match_value FROM REGEXP_MATCHES(@note, '\b\d{4}\.\d{4,5}\b')   m)   AS [build],
        (SELECT TOP 1 m.match_value FROM REGEXP_MATCHES(@note, '\bLCK_M_[A-Z]+\b')     m)   AS waitType
     FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    AI_GENERATE_EMBEDDINGS(@note USE MODEL OllamaMxbai); -- (4) embed (5) vector(1024)
```

**One-line verify** (same script, second batch — don't dwell. `Embedding` returns as the native vector type; the MSSQL ext grid renders the bracketed float array.):

```sql
SELECT TOP 1 IncidentId, Tags, Embedding
FROM dbo.Incident ORDER BY IncidentId DESC;
```

**Then alt-tab to the browser and hit refresh.** The website lights up:

- AlertPayload JSON card populates (the `json` column round-trips through DAB REST as native JSON).
- Three Tags chips flip from `—` to **errorCode: 1205**, **build: 9114.10212**, **waitType: LCK_M_X**. These came from the regex output that the INSERT shaped into `Tags json`.
- Engineer note panel populates.
- AI mitigation panel still empty — the agent hasn't run yet.

Spoken cue: *"One INSERT. JSON typed. Regex pulled error code, build, dependency. Vector generated against Ollama, running right next to Azure SQL in the same container. The on-call console you saw a moment ago — it's reading that exact row through DAB's REST endpoint. Five SQL features. One statement. One refresh."*

> **Stage tip — Beat 1 editor zoom.** This is a code-forward audience: they came to read the INSERT. Zoom the editor to **24pt+** (Cmd/Ctrl++ three or four steps) before doors open and leave it there for the rest of the talk. As you speak the five features, briefly point the cursor at each one (`json` column, `REGEXP_MATCHES`, `FOR JSON PATH`, `AI_GENERATE_EMBEDDINGS`, `vector(1024)`) — don't read the SQL aloud, let them read it.

### Beat 2 — Hybrid search: two indexes, one statement (1:00)

One proc. Two corpora with different shapes. The optimizer composes a **DiskANN Vector Index Seek** and a **JSON Index Seek** in the same plan, picking each access method by selectivity. That's the moment to make — Azure SQL is the only engine that ships both index families and lets you call them in one statement.

**Pre-stage:** Click **Enable Actual Plan** in the MSSQL editor toolbar. Leave it on for the whole beat. Pre-close any old plan tabs.

**File:** `06_hybrid_search.sql`.

```sql
EXEC dbo.usp_HybridSearch
     @TenantId  = N'zava',
     @Question  = N'Payroll batch Msg 1205 deadlock victim on dbo.PayrollBatch after build 9114.10212. Mitigate.',
     @ErrorCode = N'1205',
     @Service   = N'Payroll',
     @TopK      = 5;
```

F5. Two result kinds come back, interleaved by distance:

1. Top prior incidents — **IncidentArchive #4421 (zava, 6 weeks ago, same Msg 1205 deadlock on dbo.PayrollBatch)** at the top.
2. Top runbook chunks — **Runbook `Payroll.7 — Payroll batch deadlock mitigation`** at the top.

Click the **Plan** tab. Point at two operators:

- **Vector Index Seek** on `vec_archive_embedding` — DiskANN over `IncidentArchive.Embedding` (~150k weakly-tagged rows). Semantic search drives this side because the structured filters aren't selective enough on their own; tenant/errorCode run as residual filters on the bookmark side.
- **JSON Index Seek** on `ix_runbook_tags` for `$.service = 'Payroll'` — narrows the ~6k runbook chunks down to a handful, and then exact `vector_distance` ranks them. No DiskANN on this side because the structured filter is the right driver.

Spoken cue: *"One statement. Two specialized indexes. DiskANN drives the big, weakly-tagged corpus on the left; the JSON index drives the small, well-tagged corpus on the right. The optimizer picked the right tool for each side — not me, not the developer. Vector search and structured search composed by the engine, in one query."*

> **Why this matters.** Most "hybrid search" demos run the two halves in separate stages (full-text or filter, then re-rank with vectors) glued together in application code. Here it's one T-SQL statement, one plan, two specialized index seeks. That's the shape that survives going from a demo to a production OLTP workload.

### Beat 3 — Ledger timeline (0:30)

**File:** `07_log_timeline.sql`. Reads from `dbo.AppLog` — an **APPEND-ONLY LEDGER** table. No ADLS, no parquet, no ETL. Every row is hashed into the database Merkle tree; rows can never be updated or deleted.

```sql
SELECT TOP 10 ts, level, message
FROM   dbo.AppLog
WHERE  IncidentId = 5012
   AND ts BETWEEN '2026-05-04T14:25:00' AND '2026-05-04T14:35:00'
ORDER BY ts;
```

Audience sees deadlock-victim entries (Msg 1205 / LCK_M_X / build 9114.10212) clustered around 14:30 UTC.

Spoken cue: *"App logs in a SQL ledger table — tamper-evident, append-only, cryptographically verifiable. No ETL, no ADLS, no external storage. The same `SELECT` you've written for years — with a Merkle tree behind it."*

### Beat 4 — SKILL-driven agent loop: corpus + live state → mitigation (1:30)

The payoff. The 2025 version of this beat was corpus-only retrieval + compose. The 2026 version proves the database is doing **two distinct jobs at the same instant**: it's the **corpus store** (vector index over `IncidentArchive` + `Runbook`) AND the **live system being mitigated** (DMVs + `dbo.AppLog` ledger). The agent has to consult *both* and reason over them. That's the irreducible LLM job.

Three sub-cuts: (a) the config that ties REST + MCP + the new `dx_*` tools together, (b) the agent driving the SKILL protocol, (c) the website lighting up with a "validated by diagnostics" badge.

> **What's different vs Beat 4 in 2025**
> | | 2025 | 2026 (this) |
> |---|---|---|
> | Visible tool calls | 3 (`hybrid_search`, `log_timeline`, `generate_mitigation`) | 6 (adds `dx_index_exists`, `dx_resource_pressure`, `dx_deadlock_recent`, plus a `read_records` to confirm the row was written) |
> | Agent loop | Linear, predetermined | Reads runbook → **chooses** which dx to run → folds findings into prompt as ground truth |
> | Mitigation grounding | Corpus only | Corpus *and* live state — agent verifies each runbook step is still relevant + safe to apply now |
> | Wall-clock (CPU laptop) | ~120 s | ~110–120 s (validated 2026-05-12) |

#### 4(a) `dab-config.json` — one config, REST + MCP + dx tools (0:15)

MSSQL ext sidebar → click `dab/dab-config.json`. Cursor pre-positioned on the runtime block. Audience reads:

```jsonc
"runtime": {
  "rest": { "enabled": true, "path": "/api" },          // ← the website you just refreshed
  "mcp":  { "enabled": true, "path": "/mcp" }           // ← the agent we're about to call
},
"entities": {
  "Incident":           { "source": { "type": "table",            "object": "dbo.Incident" }, ... },
  "GenerateMitigation": { "source": { "type": "stored-procedure", "object": "dbo.usp_GenerateMitigation" }, ... },
  "DxIndexExists":      { "source": { "type": "stored-procedure", "object": "dbo.usp_DxIndexExists"      }, ... },
  "DxResourcePressure": { "source": { "type": "stored-procedure", "object": "dbo.usp_DxResourcePressure" }, ... },
  "DxDeadlockRecent":   { "source": { "type": "stored-procedure", "object": "dbo.usp_DxDeadlockRecent"   }, ... }
}
```

Spoken cue: *"One DAB config. REST on this line, MCP on that line. Same entities project to both. The website's been talking to the REST side. Now watch the agent talk to the MCP side. And see those `Dx` entries — those are stored procs that read live DMVs and the AppLog ledger. DAB exposes them as MCP tools, no glue code. The agent's about to call them between the corpus search and the model, to validate the runbook against current state."*

> **Cuttable to save 0:10:** drop the read of `dab-config.json` if you're already at 5:10. Source is in the repo; attendees can read it after the session. Spoken cue collapses to the last sentence.

#### 4(b) GHCP Chat agent mode — SKILL drives a six-tool loop (0:50)

> **Plan A (default): run live.** Plan B (recording) is your insurance, not your default.
> The decision happens at the lectern smoke test — before the audience walks in.
> If `Test-AgentPath.ps1 -WithReset` exits 0 in < 130 s on the laptop, you go live.
> If it stalls, 401s, or the dx_* tools don't show up in `copilot mcp list`, you switch to the recording.
> Either branch is invisible to the audience; both end with the same browser tab lighting up in 4(c).

**— Plan A: live execution —**

Copilot Chat: **open a NEW chat** (click the `+` icon — do NOT reuse the chat window from earlier beats). MCP tools only attach to chats opened *after* the MCP server is running, so a fresh chat is mandatory.

**Select the `live-site-sql` agent** from the agent dropdown. The SKILL protocol loads automatically. Confirm MCP server `zavalivesite-sql` is running.

> **Presenter note — what the audience is *actually* watching in Chat Debug view (read once, drop a line on stage only if asked).**
>
> The SKILL body never sits in the system prompt. At startup VS Code parses only the YAML frontmatter and advertises the skill in ~100 tokens (*"live-site-sql — diagnoses Azure SQL incidents..."*) plus three synthetic tools: `load_skill`, `read_skill_resource`, `run_skill_script`. When you hit Enter on "Mitigate incident 5012" the model fires `load_skill("live-site-sql")` **first** — you'll see it as the first row in Chat Debug view, before `read_records`. That's VS Code reading the full 7-step protocol off disk and handing it back to the model as a tool result, *just for this turn*. Without it, the model is staring at a one-liner. With it, the model now has the whole protocol and proceeds to execute it tool by tool.
>
> **If a SQL-engineer audience member asks "why a SKILL file and not just a system prompt?":** *"Two reasons. One, the protocol is portable — same `SKILL.md` byte-for-byte runs under VS Code today and Microsoft Agent Framework tomorrow when this ships as a real app. Two, context-window economics — the model only pays the token cost of the protocol when it needs it. With ten skills registered, default context stays ~1000 tokens instead of ~6000. That's the difference between phi4-mini being viable here and forcing a 128k-context cloud model."*

**Toggle Chat Debug view ON before typing the prompt.** Command Palette → *"Chat: Toggle Chat Debug View"* (or the `…` overflow on the chat input). This is the right surface for a SQL/code-forward audience — they see raw MCP `params` and `result` JSON for every tool call, not paraphrased lines. Zoom the editor up two or three steps (Cmd/Ctrl++) so the back row can read keys. Verified on the lectern laptop during the smoke test (Pre-stage checklist step — see below).

Then type the prompt:

> **Mitigate incident 5012 `@live-site-sql`**

> **Spoken line as you type the `@` — own the design choice.**
>
> *"I'm typing an `@live-site-sql` tag on the prompt. I don't actually need to — the agent file I selected is engineered so the system prompt biases the model to pick this skill on its own, and the skill's description is written to match an on-call engineer's natural phrasing. But on stage, in front of you, I want this deterministic. `@live-site-sql` forces VS Code to load the skill before the first tool call — no probabilistic selection, no surprise. In production with Microsoft Agent Framework you'd just hard-pin the skill into the system prompt and skip this entirely."*

The SKILL tells the agent everything else — the protocol, the diagnostic catalog, the output contract. Tool calls stream live (real DAB MCP invocations against the running Azure SQL container). In Chat Debug view the audience sees the full request/response payload per tool; below is the *shape* of what flows by (use as a mental map, not a script):

```
🔧 read_records(entity='Incident', filter='IncidentId eq 5012')
   → tenant=zava, service=Payroll, sev1, errorCode=1205, build=9114.10212, waitType=LCK_M_X

🔧 hybrid_search(tenantId='zava', question='<engineer note>', errorCode='1205', topK=3)
   → runbook Payroll.7 (distance 0.25)  +  prior incident #4421

🔧 dx_index_exists(SchemaName='dbo', TableName='PayrollBatch', IndexName='ix_payroll_runDate')
   → finding='index_missing'           ← the runbook's recommendation is still relevant

🔧 dx_resource_pressure(WindowMinutes=5)
   → finding='pressure_normal'          ← safe to do online DDL right now

🔧 dx_deadlock_recent(TopN=5)
   → finding='deadlock_present'         ← symptom is current, matches the engineer note

🔧 generate_mitigation(IncidentId=5012, DiagnosticsJson='{ ...all three findings... }')
   → ProposedMitigation written to dbo.Incident; Status → 'mitigating'
```

Agent's natural-language summary streams above the JSON:

> *"I checked three diagnostics before composing the plan: dx_index_exists confirms `ix_payroll_runDate` is missing on `dbo.PayrollBatch`, so step 1 of Runbook Payroll.7 is still relevant. dx_resource_pressure is normal (runnable/sched 0, log write < 1 ms), so an online index build is safe right now. dx_deadlock_recent confirms the symptom is current. Recommendation: (1) create `ix_payroll_runDate ON dbo.PayrollBatch (TenantId, RunDate) INCLUDE (Status, Amount) WITH (ONLINE = ON)`, then (2) reduce per-transaction batch from 25k → 5k rows. Cited Runbook Payroll.7 and prior incident #4421. High confidence."*

> **Stage discipline — do NOT talk over the tool stream.**
> This audience came to read SQL. The 6 tool calls streaming in Chat Debug view *with their `params` and `result` JSON* is the moment they register "the agent is talking to my database, in tools I can read." Speaking over it covers the exact thing they came to see. Stay silent from `🔧 read_records` through `🔧 generate_mitigation`. Pick the line up again when the natural-language summary starts streaming.
>
> **Toggle Chat Debug view OFF before 4(c).** Command Palette → *"Chat: Toggle Chat Debug View"*. Reason: the natural-language summary + citations + diagnostics badge are easier to read in normal view, and 4(c) is about the row lighting up in the browser — you want the chat side to *match* the page, not bury it in JSON. Doing this in one keystroke before alt-tabbing keeps the transition clean.

**— Plan B: pre-recorded fallback —**

If the smoke test failed, play `fallback/beat4_agent_lights_up_page.mp4` from monitor 2. Recording was made running this exact prompt against this exact corpus. Ends *before* the browser refresh, so 4(c) flows in identically. Verbal bridge if needed: *"Quick note — I'm playing back this morning's dry-run for the agent step. Same SQL, same tools, same row update."*

#### 4(c) Alt-tab to the browser — AI panel + diagnostics badge (0:25)

The page has been polling `/api/Incident/IncidentId/5012` every 2 seconds the whole time. By the time you switch tabs, the **AI mitigation panel** has rendered:

- Summary line — names the symptom, the cause, both proposed actions.
- Numbered remediation steps — each tagged with rationale + verify.
- Two clickable citations: **Incident #4421**, **Runbook Payroll.7**.
- **Diagnostics badge**: *"Validated by 3 live diagnostics: index_missing · pressure_normal · deadlock_present."*
- Meta footer: *"Generated by `usp_GenerateMitigation` via MCP · model: phi4-mini (local) · a few seconds ago."*

> **Slow this moment.** After the alt-tab, **count to two silently** before speaking. The browser refresh is the only big visual moment in the entire demo — let the room see the row light up before you start the spoken close. If you start talking immediately the visual gets stepped on.

Spoken close (this is the line that justifies the whole demo):

> *"Same row I wrote in Beat 1. Same DAB. The agent did two jobs at once: it pulled the runbook out of the corpus, and it asked SQL three questions about live state — is the recommended index already there, is the database safe to change right now, is the deadlock still happening. It folded the answers into the prompt and **grounded every step in either a corpus citation or a live diagnostic finding from the same database**. That's the agent loop. That's why the database is in it."*

> **Why the wording changed (presenter note):** the earlier draft said *"the model isn't formatting a template — it's reasoning over corpus and live state."* For incident #5012 specifically that overclaims (see the blockquote below). The grounding line makes the same architectural point without inviting the "isn't it just substitution?" pushback. Keep the new wording; the honesty blockquote handles the rest.

*(Optional one-line MSSQL ext proof if time allows: `SELECT ProposedMitigation FROM dbo.Incident WHERE IncidentId = 5012;` — cuttable.)*

> **Presenter note — "couldn't a template do this?" (READ BEFORE STAGE)**
>
> Yes — for incident #5012 specifically, a T-SQL template over the top runbook hit would produce nearly the same JSON. We engineered the corpus so the runbook match is clean (distance 0.25), only one runbook applies, and all three diagnostic findings line up with the runbook's prerequisites. **The LLM is doing variable substitution on the easy case.**
>
> The model earns its keep on the cases we are *not* showing on stage:
> 1. **Conflicting evidence** — if `dx_resource_pressure='pressure_high'` the model downgrades / re-orders the runbook ("defer the online index build"). A template needs explicit branching for every combination.
> 2. **Novel incidents** — when no runbook is a clean match (top distance > 0.6), the model produces a degraded-confidence plan from the diagnostic findings alone. A template returns "no match found."
> 3. **Heterogeneous runbook shapes** — 200 different runbooks → 200 template adapters, or one model and one output contract.
>
> The architectural claim being demonstrated is *"SQL hosts the model, the agent calls SQL, the page reads the result"* — and that path is the same code on the easy case and the hard case. **If asked from the audience, say so plainly:** *"For this incident a template would work. The architecture earns its keep on the incidents we don't have runbooks for yet — and it's the same proc, the same MCP tool, the same DAB config either way."* Don't pretend the on-stage incident requires reasoning it doesn't require.
>
> Why phi4-mini specifically (not gpt-5.4-mini): the local model proves SQL can host inference at the edge with no network. Beat 5(a) then shows you swap one URL string to flip to Azure OpenAI — same `sp_invoke_external_rest_endpoint` call, same JSON contract, bigger context window. That swap is meaningless if we used AOAI on both sides.

### Beat 5 — Same proc, three URLs: local → AOAI direct → APIM gateway (0:40)

> **Demo-day strategy (2026-05-13):** Beat 5 is **pre-staged, not live**.
> The Hyperscale row #5012 already has `ProposedMitigation` and
> `ProposedMitigation_v2` populated from a `Prep-Cloud.ps1` run earlier
> the same morning. On stage we **read the row** with the MSSQL extension
> against the Hyperscale connection — we do not regenerate. This keeps
> Beat 5 immune to hotel wifi, APIM cold-start latency, and AOAI quota
> hiccups.
>
> Beat 0–4 (laptop, no network) must be bulletproof.
> Beat 5 (Azure overlay) is the "and here's the same code in the cloud"
> coda — visual + narration over pre-staged data.

Two moves: (a) 3-pane editor split showing the *same proc body, three URLs*; (b) one `SELECT` against Hyperscale to prove the row is real.

#### 5(a) Editor split — three procs, one body, three URLs (0:25)

MSSQL ext, **three editor panes side by side**, each open on a different `usp_GenerateMitigation*` file:

| Pane | File | URL inside proc | Credential |
|---|---|---|---|
| Left | `sql/local/sqlscripts/04a_proc_generate_mitigation.sql` | `https://localhost:8444/v1/chat/completions` | *(none — Ollama is local)* |
| Center | `sql/azure/sqlscripts/04a_proc_generate_mitigation_direct.sql` | `https://...openai.azure.com/openai/deployments/gpt-5-4-mini/chat/completions?api-version=...` | `AoaiCred` (Managed Identity) |
| Right | `sql/azure/sqlscripts/04a_proc_generate_mitigation_gateway.sql` | `https://zavalivesite-apim-....azure-api.net/openai/deployments/gpt-5-4-mini/chat/completions?api-version=...` | `ApimCred` (Managed Identity) |

Scroll all three to the `sp_invoke_external_rest_endpoint` block at the bottom. Audience sees: **identical body**, identical hybrid-search call, identical JSON payload, identical `JSON_VALUE($.result.choices[0].message.content)` extraction. **Only the URL line differs.**

Spoken: *"Same proc body. Same hybrid search. Same JSON contract. Three URLs.*

*Left pane — laptop. `phi4-mini` over Ollama on localhost. No network. No bearer token. Same `sp_invoke_external_rest_endpoint`.*

*Middle pane — Azure SQL Hyperscale calling Azure OpenAI directly. `gpt-5-4-mini`, managed identity, no API key anywhere in this script. The DATABASE SCOPED CREDENTIAL says `IDENTITY = 'Managed Identity'` — SQL gets a bearer from Azure AD using the logical server's system-assigned identity and injects it as `Authorization: Bearer ...` into the outbound request.*

*Right pane — same Hyperscale, same `gpt-5-4-mini`, but now routed through APIM. The URL is `apim-...azure-api.net` instead of `openai.azure.com`. APIM is configured with the GenAI gateway policy: it runs Azure Content Safety (Hate / Violence / SelfHarm / Sexual classifiers on `EightSeverityLevels`) over the user message, enforces a token-per-minute quota with `llm-token-limit`, emits per-call token telemetry with `llm-emit-token-metric`, and re-authenticates to AOAI using APIM's own managed identity. SQL doesn't know any of that. SQL sees the same JSON contract come back. Hyperscale plus APIM gives us governance — content safety, quotas, observability — without changing one line of this proc body."*

#### 5(b) Read the row on Hyperscale (0:10)

Click the **Hyperscale** connection in MSSQL ext (already green from pre-stage). New query window. Type live:

```sql
SELECT  IncidentId,
        JSON_VALUE(ProposedMitigation,    '$.summary') AS direct_summary,
        JSON_VALUE(ProposedMitigation_v2, '$.summary') AS gateway_summary
FROM    dbo.Incident
WHERE   IncidentId = 5012;
```

F5. Two columns come back — both populated, both ~1-2 sentence summaries, structurally identical, content essentially the same (same prompt + same model + same retrieval).

Spoken: *"I ran `Prep-Cloud.ps1` against this Hyperscale server this morning before the talk. It deployed the Bicep, populated the corpus, generated embeddings via `text-embedding-3-small`, then executed both procs against incident #5012. What you're seeing is what those procs wrote into this row earlier today. The left summary went through AOAI direct; the right summary went through APIM with content safety and quota in front of it. Both came from `gpt-5-4-mini` running in `eastus2`. Same row. Same proc."*

#### 5(c) Spoken close (0:05)

*"One product. Three surfaces. Container on the laptop with Ollama. Hyperscale calling Azure OpenAI directly. Hyperscale calling Azure OpenAI through an APIM GenAI gateway with content safety. Same `sp_invoke_external_rest_endpoint`. Same JSON contract. Three URLs."*

---

## Files needed (pre-staged)

```
presentations/build2026/BRK223/sql/local/
  sqlscripts/
    00_setup.sql                    # CREATE DATABASE zavalivesitedb
    01_schema.sql                   # tables, JSON indexes, EXTERNAL MODEL OllamaMxbai (embeddings),
                                    #   usp_HybridSearch, usp_LogTimeline. Includes ix_runbook_tags JSON index for Beat 2 runbook side.
    02_seed_corpus.sql              # ~300 IncidentArchive rows (incl. anchor #4421) + 20 Runbooks (incl. Payroll.7),
                                    #   embedded inline via OllamaMxbai (1-3 min runtime).
    03_vector_indexes.sql           # DiskANN ×3 — archive (definitely builds), runbook + incident (best-effort).
    04a_proc_generate_mitigation.sql # usp_GenerateMitigation — wraps sp_invoke against https://localhost:8444/v1/chat/completions (phi4-mini).
                                    #   Accepts @DiagnosticsJson and folds it into the prompt as ground truth.
                                    #   DAB exposes this as the MCP execute_GenerateMitigation tool.
    04b_diagnostic_procs.sql        # The three Dx procs:
                                    #   usp_DxIndexExists, usp_DxResourcePressure, usp_DxDeadlockRecent.
                                    #   Plus the synthetic dbo.PayrollBatch table (deployed WITHOUT ix_payroll_runDate —
                                    #   that's the stage state so dx_index_exists returns 'index_missing').
    05_create_incident.sql          # Beat 1 — the five-feature INSERT (IncidentId 5012)
    06_hybrid_search.sql            # Beat 2 — EXEC usp_HybridSearch; plan shows Vector Index Seek (DiskANN) + JSON Index Seek (ix_runbook_tags) composed in one statement.
    07_log_timeline.sql             # Beat 3 (stub mode for local; ADLS block commented for cloud)
presentations/build2026/BRK223/sql/azure/
  sqlscripts/
    03_external_model.sql                       # MI-based DSCs + EXTERNAL MODEL AoaiTextEmbed3Small (embeddings only)
    04a_proc_generate_mitigation_direct.sql     # usp_GenerateMitigation_AoaiDirect — calls AOAI directly via AoaiCred (MI)
    04a_proc_generate_mitigation_gateway.sql    # usp_GenerateMitigation_AoaiGateway — calls AOAI through APIM via ApimCred (MI)
  bicep/                                         # Hyperscale + AOAI + APIM + Content Safety + MI role grants
  apim-policies/aoai-api.xml                     # authentication-managed-identity + llm-token-limit + llm-content-safety + llm-emit-token-metric
  Prep-Cloud.ps1                                 # Idempotent: deploy Bicep, materialize schema/corpus on Hyperscale,
                                                 #   EXEC both procs against incident #5012, verify both columns populated.
  web/
    index.html                       # Zava On-Call Console — single static page
    styles.css                       # ~30 lines
    app.js                           # fetch + 2-sec polling against DAB REST; ?dab=local|cloud switch
    README.md                        # how to serve and open
  skills/
    live-site-sql/
      SKILL.md                       # Beat 4 — the agent-loaded triage protocol (attach via #file:)
  dab/
    dab-config.json                  # entities + roles + REST + MCP enabled (container target)
    dab-config.cloud.json            # same shape, Hyperscale + AOAI external models
    .env                             # MSSQL_CONNECTION_STRING for container DAB
    .env.cloud                       # MSSQL_CONNECTION_STRING for Hyperscale DAB
  .vscode/
    mcp.json                         # zavalivesite-sql, type:http, url: http://localhost:8765/mcp
                                     #   (DAB MCP endpoint pinned by Aspire AppHost — apphost.cs WithHttpEndpoint(8765, 5000))
  slides/
    BRK223_intro.pptx                # title + Q&A backup slide (cloud topology)
```

### Beat 2 schema setup

For the composed-plan demo to be reliable, `01_schema.sql` must:

- Create JSON Index on `IncidentArchive.AlertPayload` (`$.tenantId`, `$.service`) and on `Incident.Tags`.
- Create **`ix_runbook_tags`** on `dbo.Runbook(Tags)` for (`$.service`, `$.tags`) — this is the JSON Index Seek the audience sees in Beat 2.
- No JSON index on `IncidentArchive.Tags($.errorCode)` is needed: the archive query is DiskANN-driven, so a JSON index there would not be picked by the optimizer (the predicate runs as a residual filter on the bookmark side).

`02_seed_corpus.sql` populates `IncidentArchive` (~301 anchor rows incl. #4421) + `Runbook` (20, incl. Payroll.7); `03_vector_indexes.sql` builds DiskANN; `03b_runbook_chunks.sql` chunks runbooks and embeds them. Beat 2's plan should always show both **Vector Index Seek** on `vec_archive_embedding` *and* **Index Seek** on `ix_runbook_tags`. Verify in dry run.

### `.vscode/mcp.json` (the wire)

```json
{
  "servers": {
    "zavalivesite-sql": {
      "type": "http",
      "url": "http://localhost:8765/mcp"
    }
  }
}
```

DAB runs as a container managed by the Aspire AppHost (`dotnet/AppHost/apphost.cs` — pinned to host port **8765** via `WithHttpEndpoint(port: 8765, targetPort: 5000)`). VS Code Copilot Chat connects over HTTP; it is **not** spawning DAB as a subprocess. `runtime.mcp.enabled = true` in `dab-config.json`. Permissions use role `anonymous` (the proxy is loopback-only — `127.0.0.1:8765`).

## If the laptop reboots (rehearsal or stage)

Everything is already pre-staged on disk and inside the SQL container. You
do **not** need a full bootstrap. Run:

```powershell
cd c:\bwsql\presentations\build2026\BRK223\sql\local
.\Build.ps1 -Fast      # auto-launches Docker Desktop, starts the SQL container if stopped, probes SQL on localhost,14330. ~10–30 s on a warm box.
.\Prep-Demo.ps1        # full pre-show sequence (verify → reset → warmup AI → Start-LiveSite)
```

If you only need the live site back (state is fine, AI warm, no rehearsal
reset wanted), skip `Prep-Demo.ps1` and run `.\Start-LiveSite.ps1` directly.

**Never run `.\Build.ps1 -Force` on stage or between rehearsals** — it
tears down the SQL container, re-pulls images, re-runs
`deploy-prestage.ps1` (drops + recreates `zavalivesitedb`), and reinstalls
Ollama/Caddy/models. Reserved for "the world is broken, I have 15 min."

## If something is broken — escalation ladder

Pick the lowest rung that matches the symptom. Each rung is idempotent.

| # | Symptom | Command(s) | Time | Touches |
|---|---|---|---|---|
| 1 | Browser wrong / Aspire died, SQL + AI fine | `.\Stop-LiveSite.ps1` → `.\Start-LiveSite.ps1` | ~30 s | Aspire AppHost + DAB + Blazor |
| 2 | Demo state stuck (Incident row, leftover Beat-2c JSON index) | `.\Reset-ForBeat2.ps1` | ~5 s | Deletes Incident #5012, drops Beat-2c index. Corpus + runbooks + procs preserved. |
| 3 | `usp_GenerateMitigation` times out / `sp_invoke` fails | `.\Restart-AiServices.ps1` | ~30–60 s | Restarts Ollama + Caddy inside container. Models stay on disk. |
| 4 | Models corrupt / Caddy CA broken | `.\Prepare-AiContainer.ps1` | ~3–5 min | Reinstalls Ollama + Caddy, re-pulls `mxbai-embed-large` + `phi4-mini`, retrusts CA, restarts sqlservr. |
| 5 | Schema / embeddings / procs wrong | `.\deploy-prestage.ps1` | ~1–3 min | Drops + recreates `zavalivesitedb`, redeploys 00→04b, reseeds corpus (~301 archive + 20 runbooks). |
| 6 | SQL won't start, container hosed | `.\Build.ps1 -Force` | ~10–15 min | `docker rm -f` + recreate container, re-pull SQL image, full AI prep, full SQL deploy, dotnet clean build. |
| 7 | Cold machine / new image / nothing on disk | `.\Build.ps1` | ~15–30 min (network-bound) | Full bootstrap from a freshly-imaged Windows box. |
| 8 | T-minus 2 min and still broken | Open `fallback/beat4_agent_lights_up_page.mp4` paused on monitor 2 | instant | Plan B — talk over the recording. |

Rules:
- **Start at rung 1, stop at the first thing that fixes it.** Don't skip ahead.
- **Never jump straight to rung 6.** It destroys all seeded state and re-pulls images over hotel wifi.
- **Inside 5 minutes of going on stage and stuck above rung 3 → commit to fallback recordings.** Don't gamble on a 5-minute fix that might become 15.

## Pre-stage checklist (run before doors open, in order)

Two scripted steps cover most of the work, then a short manual residual.

### Step 1 — `.\Build.ps1` (one-time / cold-machine bootstrap)

Run once on a freshly-imaged box, or when you want to rebuild the world from scratch. Idempotent — every step probes "is it already done?" before doing work, so re-running on a warm box is safe and fast.

**Two convenience flags:**

- `.\Build.ps1 -Fast` — probes only, no work. Implies `-SkipWinget -SkipAi -SkipDeploy -SkipDotnet`. Use on a known-good machine to verify health in ~10–30 s.
- `.\Build.ps1 -Force` — tear down and rebuild everything this script owns: re-pulls images, `docker rm -f` + recreate `azsql-zavalivesite`, re-runs `Prepare-AiContainer.ps1`, re-runs `deploy-prestage.ps1` (drops + recreates `zavalivesitedb`), `dotnet clean` + `--no-incremental` build. Does NOT touch winget-installed OS tools (no-op anyway). ~10–15 min. Use after a corrupted state or a SQL image bump.

What it does (13 internal steps; full detail in [Build.ps1](Build.ps1) header):

1. winget installs: Docker Desktop, Node.js LTS, .NET 10 SDK, sqlcmd, Azure CLI.
2. Auto-launches Docker Desktop and waits up to 5 min for the daemon.
3. Interactive `az login` if no AAD session, then ACR token for the SQL image pull.
4. `copilot login` probe-then-prompt (Copilot CLI 1.0.43, GitHub device flow).
5. Pulls DAB image (`mcr.microsoft.com/azure-databases/data-api-builder:2.0.0-rc`).
6. Pulls SQL image (`sqlbuilds.azurecr.io/mssql-p-adhoc/mssql-server/developer-edition:9114_10212_3`) and creates `azsql-zavalivesite` on **port 14330**.
7. Calls `Prepare-AiContainer.ps1` — installs Ollama + Caddy *inside* the SQL container, pulls `mxbai-embed-large` (embeddings) and `phi4-mini` (chat), trusts the Caddy CA in SQLPAL, restarts sqlservr.
8. Calls `deploy-prestage.ps1` — bootstraps `sqladmin` login, runs `sqlscripts\00_setup.sql` → `sqlscripts\04a_proc_generate_mitigation.sql` → `sqlscripts\04b_diagnostic_procs.sql` (DB + schema + corpus + embeddings + the three `Dx` procs and synthetic `dbo.PayrollBatch` deployed *without* `ix_payroll_runDate`; ~301 archive + 20 runbook rows).
9. `dotnet restore` + `dotnet build` for `ZavaLiveSite.Web` to warm the build cache.

**One manual thing Build.ps1 prints at the end and cannot do for you:**

- Enable Anthropic Claude Opus 4.7 at <https://github.com/settings/copilot/features> (web checkbox, tied to your GitHub account).

### Step 2 — `.\Prep-Demo.ps1` (every show, before doors open)

Sequences four scripts in order, checks each exit code, stops on the first failure, and prints a per-step OK/FAIL/SKIPPED summary. Run this every show; re-run with `-Skip*` flags if you only need part of it.

What it does:

1. **`Verify-Build.ps1`** — probes Docker, container, SQL responsive on `localhost,14330`, Ollama + Caddy alive, models loaded, DAB image cached, copilot CLI logged in. Auto-recovers Docker / container / AI services where it can.
2. **`Reset-ForBeat2.ps1`** — truncates `Incident` (so the page starts at "no row yet"). Leaves `IncidentArchive` (~301) and `Runbook` (20) intact. (No JSON index to drop — Beat 2 no longer builds one live.)
3. **`Warmup-Ai.ps1`** — one chat call against `phi4-mini` (cold ~80s, warm ~15s) and one embedding call against `mxbai-embed-large`. Combined with `OLLAMA_KEEP_ALIVE=-1` both models stay resident for the whole talk. Re-run with `.\Prep-Demo.ps1 -SkipVerify -SkipReset -SkipStart` if you've been idle > 10 min during rehearsal.
4. **`Start-LiveSite.ps1`** — launches the Aspire AppHost (`dotnet run apphost.cs`). Brings up the DAB container on `:8765` + Blazor WASM `web` resource on `:8080`. Aspire dashboard is disabled. Logs in `dotnet/AppHost/apphost.{out,err}.log`.

**Run with `-DryRun` once before doors open** — adds a 5th step (`Test-AgentPath.ps1`, ~2 min: full Beat-4 round trip Copilot CLI → Claude Opus 4.7 → MCP → DAB → `usp_GenerateMitigation`) plus a 6th (re-run `Reset-ForBeat2.ps1` so on-stage state is clean again).

### Step 3 — Manual checks Prep-Demo can't do for you

Quick eyeball pass after Step 2 succeeds:

1. **MSSQL ext connections green** for both `localhost,14330` (`zavalivesitedb` DB) and the Azure SQL Hyperscale database used in Beat 5 (if you're running the live cloud flip — see the Beat 5 callout above).
2. **`OPENROWSET` warm:** run `07_log_timeline.sql` once to prime the ADLS cache.
3. **Beat 2 dry run:** execute `06_hybrid_search.sql` once. In the Plan tab, confirm both **Vector Index Seek** on `vec_archive_embedding` *and* **Index Seek** on `ix_runbook_tags` are present. If either is missing, the demo is dead — do not go on stage.
4. **Enable Actual Plan** in MSSQL editor toolbar (icon next to Run). Leave it on for the whole demo.
5. **MCP: List Servers** → `zavalivesite-sql` shows **Running**. Confirm the tool list contains `read_records`, `create_record`, `update_record`, `delete_record`, `aggregate_records`, `execute_entity`, `describe_entities`, plus the **six** custom stored-proc tools: `hybrid_search`, `log_timeline`, `generate_mitigation`, **`dx_index_exists`**, **`dx_resource_pressure`**, **`dx_deadlock_recent`**. If any are missing, bounce DAB: `.\Stop-LiveSite.ps1` then `.\Start-LiveSite.ps1`. If still down, **Start** it from the MCP menu.
6. **Lectern smoke test (Beat 4 go/no-go).** Run `.\Test-AgentPath.ps1 -WithReset`. Acceptance: exit 0 in < 130 s, transcript ends with an assistant message that mentions all three diagnostic findings (`index_missing`, `pressure_normal`, `deadlock_present`). If exit ≠ 0, time > 130 s, or any finding is missing, **commit to Plan B** for Beat 4 and open `fallback/beat4_agent_lights_up_page.mp4` paused on monitor 2 *now* — do not change posture mid-talk.
    - **After smoke, click `+` for a brand-new chat** in VS Code Copilot Chat (do NOT reuse the smoke chat — MCP tool attachment can go stale across sends). New chat → select agent `live-site-sql` from the dropdown (auto-loads SKILL + MCP tools) → pre-fill `Mitigate incident 5012 @live-site-sql` if Plan A; otherwise leave blank.
    - **Verify Chat Debug view toggles** on the lectern VS Code build: Command Palette → *"Chat: Toggle Chat Debug View"*. Confirm raw MCP `params` and `result` JSON render readably for at least one tool call (run the smoke test against the new chat if needed to populate it). Leave it ON for Plan A; if the command is missing on this build, fall back to the normal view — the streamed `🔧 tool(...) → finding=...` lines are still strong for this audience. **Zoom the editor up two or three steps** (Cmd/Ctrl++) so the back row can read JSON keys.
    - *Tip:* `Test-AgentPath.ps1` exercises the exact same path the live agent will take — same SKILL protocol, same six MCP tools, same prompt. If the script passes, the live demo will pass; the in-VS-Code chat is just the visual surface.
7. **Pre-position SQL tabs** (`05_create_incident`, `06_hybrid_search`, `07_*`), cursors on the `EXEC` line for each. Close all stale `.sqlplan` tabs.
8. Slide deck on screen 1; VS Code on screen 2.

### Demo helper scripts (during rehearsal and on stage)

- `.\Reset-Incident.ps1` — deletes incident #5012 only. Lighter than `Reset-ForBeat2.ps1` — use between Beat-1 rehearsals.
- `.\Insert-Incident.ps1` — runs `sqlscripts\05_create_incident.sql` (the five-feature INSERT) via `sqlsim`. The page picks it up on its own (2-second poll); click **Refresh** to force it.
- `.\Generate-Mitigation.ps1` — runs `EXEC dbo.usp_GenerateMitigation @IncidentId = 5012` (same proc the Beat 4 MCP `GenerateMitigation` tool calls). Use during rehearsal to light up the mitigation card without driving Copilot Chat.

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| **Beat 2 plan missing an operator** | Step 3 manual check #3 — confirm both **Vector Index Seek** on `vec_archive_embedding` and **Index Seek** on `ix_runbook_tags` appear in dry run. If either is missing, recompile (`sp_recompile 'dbo.usp_HybridSearch'`) and re-probe; if still wrong, do not go on stage with Beat 2. |
| **Plan tab clutter** | Step 3 manual check #7 closes stale `.sqlplan` tabs. |
| Copilot Chat dead air / 401 / stall during Beat 4 | **Decision happens at the lectern smoke test (Step 3 manual check #6), not on stage.** If smoke fails, switch to Plan B recording at `fallback/beat4_agent_lights_up_page.mp4` — the browser still lights up because the row was already updated by the dry-run. Verbal bridge ready (see Beat 4(b)). |
| MCP server not started when chat opens | Step 3 manual check #5 — verify **MCP: List Servers** shows Running. If down at lectern, that alone triggers Plan B in Beat 4. |
| Copilot policy blocks agent tool use on stage wifi | Sign in before doors open; smoke prompt at lectern (Step 3 manual check #6). Failure → Plan B. |
| ADLS cold cache eats Beat 3 budget | Pre-warm in Step 3 manual check #2; fallback: local parquet inside the Azure SQL container |
| Ollama/Caddy cold start | Step 2 (`Prep-Demo.ps1` runs `Warmup-Ai.ps1`). Failure here also triggers Plan B in Beat 4 (since the proc can't reach the model). |
| Hotel wifi blocks Azure SQL Hyperscale in Beat 5(b) | Beat 5(a) is local files only — runs regardless. For 5(b), if the Hyperscale connection won't open, show `fallback/beat5_three_panes_and_select.mp4` instead; spoken close (5c) unchanged. |
| MSSQL ext picks wrong batch on F5 | Pre-position cursor; one `GO`-separated statement per visible script |
| DAB MCP endpoint unreachable mid-demo | `MCP: List Servers` → Restart `zavalivesite-sql`; if Aspire AppHost died, `Stop-LiveSite.ps1` then `Start-LiveSite.ps1`; if mid-Beat-4 and not recoverable in <10s, switch to Plan B recording. |

## Fallback recordings

Record before travel; have ready under `presentations/build2026/BRK223/sql/fallback/` (see `fallback/README.md` for exact recording recipe and prompts).

- `beat0_open_website.mp4` — nice-to-have
- `beat1_insert_then_refresh.mp4` — nice-to-have
- `beat2_slow_to_fast.mp4` — high priority (plan visualizer + `@mssql` + retune is live-risk-prone)
- **`beat4_agent_lights_up_page.mp4` — MANDATORY.** Plan B for Beat 4. Open in VLC paused on monitor 2 before doors. Includes the chat conversation through to the final mitigation answer; ends *before* the browser tab is shown so 4(c) flows in identically.
- `beat5_three_panes_and_select.mp4` — nice-to-have. Captures the 3-pane editor split scroll + the Hyperscale `SELECT JSON_VALUE(...) FROM Incident WHERE IncidentId=5012` returning both `direct_summary` and `gateway_summary`.
