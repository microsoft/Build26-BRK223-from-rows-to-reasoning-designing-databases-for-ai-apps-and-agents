---
name: live-site-sql
description: Live-site triage playbook for Azure SQL on-call incidents — protocol, diagnostic catalog (dx_index_exists, dx_resource_pressure, dx_deadlock_recent), hybrid search, and grounded mitigation generation. Loaded by the live-site-sql custom agent. Use when the user asks to mitigate, triage, or diagnose a Zava SQL incident.
---

# Live-Site SQL Triage — Skill

> Playbook the agent loads when an Azure SQL on-call incident lands.
> Owner: Bob Ward · Build 2026 BRK223
> Read this end-to-end before you call any tool. The protocol below is the
> sequence — do not reorder it.

---

## When to invoke

Trigger this playbook when the user says any of:
- "Mitigate incident `<N>`"
- "Triage SQL incident `<N>`"
- "What's wrong with incident `<N>`?"
- The user attaches an incident page and asks for help

Symptom keywords to recognize: deadlock, Msg 1205, LCK_M_*, PAGELATCH_*,
WRITELOG, plan regression, log full, tempdb pressure, CPU spike.

## Protocol — run in this exact order

1. **Read the incident.** Call MCP tool `read_records` on `Incident`
   filtered by `IncidentId eq <N>`. Capture: `TenantId`, `Service`,
   `Severity`, `EngineerNote`, `Tags` (errorCode, build, waitType),
   `AlertPayload`.

2. **Retrieve evidence.** Call `hybrid_search` with `Question`
   set to the **verbatim** `EngineerNote` from step 1. Do NOT
   summarize, paraphrase, extract keywords, or shorten it — pass
   the full original string byte-for-byte. The embedding model is
   trained on natural prose; a hand-crafted summary degrades recall.
   Also pass the tenant id, the error code from `Tags`, and
   `topK=3`. Read every returned row. The result set has rows
   with `source` ('incident' | 'runbook'), `id`, `title`, `body`,
   `distance`. Lower distance = better match.

3. **For each runbook recommendation, validate it against current state.**
   Runbooks tell you what *usually* works. Diagnostics tell you whether
   the recommended action is *currently appropriate*. Use the catalog
   below to pick which diagnostic answers each recommendation.

4. **Always run `dx_resource_pressure` once.** Online DDL (rebuild,
   create index online) and large UPDATEs are unsafe when log write
   percentage or CPU is high. Gate any "rebuild / batch / online"
   action in the runbook on the result of this diagnostic.

5. **Always run `dx_deadlock_recent` once when the symptom is a
   deadlock or `LCK_M_*` wait.** Confirms the symptom is current,
   not historical noise.

6. **Compose the mitigation.** Call `generate_mitigation` with:
   - `IncidentId` = the incident
   - `DiagnosticsJson` = a JSON object aggregating every diagnostic
     result you collected in steps 3-5. Shape:
     ```json
     {
       "dx_index_exists":      { "finding": "...", ... },
       "dx_resource_pressure": { "finding": "...", ... },
       "dx_deadlock_recent":   { "finding": "...", ... }
     }
     ```
     If you ran a diagnostic more than once with different params,
     pass an array under that key.

7. **Report back.** Summarize for the human: which diagnostics fired,
   what they found, how that changed the proposed plan vs the runbook
   text. Cite incident ids and runbook ids inline.

---

## Diagnostic catalog (MCP tools)

Each diagnostic returns a single result row whose first column is
`finding` — a short kebab-case verdict — followed by evidence columns.

### `dx_index_exists` — has the runbook's recommended index already been applied?

- **Tool:** `dx_index_exists`
- **Params:** `SchemaName` (e.g. `dbo`), `TableName` (e.g. `PayrollBatch`),
  `IndexName` (the exact name the runbook recommends, e.g. `ix_payroll_runDate`).
- **Findings:**
  - `index_present` → the runbook's step is **already done**. Skip it,
    proceed to the next runbook step, and call this out in the rationale.
  - `index_missing` → the runbook's step is still relevant.
  - `table_not_found` → flag in confidence notes; do not fabricate.

### `dx_resource_pressure` — is the database under pressure right now?

- **Tool:** `dx_resource_pressure`
- **Params:** `WindowMinutes` (default 5).
- **Findings:**
  - `pressure_high` → log write or CPU > 80% in the window. **Do not
    propose online DDL or large batched UPDATEs right now.** Reorder the
    plan so heavy operations are scheduled, not applied immediately.
  - `pressure_moderate` → 50–80%. Note in rationale; prefer smaller batches.
  - `pressure_normal` → < 50%. Online operations are safe.

### `dx_deadlock_recent` — is the deadlock symptom still active?

- **Tool:** `dx_deadlock_recent`
- **Params:** `TopN` (default 5).
- **Findings:**
  - `deadlock_present` → confirms the symptom; cite the most recent
    `event_time_utc` in `summary`.
  - `no_deadlock_history` → the symptom may already be mitigated;
    set `confidence.overall` no higher than `medium` and say so.

---

## Output contract (what `generate_mitigation` returns through you)

You hand the result of `generate_mitigation` to the user verbatim. It is a
JSON object:

```jsonc
{
  "summary":       "<2-3 sentences naming the incident, error code, object, root cause, primary fix>",
  "cited_actions": [{ "action": "...", "source": "incident #<id> | runbook <id>" }],
  "rollout_plan":  [{ "step": 1, "action": "...", "rationale": "...", "verify": "..." }],
  "blast_radius":  { "tenants_affected": <int>, "active_incidents_same_service": <int>, "summary": "..." },
  "confidence":    { "overall": "low|medium|high", "notes": "..." }
}
```

Then add a one-paragraph human-readable summary above the JSON that
references the diagnostics: *"I checked diagnostics X, Y, Z. X said
`<finding>` so I `<adjustment>`. The recommended action is …"*

---

## What NOT to do

- Do not call `generate_mitigation` before running the diagnostics in
  steps 3-5. The proc folds your diagnostics into the model prompt;
  if you skip them the model loses the live-state grounding.
- Do not invent diagnostic findings. If `dx_index_exists` returns
  `table_not_found`, say so — do not assume the index does or doesn't
  exist.
- Do not propose `KILL`, `DBCC FREEPROCCACHE`, `ALTER DATABASE SET <...>`,
  or anything destructive without an explicit human-approval step in
  `rollout_plan`.
- Do not name SQL ERRORLOG, SSMS, Profiler, or any on-box file —
  this is Azure SQL Database; those don't exist for the customer.
- Do not propose more than 5 rollout steps. Real on-call plans are short.
