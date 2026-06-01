<a name="start-building"></a>
<br>
<p align="center">
<img src="img/banner-build-26.png" alt="Microsoft Build 2026" width="1200"/>
</p>

# [Microsoft Build 2026](https://build.microsoft.com)

## 🔥 BRK223: From rows to reasoning — Designing databases for AI apps and agents

### Session Description

AI applications and agents require data platforms designed for reasoning, not just transactions. Traditional architectures force developers to stitch data systems together, adding latency and complexity. In this demo-rich session, we'll show the latest innovations in **SQL Database** and **Azure Cosmos DB**, then build an app on **Azure HorizonDB**, Azure's new cloud-native PostgreSQL service, to show how AI apps built directly in the database simplify design and enable reasoning over operational data.

### 🎬 Demos in this repo

Each demo is self-contained under `src/`. Open the demo's README for prerequisites, a quick-start, and a walkthrough.

| Demo | What it shows | Status |
|---|---|---|
| **[Azure SQL — From Database to Live Site, with AI Agents in the Loop](src/sql/README.md)** | Vector + JSON + REGEXP + ledger + `CREATE EXTERNAL MODEL` + `sp_invoke_external_rest_endpoint` + DiskANN + JSON indexes, all in one schema. A Blazor page polls Data API Builder REST every 2 s; a custom Copilot agent reaches the same DB over MCP to triage an incident and write a mitigation back — which the page then renders live. | ✅ Available |
| **[Azure Cosmos DB — Agent Memory Demo](src/cosmosdb/README.md)** | A support-ticket agent memory demo using Azure Cosmos DB, Foundry, and Azure Durable Functions to show a serverless architecture + SDK for efficient memory storage, processing, and retrieval. | ✅ Available |
| **[Azure HorizonDB — Zava Designer Agent](src/horizondb/README.md)** | AI Pipelines (`ai.create_pipeline`) + hybrid search (`ai.search` with BM25 + DiskANN + reranking) + Apache AGE graph traversal + LLM calls (`azure_ai.generate`, `azure_ai.rank`) — all inside one Postgres database. A React + Express app runs a 6-tool agent pipeline against HorizonDB to design a room from a 100K product catalog. | ✅ Available |

### 🏫 Getting started in a guided session

To follow along in the room:
- Watch the SQL demo land its data-platform features against the overarching story (operational data → grounding → agent reasoning).
- Compare how Cosmos DB and HorizonDB pick up the same story with different data platform patterns.
- Grab the QR code on the closing slide to clone this repo and try the SQL demo at home today.

### 🏠 Getting started in your own environment

If you're following at your own pace, each demo has its own quick-start:
- **SQL:** [src/sql/README.md](src/sql/README.md) — Windows 11 + Docker Desktop + .NET 10 + PowerShell 7. Cold build ~12–15 min.
- **Cosmos DB:** [src/cosmosdb/README.md](src/cosmosdb/README.md) - Azure Cosmos DB for NoSQL + Micrsoft Foundry + Azure Durable Functions (optional).
- **HorizonDB:** [src/horizondb/README.md](src/horizondb/README.md) — Azure HorizonDB + Node.js 18+ + product data loaded, then follow Quick Start to run the Zava Designer Agent.

### 🧠 Learning Outcomes

By the end of this session, you will be able to:

- Recognize when an AI app's bottleneck is the database design, not the model.
- Understand how **Azure SQL Database** expresses vectors, JSON, and AI directly in the engine — `vector(N)` + DiskANN, JSON type + JSON indexes, `CREATE EXTERNAL MODEL`, `AI_GENERATE_EMBEDDINGS`, `sp_invoke_external_rest_endpoint`, append-only ledger.
- Compare how the same reasoning-centric app pattern is implemented across **Azure SQL Database**, **Azure Cosmos DB**, and **Azure HorizonDB**.
- Ground a Copilot agent in a live database via MCP, with grounding files (`.agent.md` + `SKILL.md`) that VS Code Copilot Chat discovers automatically.

### 💬 Keep Learning with Copilot

