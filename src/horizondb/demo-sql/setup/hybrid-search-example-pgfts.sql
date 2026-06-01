CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_fts;
CREATE EXTENSION IF NOT EXISTS azure_ai;

-- Setup for Hybrid Search with pg_fts and vector

-- BM25 index over the searchable text columns
CREATE INDEX idx_products_fts
    ON product_rag_pipeline_build_2026_output
    USING fts (name, description);

WITH
-- Embed the query once and reuse it
query AS (
    SELECT
        'mid-century modern furniture' AS q_text,
        azure_openai.create_embeddings('default-embedding','mid-century modern furniture')::vector AS q_vec
),
-- Top-N BM25 results, ranked by relevance
bm25 AS (
    SELECT id,
           ROW_NUMBER() OVER () AS bm25_rank
    FROM product_rag_pipeline_build_2026_output, query
    WHERE pgfts.fts_query(query.q_text, 'idx_products_fts')
    LIMIT 50
),
-- Top-N vector results, ranked by cosine distance
vec AS (
    SELECT p.id,
           ROW_NUMBER() OVER (
               ORDER BY p.embedding <=> query.q_vec
           ) AS vec_rank
    FROM products p, query
    ORDER BY p.embedding <=> query.q_vec
    LIMIT 50
)
-- Reciprocal Rank Fusion
SELECT p.id, p.name, p.description,
       (1.0 / (60 + COALESCE(b.bm25_rank, 1000))) +
       (1.0 / (60 + COALESCE(v.vec_rank, 1000))) AS rrf_score
FROM products p
LEFT JOIN bm25 b ON b.id = p.id
LEFT JOIN vec  v ON v.id = p.id
WHERE b.id IS NOT NULL OR v.id IS NOT NULL
ORDER BY rrf_score DESC
LIMIT 10;