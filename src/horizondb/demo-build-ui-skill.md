# Zava Designer Agent — Live Build Playbook

How we built this demo from scratch using Copilot, and how to recreate it live on stage.

---

## What We Built

An AI-powered room designer agent called **Zava Designer Agent** that:
- Shows a real photo of a Brooklyn loft (empty state → furnished state transition)
- Lets users click "Design My Room" to trigger a 6-tool AI pipeline
- Calls HorizonDB PostgreSQL in real time — LLM analysis, hybrid search, graph traversal, reranking
- Places interactive product dots on the furnished room photo, positioned by category
- Shows a prioritized product list with real images, prices, and ratings from a 100K product catalog
- Tracks budget in real time with a bottom bar
- Exposes two trace views: **Query Trace** (pipeline steps) and **Agent Details** (raw tool calls with SQL + JSON)

**Tech stack:** React 18 + Vite 6 (frontend on `:5180`) + Express 4 + node-postgres (backend on `:3001`). Single CSS file (~2000 lines), no component library. Inter font via Google Fonts. Light theme with terra cotta (`#C45C3A`) accent.

---

## Architecture

### App Flow

```
User clicks "✨ Design My Room"
  → POST /api/design-room (Express backend)
  → 6-tool pipeline executes against HorizonDB
  → Response: { products[], trace[] }
  → Room photo transitions empty → furnished (with blur animation)
  → Product dots appear at category-keyed positions
  → Suggestions panel slides in from right
  → Budget footer appears with total / remaining
```

### Frontend State Machine

```
[Empty Room]  ──click──►  [Designing]  ──API done──►  [Designed]
                          designStep 0→6               isDesigned=true
                          blur ramps 0→18px            showSuggestions=true
                          loading steps animate         product dots render
```

---

## Backend: The 6-Tool Pipeline (server.js)

`POST /api/design-room` runs 6 tools sequentially (with parallelization where possible). Each tool returns `{ tool, duration, sql, input, output }` for the trace panel.

### Tool 1: `analyzeRoomPhoto(imageUrl, theme)`
- **Calls:** `azure_ai.generate()` — LLM reads the room photo
- **Returns:** style, colors[], existing furniture[], gaps[], mood
- **Fallback:** Hardcoded defaults if LLM fails (demo stability)

### Tool 2: `getSemanticContext(roomDescription, theme)`
- **Calls:** `pg_catalog` column comments + `semantic_dictionary` table
- **Returns:** column metadata, expanded search terms, filter hints
- **Parallelized with Tool 1** via `Promise.all()`

### Tool 3: `hybridSearchProducts(searchQuery, priorities, brands, demoMode)`
- **Calls:** `ai.search()` × 6 categories in parallel
- **Engine:** BM25 (pg_fts) + DiskANN (pgvector) + RRF fusion + semantic reranking
- **Categories:** Chairs, Coffee Tables, Lamps & Lighting, Area Rugs, Bookcases/Standing Shelf Units, Wall Art
- **Filter:** `average_rating >= 4.0 AND price_num > 25`
- **Limit:** 5 results per category
- **Demo mode:** Uses a fixed query string for repeatable results

### Tool 4: `findRelatedProducts(productIds, limit)`
- **Calls:** `bought_together` JSONB lookups + same-category fallback
- **Seeds:** Top 5 products from hybrid search
- **Parallelized:** All 5 seed lookups run via `Promise.all()`
- **Alternative:** `findRelatedProductsGraph()` uses Apache AGE Cypher traversal (toggled by `useGraph` flag)

### Tool 5: `filterProducts(products, budget, numCategories)`
- **Calls:** SQL `WHERE` on `product_metadata_demo`
- **Filter:** `price_num <= budget/numCategories AND average_rating >= 4.0`

### Tool 6: `curateRoomPicks(products, roomDescription, budget)`
- **Calls:** `azure_ai.rank()` — semantic reranking against room description
- **Boosted products for demos:** `BOOSTED_IDS = [3522, 40868, 74586, 36938, 74793]` always included (Lamp, Coffee Table, Wall Art, Glass Corner Shelf, DHP Mid Century Chair). This is because we want deterministic results for the live demo.
- **Selection:** Best 1 per category (storage gets 2), budget-aware cutoff
- **Fallback:** Top 7 by RRF score if rerank fails

### Key Constants

