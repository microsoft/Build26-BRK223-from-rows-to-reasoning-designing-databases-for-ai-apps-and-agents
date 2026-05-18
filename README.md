# 🚀 Get Started

**This repo is where attendees go to continue their learning after your session — and your Copilot agent will help you set it up.**

### Step 1: Open your repo

Open this repo in a **Codespace** (click the green **Code** button → **Create a Codespace**) — or clone it locally. Then open **GitHub Copilot Chat**.

### Step 2: Add your content

Give the agent something to work with. Drag files into the Explorer panel — session abstracts, outlines, screenshots, notes — and drop them in one of two places:

| Where to put it | What goes there | Who sees it |
|---|---|---|
| **`_remove-before-publish/`** | Internal reference materials (abstracts, outlines, screenshots, planning docs) | **Copilot only** — never published |
| **`/docs/`, `/src/`, or repo root** | Lab instructions, demo code, sample data, getting-started guides | **Attendees** — published with the repo |

> 💡 Not sure? Start by dropping your session abstract or outline into `_remove-before-publish/`. The agent will figure out what to do with it.

### Step 3: Ask the Agent

Once your content is in the repo, use these three phrases with Copilot to build out your session repo:

| Phrase to use with Copilot | What it does | When to run it |
|---|---|---|
| **"Help me get started"** | Sets up session title, description, outcomes, and owners | After you've added your session abstract or outline to the repo |
| **"Help me refine content"** | Organizes your session content into the repo | Each time you add or update content |
| **"Help me finalize"** | Final review, cleanup, and publication prep | When you're ready to publish |

> 💡 **These three phrases are just the starting point.** Copilot can do much more — try asking it to brainstorm next steps for attendees, generate code samples, or build out your repo structure. Don't be afraid to put it in plan mode and ask for what you need.

---

<a name="start-building"></a>
<br>
<p align="center">
<img src="img/banner-build-26.png" alt="Microsoft Build 2026" width="1200"/>
</p>

# [Microsoft Build 2026](https://build.microsoft.com)

## 🔥 BRK223: Azure SQL — From Database to Live Site, with AI in the Loop

### Session Description

An end-to-end sample that grounds an incident-triage AI agent in **Azure SQL**. One container hosts SQL, the embedding model, and the chat model; a Blazor WASM page polls a Data API Builder REST endpoint every two seconds; a custom VS Code agent reaches the same database over MCP to read incidents, run hybrid (vector + JSON + full-text) search across runbooks, execute diagnostic stored procedures, and write a mitigation back into the row — which the page then renders live.

The demo exercises the Azure SQL / SQL Server 2025 AI surface (`vector`, `JSON`, `REGEXP_*`, `AI_GENERATE_EMBEDDINGS`, `CREATE EXTERNAL MODEL`, `sp_invoke_external_rest_endpoint`, DiskANN, JSON indexes, ledger tables) inside a single coherent storyline: incident lands → page lights up → agent triages → mitigation appears.

**The complete demo, scripts, and walkthrough live under [src/sql/](src/sql/README.md).**

### 🏫 Getting started in a guided session

To follow along in the room:
- Watch the live demo of incident #5012 from creation to AI mitigation.
- Note which Azure SQL feature lights up at each beat (the [src/sql/demo.md](src/sql/demo.md) walkthrough labels them).
- Grab the QR code on the closing slide to clone this repo and try it at home.

### 🏠 Getting started in your own environment

If you're following these steps at your own pace:
- Clone this repository.
- Open [**src/sql/README.md**](src/sql/README.md) and follow the **Quick start — local** section (Windows 11 + Docker Desktop + .NET 10 + PowerShell 7).
- Cold build is ~12–15 min and lands you on a working local copy of the demo: SQL container, Ollama embedding + chat models, Blazor page, and the `live-site-sql` Copilot agent already wired up.

### 🧠 Learning Outcomes

By the end of this session, you will be able to:

- Model a hybrid corpus in Azure SQL using `vector`, `JSON`, full-text, and ledger together in one schema.
- Use `CREATE EXTERNAL MODEL` + `AI_GENERATE_EMBEDDINGS` to embed data and `sp_invoke_external_rest_endpoint` to call a chat model — all from T-SQL.
- Combine vector (DiskANN), JSON, and full-text predicates in a single hybrid-search stored procedure.
- Expose a database to a custom AI agent via Data API Builder's MCP endpoint, and ground the agent's behavior with a `.agent.md` + `SKILL.md` pair that VS Code Copilot Chat discovers automatically.

### 💬 Keep Learning with Copilot

Try these prompts with GitHub Copilot to explore the topics from this session. Open Copilot Chat in VS Code (`Ctrl+Alt+I` on Windows/Linux, `Cmd+Shift+I` on Mac), paste a prompt, and see what you learn. Try connecting the [Microsoft Learn MCP Server](#-microsoft-learn-mcp-server) for the latest official documentation.

Use these as a starting point — or write your own!

- *"Show me the syntax for `CREATE EXTERNAL MODEL` in Azure SQL and what `MODEL_TYPE` / `API_FORMAT` values are valid."*
- *"What's the difference between a DiskANN vector index and a plain kNN vector scan in Azure SQL, and when does the optimizer pick each?"*
- *"How do I expose a SQL stored procedure as an MCP tool with Data API Builder?"*
- *"Walk me through grounding an AI agent in Azure SQL using `.agent.md` + `SKILL.md` files that VS Code Copilot Chat auto-discovers."*

### 💻 Technologies Used

1. Azure SQL Database / SQL Server 2025 (`vector`, `JSON`, `REGEXP_*`, `AI_GENERATE_EMBEDDINGS`, `CREATE EXTERNAL MODEL`, `sp_invoke_external_rest_endpoint`, DiskANN, JSON indexes, ledger tables)
1. Data API Builder 2.0 (REST + MCP from one config)
1. .NET 10 + .NET Aspire 13 (Blazor WASM + AppHost orchestration)
1. Ollama (local: `mxbai-embed-large` embeddings + `phi4-mini` chat) / Azure OpenAI (cloud: `text-embedding-3-small` + `gpt-4o-mini`)
1. GitHub Copilot Chat custom agent (`.agent.md` + `SKILL.md`) over MCP

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
