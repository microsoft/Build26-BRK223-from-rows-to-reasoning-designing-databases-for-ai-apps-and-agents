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
USING fts (chunk_text pgfts.text_fts_ops);

CREATE INDEX IF NOT EXISTS idx_product_sample_diskann ON public.product_rag_pipeline_build_2026_output
USING diskann (embedding vector_cosine_ops);