```javascript
CATEGORY_MAP = {
  seating: 'Chairs',
  tables: 'Coffee Tables',
  lighting: 'Lamps & Lighting',
  rugs: 'Area Rugs',
  storage: ['Bookcases', 'Standing Shelf Units'],
  decor: 'Wall Art',
}

BOOSTED_IDS = [3522, 40868, 74586, 36938, 74793]
```

### Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/api/design-room` | Full 6-tool agent pipeline |
| GET | `/api/health` | DB connection check |

---

## Frontend Components

### App.jsx — Main Layout & State
- Header: Logo, nav, "Show/Hide Picks" toggle, "⚡ How did this work?" trace toggle, active users count
- Center: `RoomView` + "⚙️ Agent Details" button + "🎨" settings FAB + `ChatBubble`
- Right sidebar: `SuggestionsPanel` (slides in after design)
- Overlays: `QueryTrace`, `AgentTrace`, `DesignDrawer`
- Footer: Budget bar with total/remaining, "Share Design" + "Add to Cart" buttons
- `handleDesignMyRoom()`: Animates designStep 0→6 (800ms intervals) while API call runs in parallel

### RoomView.jsx — Room Photo + Product Dots
- **Empty state:** `/room-empty.jpg` with "Your empty Brooklyn loft" label + "✨ Design My Room" button
- **Designing state:** Progressive blur (0→18px) with 6-step loading indicator
- **Designed state:** `/room-furnished.jpg` with floating product dots + "Redesign" button
- **Dot positioning:** Category-keyed (not index-based) via `CATEGORY_POSITIONS`:
  ```
  tables:   { top: '65%', left: '48%' }
  seating:  { top: '52%', left: '82%' }
  lighting: { top: '63%', left: '60%' }
  rugs:     { top: '75%', left: '50%' }
  storage:  [{ top: '55%', left: '22%' }, { top: '50%', left: '8%' }]  // 2 slots
  decor:    { top: '20%', left: '48%' }
  ```
- `sortProductsByCategory()` ensures stable dot ordering
- `getProductPosition()` resolves position per category with counting (storage can have 2 dots)
- Tooltip cards (240px) flip below/left/right near edges, z-index 50 on hover
- Click on dot highlights product in suggestions panel

### QueryTrace.jsx — Pipeline Steps Visualization
- Modal overlay triggered by "⚡ How did this work?"
- 6-step vertical timeline with sequential reveal (400ms intervals)
- Steps: Data Ingestion → Embedding → Hybrid Search → Graph Traversal → AI Reranking → Results
- Footer stats: "6 AI operations · 1 database · 1 SQL query · 0 external services"

### AgentTrace.jsx — Raw Tool Call Details
- Modal overlay triggered by "⚙️ Agent Details"
- Shows all 6 tool calls with expandable SQL, Input JSON, Output JSON
- "LIVE" badge when showing real trace data (vs fake fallback)
- Staggered reveal animation (350ms per tool)
- Fake fallback durations: 1200ms, 80ms, 1000ms, 400ms, 45ms, 1500ms

### ChatBubble.jsx — Floating Chat Panel
- FAB button (💬) bottom-left, toggles 380×460px panel
- Header: Zava logo + "Zava Designer Agent" + "● Online" status
- Welcome message: "Hey! I can see your Brooklyn loft…"
- 3 suggested prompts (clickable chips)
- 1.5s thinking animation (3 bouncing dots) before AI response
- Calls `onDesignReady()` after response

