# BRK223 — Azure variant

Sibling to `../local/`. Same incident-response demo, but the **AI side**
moves off in-container Ollama and onto:

- **Azure SQL Hyperscale** (logical server + database, vector + JSON enabled)
- **Azure OpenAI** — `gpt-4o-mini` (chat) + `text-embedding-3-small` (1536-dim embeddings)
- **Azure API Management** — fronted as a **GenAI Gateway**, with
  `llm-content-safety` (Hate + Violence threshold 4, EightSeverityLevels,
  `shield-prompt="true"`), `llm-token-limit` per subscription, and
  `llm-emit-token-metric` to Application Insights.
- **Azure AI Content Safety** account, wired into the APIM policy via
  Managed Identity (resource id `https://cognitiveservices.azure.com`,
  `Cognitive Services User` role).

The corpus (`IncidentArchive`, `Runbook`, etc.) is identical to the
local stack — only the model endpoints differ. Beat 5 of the demo
shows the **same proc body** with three different
`sp_invoke_external_rest_endpoint` targets side-by-side:

| Pane | File | URL |
|---|---|---|
| Local  | `../local/sqlscripts/04a_proc_generate_mitigation.sql`           | `https://localhost:8445/v1/chat/completions` (Caddy → Ollama phi4-mini) |
| Azure direct  | `sqlscripts/04a_proc_generate_mitigation_direct.sql`     | `https://<aoai>.openai.azure.com/openai/deployments/gpt-4o-mini/chat/completions?api-version=...` |
| Azure gateway | `sqlscripts/04a_proc_generate_mitigation_gateway.sql`    | `https://<apim>.azure-api.net/openai/deployments/gpt-4o-mini/chat/completions?api-version=...` (with `Ocp-Apim-Subscription-Key`) |

Audience reads three URLs; one proc body. Live `SELECT JSON_VALUE(...)`
against Hyperscale row 5012 closes the beat.

## Layout

```
azure/
  Prep-Cloud.ps1                 # idempotent: deploy Bicep -> deploy schema/corpus -> INSERT 5012 -> EXEC both procs
  sqlscripts/
    00_setup.sql                                  # CREATE DATABASE / vector + JSON prereqs (Hyperscale already provisioned by Bicep)
    01_schema.sql                                 # mirrors local/01_schema.sql but EXTERNAL MODEL = AoaiTextEmbed3Small
    02_seed_corpus.sql                            # same corpus, embedded via AoaiTextEmbed3Small
    03_external_model.sql                         # CREATE EXTERNAL MODEL AoaiTextEmbed3Small (API_FORMAT='Azure OpenAI', MODEL_TYPE=EMBEDDINGS)
    04a_proc_generate_mitigation_direct.sql       # usp_GenerateMitigation_AoaiDirect  -> sp_invoke -> AOAI directly
    04a_proc_generate_mitigation_gateway.sql      # usp_GenerateMitigation_AoaiGateway -> sp_invoke -> APIM -> AOAI
    04b_diagnostic_procs.sql                      # same as local (no AI deps)
    05_create_incident.sql                        # INSERT row 5012
  bicep/
    main.bicep                     # RG-scope orchestration
    modules/
      sql.bicep                    # logical server + Hyperscale db + firewall + AAD admin
      openai.bicep                 # AOAI account + two deployments
      contentsafety.bicep          # Azure AI Content Safety account
      apim.bicep                   # APIM Developer SKU + system-assigned MI + backends + API + policy attachment
      roles.bicep                  # MI role assignments (Cognitive Services User) on AOAI + CS
      keyvault.bicep               # optional KV for AOAI key fallback
  apim-policies/
    aoai-api.xml                   # inbound: llm-token-limit + llm-content-safety + llm-emit-token-metric + set-backend-service + auth (MI)
```

## Target Azure environment

| Setting | Value |
|---|---|
| Subscription | `0efc44aa-c965-420f-aac4-fff305dbcc97` (AzureSQL_bobward) |
| Tenant | `72f988bf-86f1-41af-91ab-2d7cd011db47` |
| Resource group | `zavalivesiterg` |
| Region | `eastus2` |

## Deploy

Before the first `-ReDeploy` run, export the three values Bicep needs.
The checked-in `bicep/params.json` has empty placeholders for these on
purpose — `Prep-Cloud.ps1` passes them as `-p name=value` overrides so
no PII lands in source.

```powershell
$env:BRK223_PUBLISHER_EMAIL         = '<upn for APIM publisher email>'
$env:BRK223_SQL_AAD_ADMIN_LOGIN     = '<aad admin UPN>'
$env:BRK223_SQL_AAD_ADMIN_OBJECT_ID = '<aad admin object id>'

.\Prep-Cloud.ps1 -ReDeploy   # first run only; re-runs Bicep then everything else
.\Prep-Cloud.ps1             # subsequent runs reuse the existing deployment
```

Probes existing resources, only creates what's missing, then deploys
schema/corpus to Hyperscale and executes both procs to populate
`dbo.Incident.ProposedMitigation` (direct) and `ProposedMitigation_v2`
(gateway) for row 5012 before showtime.

## Why two procs

Beat 5 has **15 seconds of editor reading time**. The audience must see
that the *only* difference between direct and gateway is the URL +
header — proving that the GenAI Gateway is a drop-in policy layer, not
a code rewrite. Same prompt, same response shape, same Hyperscale
write. The gateway version is the one that gets policed by Content
Safety, rate-limited by `llm-token-limit`, and metered into App
Insights via `llm-emit-token-metric`.
