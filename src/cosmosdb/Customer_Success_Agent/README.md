# SaaS Customer Success Agent

SaaS Customer Success Agent is a developer-facing demo app for the Agent Memory Toolkit. It shows how a customer success agent can remember account context across engagements, retrieve relevant facts, update account profiles, and keep memory isolated across multiple SaaS customer accounts.

The demo includes four seeded SaaS customer accounts:

- Northwind Analytics: enterprise analytics account with onboarding deadlines, dashboard adoption goals, and renewal risk.
- Contoso Health: regulated healthcare account focused on SSO, least-privilege role mapping, and audit evidence.
- Fabrikam Retail: retail account preparing QBR narratives, workflow adoption metrics, and expansion planning.
- Alpine Robotics: robotics account evaluating reliability, launch readiness, API limits, and enterprise-plan fit.

The UI intentionally uses **Agent** naming throughout.

## What It Demonstrates

- Storing customer-success engagement conversations with `CosmosMemoryClient.add_cosmos`.
- Searching cross-engagement account context with `search_cosmos`.
- Reading extracted facts, procedural memory, and episodic memory with `get_memories`.
- Generating engagement thread summaries and account-level user summaries with the in-process pipeline.
- Keeping customer account memory isolated per account scope.
- Showing semantic recall for SaaS queries such as renewal risk, SSO blockers, QBR adoption, audit evidence, and launch reliability.
- Showing processing with one action that extracts durable memories, summarizes the engagement, and updates the account profile.
- Inspecting the memory that shaped the agent response.

## Folder Layout

```text
Customer_Success_Agent/
  Makefile
  backend/
    app.py
    memory_service.py
    models.py
    seed_cli.py
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

      The frontend labels these records as accounts and engagements. Some backend models and routes still use the original `user` and `ticket` names because the Agent Memory Toolkit stores memories by `user_id` and `thread_id`; in this sample, `user_id` is the account-level tenant boundary and each ticket route represents an engagement thread.

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
pip install -r Samples/Scenarios/Customer_Success_Agent/backend/requirements.txt
```

Option B: install the toolkit package directly if you already have this sample source locally:

```bash
pip install cosmos-agent-memory-toolkit
pip install -r Samples/Scenarios/Customer_Success_Agent/backend/requirements.txt
```

If you are working from a cloned repository, you can also install the demo dependencies from this scenario folder:

```bash
make install-backend
make install-frontend
```

Install frontend dependencies:

```bash
cd Samples/Scenarios/Customer_Success_Agent/frontend
npm install
```

## Configure Environment

Copy the template and fill in your endpoints:

```bash
cd Samples/Scenarios/Customer_Success_Agent
cp .env.template .env
```

Required values:

```text
COSMOS_DB_ENDPOINT
AI_FOUNDRY_ENDPOINT
AI_FOUNDRY_EMBEDDING_DEPLOYMENT_NAME
AI_FOUNDRY_CHAT_DEPLOYMENT_NAME
```

`COSMOS_DB_KEY` and `AI_FOUNDRY_API_KEY` are optional when your local identity has the required access. If `COSMOS_DB_KEY` is empty, the backend authenticates to Cosmos DB with `DefaultAzureCredential` / Microsoft Entra ID.

## Run The Demo

Start the backend:

```bash
cd Samples/Scenarios/Customer_Success_Agent
uvicorn app:app --reload --port 8000
```

Or from this scenario folder:

```bash
make backend
```

Start the frontend in a second terminal:

```bash
cd Samples/Scenarios/Customer_Success_Agent/frontend
npm run dev
```

Or from this scenario folder:

```bash
make frontend
```

Open the Vite URL printed in the terminal, usually `http://localhost:5173`.

## Seed Demo Data

Demo accounts, engagements, and conversations are loaded from the terminal with the seeding CLI (run from this scenario folder, with your `.env` configured):

```bash
cd Samples/Scenarios/Customer_Success_Agent
python -m backend.seed_cli seed
```

Add `--process` to also extract facts, procedural and episodic memory, engagement summaries, and account summaries while seeding:

```bash
python -m backend.seed_cli seed --process
```

To delete every demo memory record across all demo accounts:

```bash
python -m backend.seed_cli reset
```

Equivalent Makefile shortcuts are available: `make seed`, `make seed-process`, and `make reset`.

Use the theme toggle in the top bar to switch between light and dark mode.

## Suggested Demo Flow

1. Seed the raw demo turns from the terminal with `python -m backend.seed_cli seed`.
2. Select one account and open an engagement.
3. Ask a recall prompt such as "What risks should I mention in the renewal plan?"
4. Process the engagement to extract facts, procedural memory, episodic memory, an engagement summary, and an account summary.
5. Switch accounts to confirm memory isolation.
6. Use semantic search prompts around renewal risk, SSO blockers, QBR adoption, audit evidence, or launch reliability to show cross-engagement recall within the selected account.
