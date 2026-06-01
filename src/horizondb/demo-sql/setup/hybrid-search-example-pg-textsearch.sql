CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS azure_ai;
CREATE EXTENSION IF NOT EXISTS pg_textsearch;

CREATE INDEX IF NOT EXISTS product_embedding_pipeline_output_bm25_idx
ON product_rag_pipeline_build_2026_output
USING bm25 (chunk_text)
WITH (text_config = 'english');

WITH
params AS (
    SELECT
        to_bm25query( 'mid-century modern furniture', 'product_embedding_pipeline_output_bm25_idx') AS q_bm25,
        azure_openai.create_embeddings( 'text-embedding-3-small', 'mid-century modern furniture')::vector AS q_vec
),
bm25 AS (
    SELECT
        p.doc_id, p.chunk_index,
        ROW_NUMBER() OVER (ORDER BY p.chunk_text <@> params.q_bm25) AS bm25_rank
    FROM product_rag_pipeline_build_2026_output p, params
    ORDER BY p.chunk_text <@> params.q_bm25
    LIMIT 50
),
vec AS (
    SELECT
        p.doc_id, p.chunk_index,
        ROW_NUMBER() OVER (ORDER BY p.embedding::vector <=> params.q_vec) AS vec_rank
    FROM product_rag_pipeline_build_2026_output p, params
    ORDER BY p.embedding::vector <=> params.q_vec
    LIMIT 50
)
SELECT
    p.doc_id, p.chunk_index, p.chunk_text, p.metadata,
    (1.0 / (60 + COALESCE(b.bm25_rank, 1000))) + (1.0 / (60 + COALESCE(v.vec_rank, 1000))) AS rrf_score
FROM product_rag_pipeline_build_2026_output p
LEFT JOIN bm25 b
    ON b.doc_id = p.doc_id AND b.chunk_index = p.chunk_index
LEFT JOIN vec v
    ON v.doc_id = p.doc_id AND v.chunk_index = p.chunk_index
WHERE b.doc_id IS NOT NULL OR v.doc_id IS NOT NULL
ORDER BY rrf_score DESC
LIMIT 10;