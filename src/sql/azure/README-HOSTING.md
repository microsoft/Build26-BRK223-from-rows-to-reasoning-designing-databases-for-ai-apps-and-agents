# BRK223 — Azure-hosted lift-and-shift

This folder is the "cloud version" of the laptop demo. The intent is a
**true** lift-and-shift:

| Layer            | Laptop (`sql/local`)              | Cloud (`sql/azure`)                |
|------------------|------------------------------------|-------------------------------------|
| SQL              | SQL Server 2025 container          | Azure SQL Hyperscale HS_Gen5_2      |
| Embeddings + Chat| Foundry Local (`localhost:5273`)   | Azure OpenAI via APIM gateway       |
| DAB              | container on host:8765 (Aspire)    | ACA app, system-MI → SQL            |
| Blazor WASM      | localhost:8080 (Aspire)            | Static Web App                      |
| MCP transport    | HTTP via DAB `/mcp`                | HTTPS via DAB `/mcp` (cross-origin) |

Same entity names, same MCP tool names, same proc names (`usp_GenerateMitigation`,
`usp_HybridSearch`, …), same column the page reads
(`Incident.ProposedMitigation`). The Blazor page and the GHCP MCP agent
cannot tell which copy they're talking to — that's the entire demo point.

The two `..._v2` artifacts (`usp_GenerateMitigation_AoaiDirect` /
`usp_GenerateMitigation_AoaiGateway` + `ProposedMitigation_v2`) remain in
place; they exist to support **Beat 5's** "same body, different URL"
direct-vs-gateway side-by-side. The lift-and-shift proc above
(`dbo.usp_GenerateMitigation`) writes to the unsuffixed
`ProposedMitigation` column so consumers don't have to know about the
gateway split.

---

## Two scripts, two phases

```
Prep-Cloud.ps1            ← base stack: SQL + AOAI + APIM + Content Safety + data + procs
Prep-Cloud-Hosting.ps1    ← THIS folder: ACR + ACA DAB + SWA (Blazor)
```

Run them in order on a fresh subscription. Both are idempotent.

`Prep-Cloud.ps1 -ReDeploy` requires three env vars (no defaults in source):

```powershell
$env:BRK223_PUBLISHER_EMAIL         = '<upn for APIM publisher email>'
$env:BRK223_SQL_AAD_ADMIN_LOGIN     = '<aad admin UPN>'
$env:BRK223_SQL_AAD_ADMIN_OBJECT_ID = '<aad admin object id>'

cd presentations\build2026\BRK223\sql\azure
.\Prep-Cloud.ps1 -ReDeploy      # ~15-20 min on a cold subscription
.\Prep-Cloud-Hosting.ps1        # ~5-7 min once ACR is warm
```

Tear-down (does NOT touch SQL/AOAI/APIM/CS — those stay for cost reasons):

```powershell
.\Teardown-Cloud-Hosting.ps1
```

Full tear-down: `az group delete -g zavalivesiterg --yes`.

---

## What gets created (hosting only)

| Resource                    | Name pattern                | Purpose                                              |
|-----------------------------|-----------------------------|------------------------------------------------------|
| Azure Container Registry    | `zavalivesiteacr<sfx>`            | Hosts the DAB image (built via `az acr build`).      |
| Container Apps environment  | `zavalivesite-aca-env-<sfx>`      | Consumption profile.                                 |
| Container App (DAB)         | `zavalivesite-dab-<sfx>`          | DAB, system-MI, HTTPS ingress on port 5000.          |
| Static Web App              | `zavalivesite-web-<sfx>`          | Blazor WASM hosting, Free SKU.                       |

`<sfx>` is the 6-char `NameSuffix` parameter (default `vzew2f`).

---

## Auth model (read this before debugging)

