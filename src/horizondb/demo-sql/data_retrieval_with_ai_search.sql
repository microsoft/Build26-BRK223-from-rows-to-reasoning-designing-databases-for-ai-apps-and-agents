
-- ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
-- DATA RETRIEVAL: Real Queries for Roommate UI Demo
-- ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

CREATE EXTENSION IF NOT EXISTS pg_fts;
SET search_path = public, pgfts, "$user";

CREATE INDEX IF NOT EXISTS idx_product_rag_3_fts ON public.product_rag_pipeline_build_2026_5_output
USING fts (chunk_text pgfts.text_fts_ops);

CREATE INDEX IF NOT EXISTS idx_product_rag_3_diskann ON public.product_rag_pipeline_build_2026_5_output
USING diskann (embedding vector_cosine_ops);

-- =============================================================================
-- Room Analysis: azure_ai.generate() with image URL
-- Describes the room photo to identify style, furniture, colors, and gaps
-- =============================================================================
-- 1. 
-- SELECT azure_ai.generate(
--   'Recommended the style for this. https://i.ibb.co/p61fm20N/Designer.png
--   ['Mid-Century Modern', 'Industrial', 'Scandinavian','Bohemian', 'Farmhouse', 'Minimalist']'
-- );

-- 2. 
-- SELECT azure_ai.generate(
--   'Analyze this living room photo. https://i.ibb.co/p61fm20N/Designer.png
--   give a semantic description of the room'
-- );

-- =============================================================================
-- Product Search: ai.search() with semantic ranking and category filters
-- Searches for furniture and decor matching the room design query
-- For more information on the hybrid search, check Search "RRF fusion: vector + fulltext" in setup/ai-search.sql
-- =============================================================================

-- 1. Seating
SELECT product.id, product.title, product.price, product.category, search.score
FROM ai.search(
    query => 'mid-century modern furniture for Brooklyn loft living room with wood tones and dark vibe',
    source_table => 'product_rag_pipeline_build_2026_output',
    content_column => 'chunk_text',
    embedding_column => 'embedding',
    embedding_model => 'default-embedding',
    search_type => 'hybrid',
    top_k => 50) search 
JOIN product_rag_pipeline_build_2026_output product_output ON product_output.id = search.id
JOIN product_sample product ON product.id = product_output.doc_id
WHERE product.category = 'Chairs'; -- Run across 7 categories: Chairs, Coffee Tables, Lamps & Lighting, Area Rugs, Bookcases, Storage & Organization, Wall Art.