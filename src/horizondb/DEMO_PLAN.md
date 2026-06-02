# Build 2026 Demo Plan — Revised Structure

## Overview

20-minute demo using the **Zava Room Designer Agent** scenario. 100K Zava Home & Kitchen products in `product_metadata_demo` on HorizonDB. The demo showcases AI Pipelines, hybrid search, AI-powered style extraction, and a graph query — all inside Postgres.

**Core message:** *"One Postgres database. Every layer of the AI stack."* — No Pinecone, no Neo4j, no separate reranker service. Vector search, full-text search, graph, multimodal embeddings, reranking, and durable pipelines all run inside one Postgres database.

**The Core Promise:** "I'm going to build Zava Designer Agent — an app that looks at a photo of your living room and tells you exactly which pieces from a 100K+ Zava catalog would make it perfect — and I'm going to build the entire thing, database to frontend, in 20 minutes using nothing but HorizonDB."

### Demo flow at a glance

| Act | Title | Duration | What the audience sees |
|-----|-------|----------|----------------------|
| 0 | Cold Open | 1 min | Finished app working — upload a room photo, get 6 furniture picks. Hook before any intros. |
| 1 | RAG Pipeline in Seconds | 5 min | Enable Model Management, then `ai.create_pipeline` chunks + embeds 100K products, `on_change` trigger auto-processes inserts |
| 2 | Hybrid Search with Reranking | 5 min | `ai.search` across 6 categories — BM25 + DiskANN + semantic reranking in one call |
| 3 | Graph: Style-Based Discovery | 6 min | Flash style pipeline output (1 min), then Cypher queries traverse Product → Style → SIMILAR_TO → Product |
| 4 | Full Circle: The Agent | 3 min | Back to Zava Designer Agent — open the tool trace, show all 5 tools calling HorizonDB under the hood |
| 5 | Production-Ready | 1 min | Sizzle reel of 4 variant consumer apps and internal chatbot. CTA: "Clone the repo." |

---

## ACT 0 — Cold Open

**Duration:** ~1 minute

**What happens:** No slides, no intros. Walk on stage, open the Zava Designer Agent, and run it.

Upload a room photo of a Brooklyn loft. The agent thinks for a few seconds. Six furniture picks appear on the photo — a coffee table, an accent chair, a lamp, a rug, a bookshelf, wall art. Prices, ratings, a running budget total.

**Say:** "This app just analyzed a photo, searched the product catalog, traversed a style graph, reranked the results, and picked six pieces that fit this room — all from a single Postgres database. Let me show you how to build it."

**Then:** Brief intro — who you are, what HorizonDB is, and the promise: *"Database to frontend, 20 minutes, one database."*

---

## ACT 1 — RAG Pipeline in Seconds

**Feature:** `ai.create_pipeline`, `ai.run`

### Enable Model Management (~15 seconds)

Before creating any pipeline, flip on managed models. In the Azure Portal, navigate to the HorizonDB server → **AI Settings** → check **Enable Model Management** → Save. That's it — one checkbox gives you `default-embedding` and `default-chat` models accessible via SQL, no external Azure OpenAI endpoint to configure.

**Say:** "Before I build anything, I need AI models. In HorizonDB, that's one checkbox — Enable Model Management. Now I have embedding and chat models available directly inside Postgres."

### The dataset (~30 seconds)

Open the schema visual (VS Code PostgreSQL extension → schema diagram) for `product_metadata_demo`. Walk the audience through the table:

**Say:** "This is our dataset — 100,000 real Amazon Home & Kitchen products. Each row has a title, description, price, ratings, store, categories as a JSON array, product features, and images. We've pre-built a `content` column that concatenates the key fields into a single rich text block — that's what we'll feed into the pipeline."

