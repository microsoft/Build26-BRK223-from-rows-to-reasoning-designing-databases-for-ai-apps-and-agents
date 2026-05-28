# Support Engineer Agent

Support Engineer Agent is a developer-facing demo app for the Agent Memory Toolkit. It shows how a support agent can remember customer context across tickets, retrieve relevant facts, update user profiles, and keep memory isolated across multiple distinct users.

The demo includes four seeded support customers:

- James: enterprise IT admin with device and Intune issues.
- Aayush: startup founder/developer focused on API reliability and latency.
- Theo: data engineer working through Cosmos DB query and throughput issues.
- Raj: security and compliance lead focused on auditability and access control.

The UI intentionally uses **Agent** naming throughout.

## What It Demonstrates

- Storing support conversations with `CosmosMemoryClient.add_cosmos`.
- Searching cross-ticket context with `search_cosmos`.
- Reading extracted facts, procedural memory, and episodic memory with `get_memories`.
- Generating thread and user summaries with the in-process pipeline.
- Keeping support memory isolated per user.
- Inspecting the memory that shaped the agent response.

## Folder Layout

```text
Support_Engineer_Agent/
  Makefile
  backend/
    app.py
    memory_service.py
    models.py
    seed_data.py
    support_agent.py
    requirements.txt
  frontend/
    index.html
    package.json
    src/
      api.js
      main.jsx
      state.js
      styles.css
      components/
        App.jsx
        ChatPanel.jsx
        MemoryPanel.jsx
        ThemeToggle.jsx
        TicketTimeline.jsx
        UserSwitcher.jsx
```

## Prerequisites

- Python 3.11+
- Node.js 18+
- Azure Cosmos DB account configured for the toolkit
- Azure AI Foundry or Azure OpenAI endpoint with chat and embedding deployments

## Get The Toolkit

Use either a local clone of the repository or the published package.

Option A: clone the repository and install the toolkit from source:

```bash
git clone https://github.com/AzureCosmosDB/AgentMemoryToolkit.git
cd AgentMemoryToolkit
pip install -e .
pip install -r Samples/Scenarios/Support_Engineer_Agent/backend/requirements.txt
```

Option B: install the toolkit package directly if you already have this sample source locally:

```bash
pip install cosmos-agent-memory-toolkit
pip install -r Samples/Scenarios/Support_Engineer_Agent/backend/requirements.txt
```

If you are working from a cloned repository, you can also install the demo dependencies from this scenario folder:

```bash
make install-backend
make install-frontend
```

Install frontend dependencies:

```bash
cd Samples/Scenarios/Support_Engineer_Agent/frontend
npm install
```

## Configure Environment

Copy the template and fill in your endpoints:

```bash
cd Samples/Scenarios/Support_Engineer_Agent
cp .env.template .env
```

Required values:

```text
COSMOS_DB_ENDPOINT
AI_FOUNDRY_ENDPOINT
AI_FOUNDRY_EMBEDDING_DEPLOYMENT_NAME
AI_FOUNDRY_CHAT_DEPLOYMENT_NAME
```

`COSMOS_DB_KEY` and `AI_FOUNDRY_API_KEY` are optional when your local identity has the required access.

## Run The Demo

Start the backend:

```bash
cd Samples/Scenarios/Support_Engineer_Agent/backend
uvicorn app:app --reload --port 8000
```

Or from this scenario folder:

```bash
make backend
```

Start the frontend in a second terminal:

```bash
cd Samples/Scenarios/Support_Engineer_Agent/frontend
npm run dev
```

Or from this scenario folder:

```bash
make frontend
```

Open the Vite URL printed in the terminal, usually `http://localhost:5173`.