### SuggestionsPanel.jsx — Right Sidebar
- Budget tracker with progress bar (green → yellow → red)
- Product cards sorted by priority, with priority rank badges (#1, #2, #3)
- Auto-scrolls and pulses card when product dot is clicked
- Empty state: "AI picks will appear here"

### ProductCard.jsx — Individual Product Display
- Product image (120px), priority badge, brand, category tag, name, reason
- Star rating (★/☆) + review count
- "Add to Room" / "Remove" toggle button
- Hover: border highlight + shadow lift

### DesignDrawer.jsx — Settings Overlay
- 340px fixed-left drawer with backdrop
- Sections: Room Theme (6 options), Budget (slider 500–10K), Room Photo URL, Pricing Preference toggle, Demo Mode toggle, Preferred Brands (10 chips), Priority Focus (multi-select up to 3)

---

## File Architecture

```
zava-designer-agent-ui-demo/
├── .env                      # PGHOST, PGPORT, PGDATABASE, PGUSER, PGPASSWORD
├── server.js                 # Express backend — 6-tool pipeline, ~800 lines
├── package.json              # React 18, Vite 6, Express 4, pg, dotenv, cors
├── vite.config.js            # Dev server :5180, proxy /api → :3001
├── index.html                # Entry point, Inter font, title "Zava Designer Agent"
├── demo-build-skill.md       # This file
├── public/
│   ├── room-empty.jpg        # Brooklyn loft — empty (before design)
│   ├── room-furnished.jpg    # Brooklyn loft — furnished (after design)
│   ├── room.jpg              # Original room photo
│   ├── zava-logo.png         # Brand logo (PNG)
│   └── zava-logo.svg         # Brand logo (SVG)
├── src/
│   ├── App.jsx               # Main layout, state, API call, all panels orchestrated
│   ├── main.jsx              # React entry point
│   ├── index.css             # ALL styles (~2000 lines, light theme, CSS custom props)
│   ├── components/
│   │   ├── AgentTrace.jsx    # Tool call details overlay (SQL + JSON per tool)
│   │   ├── ChatBubble.jsx    # Floating chat panel with suggested prompts
│   │   ├── DesignDrawer.jsx  # Settings drawer (theme, budget, brands, priorities)
│   │   ├── DesignPanel.jsx   # Compact settings panel (desktop, left sidebar)
│   │   ├── ProductCard.jsx   # Individual product card (image, price, rating, toggle)
│   │   ├── QueryTrace.jsx    # Pipeline steps visualization (vertical timeline)
│   │   ├── RoomView.jsx      # Room photo + product dots + blur transition
│   │   └── SuggestionsPanel.jsx  # Right sidebar, budget tracker, product list
│   └── data/
│       └── mockData.js       # 7 fallback products, themes, brands, categories, colors, icons
```

---

## How to Run

```bash
cd playground/build_2026/zava-designer-agent-ui-demo
npm install

# Terminal 1: Backend
node server.js
# → Zava Designer Agent on http://localhost:3001

# Terminal 2: Frontend
npm run dev
# → http://localhost:5180 (proxies /api → :3001)
```

Requires `.env` with PostgreSQL credentials:
```
PGHOST=apr1horizondbai.ed2f11dc7a46.centralus.horizondb.azure.com
PGPORT=5432
PGDATABASE=build_2026
PGUSER=...
PGPASSWORD=...
```

---

## Database Reference

```
Host:     apr1horizondbai.ed2f11dc7a46.centralus.horizondb.azure.com
Database: build_2026
Table:    product_metadata_demo (~100K rows, ~1.8 GB)
Columns:  id, title, description, price, average_rating, rating_number,
          features, images (jsonb), store, categories (jsonb),
          details (jsonb), parent_asin, content, embedding
```

Key queries:
```sql
-- Extract product image URL
SELECT images->0->>'hi_res' AS image_url FROM product_metadata_demo WHERE id = 3522;

-- Hybrid search (what ai.search does under the hood)
SELECT * FROM ai.search(
    query => 'mid-century modern chair',
    source_table => 'product_metadata_demo',
    embedding_column => 'embedding',
    rerank => true,
    filter => 'categories @> ''["Chairs"]'' AND average_rating >= 4.0'
);

-- Semantic reranking
SELECT id, rank, score FROM azure_ai.rank($1::text, $2::text[], $3::int[]);
```

---

## Design Tokens (CSS Custom Properties)

```css
--bg: #F8F6F3;              /* Off-white background */
--surface: #FFFFFF;          /* Card/panel white */
--surface-alt: #F3F0EB;     /* Subtle alt surface */
--primary: #C45C3A;          /* Rust/terra cotta accent */
--primary-light: #F5EBE6;   /* Primary tint */
--primary-hover: #A84D30;   /* Primary darkened */
--text: #1C1917;             /* Dark text */
--text-secondary: #78716C;  /* Medium gray */
--text-tertiary: #A8A29E;   /* Light gray */
--border: #E7E5E4;           /* Light border */
--success: #16A34A;          /* Budget on-track */
--warning: #E8A317;          /* Budget caution */
--danger: #DC2626;           /* Budget over */
--radius: 10px;
--header-h: 60px;
--footer-h: 64px;
--panel-right-w: 360px;
```
