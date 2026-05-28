# /src

Source code and demo assets for **BRK223 — From rows to reasoning: Designing databases for AI apps and agents**.

## Demos

| Path | What it is | Status |
|---|---|---|
| [sql/](sql/README.md) | **Azure SQL — From Database to Live Site, with AI Agents in the Loop.** Local single-container build (SQL + Ollama + Caddy) + Blazor WASM page + Data API Builder REST/MCP + custom `live-site-sql` Copilot agent. Also includes the matching Azure cloud lift (Hyperscale + AOAI + APIM + Content Safety + ACA + SWA). | ✅ Available |
| [cosmosdb/](cosmosdb/README.md) | **Azure Cosmos DB — Agent memory for support workflows.** Support Engineer Agent demo using Agent Memory Toolkit to store , process, and retrieve memories to build derived user context across tickets. | ✅ Available |
| [horizondb/](horizondb/README.md) | **Azure HorizonDB — Zava Designer Agent.** PostgreSQL + AI pipelines + hybrid search + graph traversal demo for room design workflows. | ✅ Available |

## Where to start

Pick a demo and follow its quick-start:

- **SQL:** [sql/README.md](sql/README.md) — see **Quick start — local**. Cold build is ~12–15 min.
- **Cosmos DB:** [cosmosdb/README.md](cosmosdb/README.md) — see setup and run instructions in the demo README.
- **HorizonDB:** [horizondb/README.md](horizondb/README.md) — see **Prerequisites** and **Quick Start** to run the Zava Designer Agent.