Key columns to highlight on the visual:
- `title`, `description` — the human-readable product info
- `categories` (JSONB array) — e.g. `["Furniture", "Living Room", "Coffee Tables"]`
- `price`, `average_rating`, `rating_number` — filtering dimensions
- `content` — the concatenated column used for chunking + embedding
- `images` (JSONB) — product photos

### Build the pipeline

Today most generative AI apps rebuild the same steps:

*   Chunking
*   Creating embeddings
*   Backfilling data

These steps are often in fragile external pipelines. With AI pipelines, all of this is built directly into Postgres. 


Show a pipeline that chunks and embeds product data. The `content` column (title + description + categories + store + features) gives richer embeddings than description alone.

```sql
SELECT ai.create_pipeline(
    name    => 'product_rag_pipeline_build_2026',
    source  => ai.table_source('product_metadata_demo'),
    steps   => ARRAY[
        ai.chunk(input => 'content', chunk_size => 1024, overlap => 128),
        ai.embed(model => 'default-embedding', input_column => 'chunk_text', dimensions => 1536)
    ],
    trigger => 'on_change'
);

SELECT ai.run('product_rag_pipeline_build_2026');
```

**Sub-beats:**

- Monitor with AI Pipeline in VSCode
  I can then go ahead and run this. If I count the records in the output table, you can see that it's increasing. This is all happening asynchronously in the background so that it's not blocking or really having any real performance impact on my transactional workload.  

- Insert a new product → `on_change` trigger picks it up automatically
  
  The best thing about this pipeline is that it's durable (using pg_durable OSS extension). This means that I can pause it and you can see here that the row count stops increasing even if the workload continues. I can resume it. Think of it as a reliable background task. If my server fails over, it's no problem. The AI pipeline fails over as well and it just keeps running. All that pipeline complexity then just moves into the database and reduces the complexity and runs reliably. Exactly and building on this

### Show the output table (~30 seconds)

Once the pipeline finishes, query the auto-created output table to show what it produced:

```sql
SELECT source_id, chunk_index, chunk_text, LEFT(embedding::text, 60) AS embedding_preview
FROM product_rag_pipeline_build_2026_output
LIMIT 5;
```

