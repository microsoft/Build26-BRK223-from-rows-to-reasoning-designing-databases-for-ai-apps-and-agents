SELECT * FROM product_sample LIMIT 5;

-- ---------------------------------------------------------------------------
-- ACT 1 — RAG Pipeline in Seconds
-- ---------------------------------------------------------------------------

SELECT ai.create_pipeline(
    name    => 'product_rag_pipeline_build_2026',
    source  => ai.table_source('product_sample'),
    steps   => ARRAY[
        ai.chunk(input => 'content',
                 chunk_size => 1024, 
                 overlap => 128), -- generates chunk_text, chunk_index, etc.
        ai.embed(model => 'default-embedding', 
                 input_column => 'chunk_text',
                 dimensions => 1536,
                 batch_size => 10)
    ],
    trigger => 'on_change'
);
-- Auto-creates: public.{pipeline_name}_output (doc_id, chunk_index, chunk_text, embedding, ...)

-- Run it once to backfill the existing rows.
SELECT ai.run('product_rag_pipeline_build_2026');

-- ---------------------------------------------------------------------------
-- ACT 1B — Monitor Pipeline 
-- ---------------------------------------------------------------------------

SELECT * FROM ai.status('product_rag_pipeline_build_2026');
SELECT * FROM ai.list_pipelines();

-- ---------------------------------------------------------------------------
-- ACT 1C — Look at output table
-- ---------------------------------------------------------------------------

SELECT count(*) FROM product_rag_pipeline_build_2026_output;
SELECT * FROM product_rag_pipeline_build_2026_output;

-- ---------------------------------------------------------------------------
-- ACT 1D — Vector Search
-- ---------------------------------------------------------------------------
-- Semantic search against the catalog.
SELECT doc_id, chunk_text, chunk_index
     FROM product_rag_pipeline_build_2026_output
     ORDER BY embedding <=> azure_openai.create_embeddings(
                                'default-embedding',
                                'Best chair that is comfortable for a living room')::vector
     LIMIT 5;
    
-- ---------------------------------------------------------------------------
-- ACT 2 — Auto-Embedding on New Rows
-- ---------------------------------------------------------------------------

-- 2a. The most mundane thing imaginable: just add a new product.
--     Because trigger => 'on_change' + incremental_column => 'updated_at',
--     ONLY this row gets chunked and embedded — not the whole table.
INSERT INTO product_sample (title, content)
VALUES (
    'New Chair for Living Room',
    'A comfortable and stylish chair perfect for any living room setting. Features ergonomic design, high-quality materials, and a modern aesthetic that complements various interior styles.'
);

SELECT count(*) FROM product_rag_pipeline_build_2026_output;

-- 2b. Watch the new doc show up in the sink table within a few seconds.
--     Re-run this a couple of times during the narration.
SELECT *
     FROM product_rag_pipeline_build_2026_output
     ORDER BY embedding <=> azure_openai.create_embeddings(
                                'text-embedding-3-small',
                                'Best chair that is comfortable for a living room')::vector
     LIMIT 5;