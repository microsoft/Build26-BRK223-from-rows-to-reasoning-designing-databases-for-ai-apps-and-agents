-- ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
-- DATA GRAPH QUERY: Querying the Style Graph
-- ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

-- ─── ACT 1: Pipeline usage ─────────────────────
SELECT ai.create_pipeline(
    name   => 'style_tagger',
    source => ai.table_source('product_sample'),
    steps  => ARRAY[
        ai.extract(
            model        => 'default-chat',
            input_column => 'content',
            data         => ARRAY[
                                'style: string - the furniture design style, one of: Mid-Century Modern, Industrial, Scandinavian, Bohemian, Farmhouse, Minimalist'
            ]
        ),
        ai.generate(
            'default-chat',
            'Given this product, output ONLY a comma-separated list of 1-2 complementary furniture design styles from this list: Mid-Century Modern, Industrial, Scandinavian, Bohemian, Farmhouse, Minimalist. No explanation, just the style names.',
            'content'
        )
    ],
    trigger => 'on_change'
);

SELECT ai.run('style_tagger');

-- ─── ACT 2: Create style graph ─────────────────────
-- Create a graph from the style tagger output in the database, using setup/graph_creation.sql
-- \i setup/graph_creation.sql

-- Three node types, three edge types:
-- (:Product)-[:HAS_STYLE]->(:Style)           ← from ai.extract output
-- (:Product)-[:IN_CATEGORY]->(:Category)      ← from categories column
-- (:Style)-[:SIMILAR_TO]->(:Style)            ← from ai.generate output

-- ─── ACT 3 setup: Flash style pipeline output (~1 min) ─────────────────────
-- Show 5 rows — this is what feeds the graph
SELECT id, title, extracted->'style' AS style, generated AS related_styles
FROM style_tagger_output LIMIT 5;

-- Verify style distribution
SELECT extracted->'style' AS style, COUNT(*) FROM style_tagger_output GROUP BY style ORDER BY count DESC;

-- ─── ACT 3: Graph queries ──────────────────────────────────────────────────

--- 2-HOP: The wow moment ---
-- The AI discovered style relationships → the graph traverses them
-- ASCII art representation of the graph
--        Product(2315)
--              ↓
--        [HAS_STYLE]
--              ↓
--        Style(Mid-Century Modern)
--              ↓
--        [SIMILAR_TO]
--              ↓
--        Style(Bohemian)
--              ↑
--        [HAS_STYLE]
--              ↑
--        Product(recommendation)

SET search_path = ag_catalog, "$user", public, pgfts;

-- "Products in styles SIMILAR to mine, across different categories"
SELECT * FROM ag_catalog.cypher('style_graph', $$
    MATCH (seed:Product {id: 2315})-[e1:HAS_STYLE]->(s:Style)-[e2:SIMILAR_TO]->(related:Style)<-[e3:HAS_STYLE]-(rec:Product)
    MATCH (seed)-[e4:IN_CATEGORY]->(seedCat:Category)
    MATCH (rec)-[e5:IN_CATEGORY]->(recCat:Category)
    WHERE seedCat.name <> recCat.name
    RETURN seed, e1, s, e2, related, e3, rec, e4, seedCat, e5, recCat
    LIMIT 10
$$) AS (seed agtype, e1 agtype, style agtype, e2 agtype, related agtype, e3 agtype, rec agtype, e4 agtype, seedCat agtype, e5 agtype, recCat agtype);


----- Bonus: Cooler Graphs (if time) ------

-- 1-HOP: Same style, cross-category
-- ASCII art representation of the graph
--        Product(2315)
--              ↓
--        [HAS_STYLE]
--              ↓
--        Style(Mid-Century Modern)
--              ↑
--        [HAS_STYLE]
--              ↑
--        Product(recommendation)

SET search_path = ag_catalog, "$user", public, pgfts;

-- "I picked this Chair. What rugs, lamps, and chairs match its style?"
SELECT * FROM ag_catalog.cypher('style_graph', $$
    MATCH (seed:Product {id: 2315})-[edge1:HAS_STYLE]->(s:Style)<-[edge2:HAS_STYLE]-(recommendation:Product)
    MATCH (seed)-[edge3:IN_CATEGORY]->(seedCat:Category)
    MATCH (recommendation)-[edge4:IN_CATEGORY]->(recCat:Category)
    WHERE seedCat.name <> recCat.name
    RETURN seed, edge1, s, edge2, recommendation, edge3, seedCat, edge4, recCat
    LIMIT 10
$$) AS (seed agtype, edge1 agtype, style agtype, edge2 agtype, recommendation agtype, edge3 agtype, seedCat agtype, edge4 agtype, recCat agtype);


-- "Which styles bridge the most categories?"
SELECT * FROM ag_catalog.cypher('style_graph', $$
    MATCH (p:Product)-[edge1:HAS_STYLE]->(s:Style),
          (p)-[edge2:IN_CATEGORY]->(c:Category)
    RETURN p, edge1, s, edge2, c
$$) AS (p agtype, edge1 agtype, s agtype, edge2 agtype, c agtype);


