# Azure HorizonDB Demo — Zava Designer Agent

**One database. Every layer of the AI stack.** This demo builds the **Zava Designer Agent** — an AI-powered room designer that analyzes a photo of your living room and recommends furniture from a 100K-product catalog — using nothing but HorizonDB (Azure's cloud-native PostgreSQL service).

No Pinecone, no Neo4j, no separate reranker service. Vector search, full-text search, graph traversal, multimodal embeddings, reranking, and durable AI pipelines all run inside one Postgres database.

---

## What It Does

Upload a room photo. The agent analyzes it, searches 100K Amazon Home & Kitchen products, traverses a style graph, reranks results, and picks six furniture pieces that fit — all from a single HorizonDB instance.

The 6-tool agent pipeline:

| Step | Tool | HorizonDB Feature | Purpose |
|------|------|--------------------|---------|
| 1 | `analyzeRoomPhoto` | `azure_ai.generate()` | LLM reads the room photo — identifies style, colors, gaps |
| 2 | `getSemanticContext` | `pg_catalog` + `semantic_dictionary` | Schema introspection and search term expansion |
| 3 | `hybridSearchProducts` | `ai.search()` × 6 categories | BM25 + DiskANN + semantic reranking in one call |
| 4 | `findRelatedProducts` | Apache AGE Cypher / `bought_together` | Graph traversal for style-connected products |
| 5 | `filterProducts` | SQL `WHERE` | Budget ceiling + minimum rating enforcement |
| 6 | `curateRoomPicks` | `azure_ai.rank()` | Semantic reranking, best-per-category selection |

---

## Tech Stack

- **Database:** Azure HorizonDB (PostgreSQL) with extensions: `azure_ai`, `pg_fts`, `age`, `vector`
- **Frontend:** React 18 + Vite 6 (dev server on `:5180`)
- **Backend:** Express 4 + node-postgres (API on `:3001`)
- **Data:** ~100K Amazon Home & Kitchen products in `product_metadata_demo`

---

## Repository Structure

```
src/horizondb/
├── README.md                          # This file
├── DEMO_PLAN.md                       # Full 20-minute stage demo script
├── demo-build-ui-skill.md             # How the UI was built (component playbook)
├── demo-sql/                          # SQL scripts for the demo features
│   ├── data_ingest_with_ai_pipelines.sql   # AI Pipeline: chunk + embed 100K products
│   ├── data_retrieval_with_ai_search.sql   # Hybrid search with reranking
│   ├── data_graph_query.sql                # Apache AGE graph queries
│   └── setup/                              # One-time setup scripts
│       ├── setup.sql                       # Extensions and base config
│       ├── ai-search.sql                   # Search index setup
│       ├── graph_creation.sql              # AGE graph schema
│       ├── cleanup.sql                     # Teardown script
│       └── data/                           # Sample data + table DDL
│           ├── product-sample-table.sql    # Product table DDL
│           └── product_sample_may13.csv    # Sample product data
└── zava-designer-agent-ui-demo/       # Full-stack web app
    ├── server.js                      # Express backend — 6-tool pipeline
    ├── package.json                   # Dependencies
    ├── vite.config.js                 # Dev server config
    ├── Zava_logo.png                  # Brand logo
    ├── public/                        # Room photos + logos
    └── src/                           # React frontend
        ├── App.jsx                    # Main layout + state machine
        ├── index.css                  # All styles (~2000 lines)
        ├── main.jsx                   # React entry point
        ├── components/                # UI components
        │   ├── AgentTrace.jsx         # Tool call details overlay
        │   ├── ChatBubble.jsx         # Floating chat panel
        │   ├── DesignDrawer.jsx       # Settings drawer
        │   ├── DesignPanel.jsx        # Design controls panel
        │   ├── ProductCard.jsx        # Individual product display
        │   ├── QueryTrace.jsx         # Pipeline steps visualization
        │   ├── RoomView.jsx           # Room photo + product dots
        │   └── SuggestionsPanel.jsx   # Right sidebar with picks
        └── data/
            └── mockData.js            # Fallback data for offline dev
```

---

## Prerequisites

- **Azure HorizonDB server** with the following extensions enabled: `azure_ai`, `pg_fts`, `age`, `vector`
- **Model Management enabled** on the HorizonDB server (Azure Portal → AI Settings → Enable Model Management) — provides `default-embedding` and `default-chat` models
- **Node.js** 18+ and npm
- **Product data** loaded into `product_metadata_demo` table (~100K rows)

---

## Quick Start

### 1. Set up the database

Run the setup scripts against your HorizonDB instance in order:

```bash
# Connect to your HorizonDB server with psql, then run:
\i demo-sql/setup/setup.sql
\i demo-sql/setup/data/product-sample-table.sql
\i demo-sql/setup/ai-search.sql
\i demo-sql/setup/graph_creation.sql
```

> **Note:** The `private/` folder contains internal function definitions (`ai-pipelines-setup.sql`, `ai-search-internal.sql`) that must be run on the server before the demo scripts. These are gitignored and not published — contact the demo owner for access.

### 2. Load sample data

```bash
# Load product data from CSV
\copy product_metadata_demo FROM 'demo-sql/setup/data/product_sample_may13.csv' WITH (FORMAT csv, HEADER true);
```

### 3. Run the demo scripts

```bash
\i demo-sql/data_ingest_with_ai_pipelines.sql
\i demo-sql/data_retrieval_with_ai_search.sql
\i demo-sql/data_graph_query.sql
```

### 4. Start the web app

```bash
cd zava-designer-agent-ui-demo

# Create .env with your HorizonDB credentials
cat > .env <<EOF
PGHOST=<your-horizondb-server>.horizondb.azure.com
PGPORT=5432
PGDATABASE=postgres
PGUSER=<your-username>
PGPASSWORD=<your-password>
EOF

npm install
npm run dev:full
```

The frontend opens at `http://localhost:5180` and proxies API calls to the Express backend on `:3001`.

### 5. Use the app

1. Open `http://localhost:5180`
2. Click **"Design My Room"**
3. Watch the 6-tool pipeline execute — room analysis → hybrid search → graph traversal → reranking
4. Explore the product dots on the furnished room photo
5. Click **"⚡ How did this work?"** for the pipeline visualization or **"⚙️ Agent Details"** for raw SQL + JSON traces

---

## Key HorizonDB Features Demonstrated

### AI Pipelines (`ai.create_pipeline`, `ai.run`)
Chunk and embed 100K products with two lines of SQL. The `on_change` trigger auto-processes new inserts.

### Hybrid Search (`ai.search`)
BM25 full-text + DiskANN vector + RRF fusion + semantic reranking — all in a single function call, filtered by category.

### Graph Traversal (Apache AGE)
AI-extracted style tags (`ai.extract`) build a property graph: `(:Product)-[:HAS_STYLE]->(:Style)-[:SIMILAR_TO]->(:Style)`. Cypher queries discover cross-category, cross-style recommendations.

### LLM Integration (`azure_ai.generate`, `azure_ai.rank`)
Call LLMs and rerankers directly from SQL — no external service orchestration needed.

---

## Related Resources

- [DEMO_PLAN.md](DEMO_PLAN.md) — Full 20-minute stage demo script with speaker notes
- [demo-build-ui-skill.md](demo-build-ui-skill.md) — Detailed component architecture and build playbook
- [Session README](../../README.md) — BRK223 session overview and other demos (Azure SQL, Cosmos DB)
