-- Zava Room Designer Agent 
-- A tool that helps users design their living spaces by suggesting products from an 
-- ecommerce catalog based on a photo of their room.

-- ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
-- DATA RETRIEVAL: Real Queries for Roommate UI Demo
-- ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

CREATE EXTENSION IF NOT EXISTS pg_fts;
CREATE EXTENSION IF NOT EXISTS pg_diskann;

-- Using pg_fts for BM25 Full text search
SET search_path = public, pgfts, "$user";
CREATE INDEX IF NOT EXISTS idx_product_rag_fts ON public.product_rag_pipeline_build_2026_output
USING fts (chunk_text pgfts.text_fts_ops);

-- Using pg_diskann for vector index
CREATE INDEX IF NOT EXISTS idx_product_rag_diskann ON public.product_rag_pipeline_build_2026_output
USING diskann (embedding vector_cosine_ops);

-- =============================================================================
-- Product Search: ai.search() with semantic ranking and category filters
-- Searches for furniture and decor matching the room design query
-- ai.search is currently a custom stored proc at //Build, it will be released in HorizonDB the Summer 2026
-- For more information on the hybrid search, check Search "RRF fusion: vector + fulltext" in setup/ai-search.sql - Line 777
-- =============================================================================

-- 1. Seating
SELECT product.id, product.title, product.price, product.category, search.score
FROM ai.search(
    query => 'mid-century modern furniture for Brooklyn loft living room with wood tones and dark vibe',
    source_table => 'product_rag_pipeline_build_2026_output',
    content_column => 'chunk_text',
    search_type => 'hybrid',
    top_k => 10) search 
JOIN product_rag_pipeline_build_2026_output product_output ON product_output.id = search.id
JOIN product_sample product ON product.id = product_output.doc_id
ORDER BY search.score DESC;

-- More advanced search with reranking
SELECT product.id, product.title, product_output.chunk_text, product.price, product.category, search.score
FROM ai.search(
    query => 'mid-century modern furniture for Brooklyn loft living room with wood tones and dark vibe',
    source_table => 'product_rag_pipeline_build_2026_output',
    content_column => 'chunk_text',
    search_type => 'hybrid',
    rerank => true, -- Added reranking
    top_k => 10) search 
JOIN product_rag_pipeline_build_2026_output product_output ON product_output.id = search.id
JOIN product_sample product ON product.id = product_output.doc_id
ORDER BY search.score DESC;

-- What changes in the results:
--    - Baseline ranks the DHP white mid-century chair at #1 (strong keyword
--      + vector match on "mid-century modern").
--    - Rerank reads the full intent — "wood tones AND dark vibe" — and the
--      white chair conflicts with "dark vibe", so it drops out of the top 10.
--    - Walnut / dark wood pieces rise: WLIVE grey lift-top coffee table,
--      Household Essentials walnut cubby, VASAGLE rustic brown bookcase.