```
                                                     ┌───────────────────────────┐
                                                     │ APIM MI                   │
                                                     │   → Cognitive Services    │
                                                     │     User on AOAI          │
                                                     └────────────▲──────────────┘
                                                                  │
  Browser ──HTTPS──► SWA (Blazor WASM)                            │
                          │                                       │
                          │  HTTPS                                │ AAD (MI)
                          ▼                                       │
                     ACA DAB  ──TDS (AAD token from system MI)──► Azure SQL HS
                                                                  │
                                                                  │  EXTERNAL MODEL +
                                                                  │  sp_invoke_external_rest_endpoint
                                                                  ▼
                                                                APIM ─► AOAI
```

- **Browser → SWA**: anonymous (Free SKU; demo content has no PII).
- **Browser → ACA DAB**: anonymous via DAB's `Simulator` provider, CORS `*`.
  Production deployment would swap in AAD with EasyAuth.
- **ACA → SQL**: `Authentication=Active Directory Default` resolves to
  the ACA system-assigned MI. Grants applied via
  `hosting/sql/grant_aca_mi.sql` (`CREATE USER FROM EXTERNAL PROVIDER` +
  `db_datareader` + `db_datawriter` + per-proc EXECUTE).
- **SQL → APIM → AOAI**: SQL server's system MI authenticates to APIM
  (`Cognitive Services User`). APIM re-authenticates to AOAI using its
  own MI. The bearer SQL injects via `sp_invoke` is ignored by APIM and
  replaced by APIM's MI on the way out.
- **ACA MI does NOT need AOAI/APIM rights** — model calls happen from
  SQL, not from DAB. DAB just forwards the proc call.

---

## File layout (hosting only)

```
azure/
  Prep-Cloud-Hosting.ps1          ← orchestrator
  Teardown-Cloud-Hosting.ps1      ← cost-control teardown
  hosting/
    dab/
      Dockerfile                  ← FROM mcr.../data-api-builder + COPY config
      dab-config.json             ← cloud DAB config (mirror of local)
    sql/
      grant_aca_mi.sql            ← T-SQL grants for the ACA MI
    blazor-publish/               ← (gitignored) dotnet publish output
    mcp.cloud.json                ← sample .vscode/mcp.json for attendees
  bicep/
    hosting.bicep                 ← ACR + ACA env + ACA DAB + SWA
    main.bicep                    ← (existing) Hyperscale + AOAI + APIM + CS
    modules/...
  sqlscripts/
    04a_proc_generate_mitigation.sql           ← lift-and-shift proc (NEW)
    04a_proc_generate_mitigation_gateway.sql   ← Beat-5 _v2 demo proc
    04a_proc_generate_mitigation_aoai.sql      ← Beat-5 direct demo proc
    ...
```

---

## Common failure modes

| Symptom                                                       | Likely cause                                                                                  |
|---------------------------------------------------------------|-----------------------------------------------------------------------------------------------|
| `swa deploy` fails with 401                                   | Stale SWA deployment token. Re-run; `az staticwebapp secrets list` is read live each time.    |
| ACA app stuck in `Provisioning` for >5 min                    | Image hasn't been built yet — confirm `az acr repository list -n <acr>` shows `zavalivesite-dab`.   |
| DAB returns 500 on `/api/Incident`                            | Connection string MI auth not yet propagated. Re-restart the ACA revision after 30 s.         |
| `CREATE USER FROM EXTERNAL PROVIDER` Msg 33159                | AAD hasn't propagated the new ACA principal yet. Script already sleeps 20 s; bump to 60 s.    |
| Blazor site still hits localhost                              | `appsettings.Production.json` not in `wwwroot/`. Check `dotnet publish` output.               |
| MCP discovery returns 404 from VS Code                        | `.vscode/mcp.json` not reloaded — Cmd-Shift-P → "Developer: Reload Window".                   |

---

## What still routes through APIM (and why)

The cloud `usp_GenerateMitigation` posts to the APIM gateway URL, not AOAI
directly. This is deliberate: APIM is where the content-safety classifiers
and the token-rate limit live. Switching the proc to point at AOAI
directly would skip both. Beat-5 keeps the direct/gateway pair on
purpose; the lift-and-shift proc commits to "gateway always" because
that's the recommended pattern.