Try these prompts with GitHub Copilot to explore the topics from this session. Open Copilot Chat in VS Code (`Ctrl+Alt+I` on Windows/Linux, `Cmd+Shift+I` on Mac), paste a prompt, and see what you learn. Try connecting the [Microsoft Learn MCP Server](#-microsoft-learn-mcp-server) for the latest official documentation.

Use these as a starting point — or write your own!

- *"Compare how Azure SQL Database, Azure Cosmos DB, and Azure HorizonDB each store and query vector embeddings. When would I pick each?"*
- *"Show me the syntax for `CREATE EXTERNAL MODEL` in Azure SQL and what `MODEL_TYPE` / `API_FORMAT` values are valid."*
- *"How do I expose a database to an AI agent via MCP using Data API Builder?"*
- *"What does 'AI built directly in the database' mean for an agent that needs to reason over operational data with low latency?"*

### 💻 Technologies Used

1. Azure SQL Database / SQL Server 2025 (`vector`, `JSON`, `REGEXP_*`, `AI_GENERATE_EMBEDDINGS`, `CREATE EXTERNAL MODEL`, `sp_invoke_external_rest_endpoint`, DiskANN, JSON indexes, ledger tables)
1. Azure Cosmos DB
1. Azure HorizonDB (cloud-native PostgreSQL with AI in the database)
1. Data API Builder 2.0 (REST + MCP from one config)
1. .NET 10 + .NET Aspire 13 (Blazor WASM + AppHost orchestration in the SQL demo)
1. GitHub Copilot Chat custom agents (`.agent.md` + `SKILL.md`) over MCP

### 📚 Resources and Next Steps

| Resource | Description |
|:---------|:------------|
| [https://aka.ms/build26-next-steps](https://aka.ms/build26-next-steps) | Explore lab and session repos to further your learning from Microsoft Build |


### 🌟 Microsoft Learn MCP Server

The Microsoft Learn MCP Server gives your AI agent direct access to Microsoft's official documentation — grounded, up-to-date answers about the products and services covered in this session.

**VS Code** — One click installation: 

[![Install in VS Code](https://img.shields.io/badge/VS_Code-Install_Microsoft_Learn_MCP-0098FF?style=flat-square&logo=visualstudiocode&logoColor=white)](https://vscode.dev/redirect/mcp/install?name=microsoft-learn&config=%7B%22type%22%3A%22http%22%2C%22url%22%3A%22https%3A%2F%2Flearn.microsoft.com%2Fapi%2Fmcp%22%7D)


**GitHub Copilot CLI** — Run this to install the Learn MCP Server as a plugin:
```
/plugin install microsoftdocs/mcp
```

For more info, other clients, and to post questions, visit the [Learn MCP Server repo](https://aka.ms/learnmcp).

## Content Owners

<!-- TODO: Add yourself as a content owner
1. Change the src in the image tag to {your github url}.png
2. Change INSERT NAME HERE to your name
3. Change the github url in the final href to your url. -->

<table>
<tr>
    <td align="center"><a href="http://github.com/yourGitHubHandle">
        <img src="https://github.com/yourGitHubHandle.png" width="100px;" alt="INSERT NAME HERE"/><br />
        <sub><b>INSERT NAME HERE</b></sub></a><br />
            <a href="https://github.com/yourGitHubHandle" title="talk">📢</a>
    </td>
</tr></table>

## Contributing

This project welcomes contributions and suggestions.  Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit [Contributor License Agreements](https://cla.opensource.microsoft.com).

When you submit a pull request, a CLA bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., status check, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.

## Trademarks

This project may contain trademarks or logos for projects, products, or services. Authorized use of Microsoft
trademarks or logos is subject to and must follow
[Microsoft's Trademark & Brand Guidelines](https://www.microsoft.com/legal/intellectualproperty/trademarks/usage/general).
Use of Microsoft trademarks or logos in modified versions of this project must not cause confusion or imply Microsoft sponsorship.
Any use of third-party trademarks or logos are subject to those third-party's policies.