| source_id | chunk_index | chunk_text | embedding_preview |
|-----------|-------------|------------|-------------------|
| 1 | 0 | WLIVE Lift Top Coffee Table. Mid-century modern… | [0.0123, -0.0456, 0.0789, 0.0012, -0.034… |
| 1 | 1 | …storage shelf, espresso finish, wood grain… | [0.0234, -0.0567, 0.0891, 0.0023, -0.045… |
| 2 | 0 | Boho Macramé Wall Hanging. Handwoven cotton… | [-0.0112, 0.0334, 0.0567, -0.0089, 0.012… |

**Say:** "The pipeline read every product, broke the content into chunks, and generated a 1,536-dimension embedding for each one. This is the table that powers search — and it was built with two lines of SQL."

---

## ACT 2 — Hybrid Search with Reranking

**Feature:** `ai.search`, DiskANN, pg_fts BM25, semantic reranking

1. Let me create the right indexes to do the search. First, I'll create the vector index for the vector search, and I also create a full text search index. We're going to be using pg_fts, which is a new extension we have to do full text search, BM25 full text search, a similar algorithm you with find in most production search engines. 
2. This is not shipped yet, so I'm using my stored procedure just to show you guys what it would be like when it ships. 
3. Show Query visualization. 

Search the product catalog with natural language, filtered by category.

```sql
SELECT product.title, product.price, search.score
FROM ai.search(
    query => 'mid-century modern furniture for Brooklyn loft living room with wood tones and dark vibe',
    source_table => 'product_metadata_demo',
    embedding_column => 'embedding'
) search
JOIN product_metadata_demo product ON product.id = search.id;
ORDER BY score
```

Run across 6 categories: Chairs, Coffee Tables, Lamps & Lighting, Area Rugs, Bookcases, Wall Art.

**Sub-beats:**
- Flip back to the Agent app. Open the Agent tools and walk through how the agent was able to analyze a room with a tool and then do the search. 

---

## ACT 3 — Graph: Style-Based Product Discovery

**Feature:** `ai.extract` + `ai.generate` → Apache AGE graph

### Setup: Style pipeline output (~1 minute)

**Narrative:** "Our catalog has unstructured descriptions. We ran a second pipeline that reads each one, extracts its design style, and discovers complementary styles — all with `ai.extract` and `ai.generate`."

Flash the pipeline definition on screen (don't walk through it — audience already saw pipeline syntax in ACT 1):

```sql
SELECT ai.create_pipeline(
    name   => 'style_tagger',
    source => ai.table_source('product_metadata_demo'),
    steps  => ARRAY[
        ai.extract(model => 'default-chat', input_column => 'content',
                   data => ARRAY['style: string - the design style']),
        ai.generate('default-chat',
                    'Output ONLY a comma-separated list of 1-2 complementary styles.',
                    'content')
    ]
);
```

Show 3 rows of output — this is what feeds the graph:

```sql
SELECT title, extracted->'style' AS style, generated AS related_styles
FROM style_tagger_output LIMIT 3;
```

| title | style | related_styles |
|---|---|---|
| WLIVE Lift Top Coffee Table | Mid-Century Modern | Scandinavian, Industrial |
| Boho Macramé Wall Hanging | Bohemian | Farmhouse, Scandinavian |
| Metal Pipe Bookshelf | Industrial | Mid-Century Modern, Minimalist |

**Say:** "Every product now has a style tag and a list of related styles. This becomes our graph."

### Graph queries (~5 minutes)

**Narrative:** "Now let's connect it all — products, styles, categories, and the style affinities the AI discovered."

Three node types, three edge types:
```
(:Product)-[:HAS_STYLE]->(:Style)           ← from ai.extract output
(:Product)-[:IN_CATEGORY]->(:Category)      ← from categories column
(:Style)-[:SIMILAR_TO]->(:Style)            ← from ai.generate output
```

### Live demo query 1 — 2-hop via SIMILAR_TO (the wow moment)

```sql
-- "Products in styles SIMILAR to mine, across different categories"
SELECT * FROM ag_catalog.cypher('style_graph', $$
    MATCH (seed:Product {id: 2315})-[e1:HAS_STYLE]->(s:Style)-[e2:SIMILAR_TO]->(related:Style)<-[e3:HAS_STYLE]-(rec:Product)
    MATCH (seed)-[e4:IN_CATEGORY]->(seedCat:Category)
    MATCH (rec)-[e5:IN_CATEGORY]->(recCat:Category)
    WHERE seedCat.name <> recCat.name
    RETURN seed, e1, s, e2, related, e3, rec, e4, seedCat, e5, recCat
    LIMIT 15
$$) AS (seed agtype, e1 agtype, style agtype, e2 agtype, related agtype, e3 agtype, rec agtype, e4 agtype, seedCat agtype, e5 agtype, recCat agtype);
```

**English:** "My Chair is Mid-Century Modern. The AI says Scandinavian and Industrial are similar. Show me Scandinavian chairs and Industrial lamps — products I'd never find with a simple style filter."

**The payoff moment:** "The AI discovered style relationships. The graph traverses them. You get recommendations that cross both categories AND styles — all from Postgres."

This is the money query — discovers products you'd never find with a filter, we can add a style discover feature in the future by connecting styles with SIMILAR_TO edges but I show you the query.

### Talk-through moment

"Every piece of this — the style extraction, the related-style discovery, the graph edges, and the traversal query — runs inside Postgres. No external ML service, no ETL pipeline, no separate graph database."

---

## ACT 4 — Full Circle: The Agent Behind the App

**Feature:** Zava Designer Agent tool trace — every tool calls HorizonDB

**Narrative:** "We've seen pipelines, hybrid search, and graph traversal. But this is what it looks like when an AI agent uses them all together."

Switch back to the Zava Designer Agent UI. Type the same prompt from earlier — *"mid-century modern furniture for Brooklyn loft living room with wood tones"* — and hit enter.

While the agent is thinking, **open the tool trace panel** to show the 5-tool pipeline executing in real time:

| Step | Tool | What it calls in HorizonDB | Purpose |
|------|------|---------------------------|---------|
| 1 | `analyze_room_photo` | `azure_ai.generate()` | LLM reads the room photo and identifies style, colors, existing furniture, and gaps |
| 2 | `hybrid_search_products` | `ai.search()` × 6 categories | BM25 + DiskANN + reranking — one search per category (Chairs, Coffee Tables, Lamps, Rugs, Bookcases, Wall Art) |
| 3 | `find_related_products` | AGE Cypher / `bought_together` JOIN | Graph traversal to find products connected by style or purchase patterns |
| 4 | `filter_products` | SQL `WHERE` on price + rating | Enforces budget ceiling per item and minimum 4.0★ rating |
| 5 | `curate_room_picks` | `azure_ai.rank()` | Semantic reranking of all candidates against the room description, then best-per-category selection |

**Key talking point:** "Five tools, one database. The room analysis, the search, the graph traversal, the reranking — every single call goes to HorizonDB. There's no external vector database, no separate ML service, no graph database running alongside. It's all Postgres."

**Show the trace output** — each tool returns its duration, inputs, and outputs. Point out the total latency: all 5 tools complete in ~3-5 seconds.

**Close the loop:** The products appear on the room photo as interactive dots. The sidebar shows prices, ratings, and a running budget total. "This is what it looks like when you build an AI-native application on a single database."

**Final line:** "Pipelines to enrich your data. Hybrid search to find it. A graph to connect it. And an LLM to reason over it. All inside Postgres — that's HorizonDB."


---

## ACT 5 — Production-Ready

**Duration:** ~1 minute

**What happens:** Run a quick sizzle reel showing 4 variant consumer apps plus an internal chatbot built on the same HorizonDB foundation.

**Say:** "This isn't just a single demo app. This pattern scales across multiple product experiences and internal copilots. Clone the repo and start building your own."

**Summary line:** "It is all in enterprise-ready HorizonDB."


---

## Pre-Demo Setup Checklist

| Task | Status | Notes |
|------|--------|-------|
| `content` column on `product_metadata_demo` | Done | `concat_ws` of title, description, categories, store, features |
| RAG pipeline created + run | In progress | Chunks + embeds on `content` column |
| DiskANN index on embeddings | Needed | `USING diskann (embedding vector_cosine_ops)` |
| pg_fts BM25 index | Needed | `USING fts (title text_fts_ops, store text_fts_ops)` |
| `style_tagger` pipeline run | Blocked | `default-chat` model deployment not found — need to deploy a chat model on the Azure OpenAI endpoint |
| AGE extension installed | Done | `CREATE EXTENSION age` on `build_2026` |
| Style graph built | Done (test) | 60 Products, 7 Styles, 6 Categories, 12 SIMILAR_TO edges. Tested on `product_sample` subset |
| Seed product identified | Done | Product 10414: WLIVE Lift Top Coffee Table (Mid-Century Modern, Coffee Tables) |
| SIMILAR_TO edges tested | Done | 2-hop query returns Industrial Bookcases and Lamps from Mid-Century Modern seed |
| Zava Designer Agent running | Needed | `cd zava-designer-agent-ui-demo && npm run dev:full` — server on :3001, UI on :5180 |
| Zava Designer Agent `.env` pointed at demo server | Needed | `PGHOST`, `PGDATABASE=postgres`, `PGUSER`, `PGPASSWORD` for May12-Horizon |
| Tool trace panel visible | Needed | Ensure trace accordion is open before demo so audience sees tool-by-tool execution |