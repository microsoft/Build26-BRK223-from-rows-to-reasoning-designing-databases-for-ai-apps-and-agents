CREATE EXTENSION IF NOT EXISTS pg_durable;
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS azure_ai;
CREATE EXTENSION IF NOT EXISTS pg_fts;
CREATE EXTENSION IF NOT EXISTS pg_diskann;

-- =============================================================================
-- SETUP: pg_fts Extension & BM25 Index
-- =============================================================================

SET search_path = public, pgfts;

CREATE EXTENSION IF NOT EXISTS pg_fts;

CREATE INDEX IF NOT EXISTS idx_product_sample_fts ON public.product_rag_pipeline_build_2026_output
USING fts (chunk_text text_fts_ops);

CREATE INDEX IF NOT EXISTS idx_product_sample_diskann ON public.product_rag_pipeline_build_2026_output
USING diskann (embedding vector_cosine_ops);

-- Add id PK (auto-generated, not tied to doc_id since chunks share doc_ids)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'product_rag_pipeline_build_2026_output' AND column_name = 'id'
    ) THEN
        EXECUTE 'ALTER TABLE product_rag_pipeline_build_2026_output ADD COLUMN id SERIAL PRIMARY KEY';
    END IF;
END
$$;