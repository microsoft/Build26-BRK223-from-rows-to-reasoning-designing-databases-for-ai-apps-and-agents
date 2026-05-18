/*============================================================================
  BRK223 — 03b_runbook_chunks.sql
  -----------------------------------------------------------------------------
  Populates dbo.RunbookChunk from dbo.Runbook using AI_GENERATE_CHUNKS
  (SQL Server 2025 built-in TVF) + AI_GENERATE_EMBEDDINGS, then builds a
  DiskANN vector index on the chunks.

  Story: chunks are the right unit for RAG retrieval and we get a real
  vector index seek on the runbook corpus instead of brute-force scan.

  Run AFTER: 01_schema.sql (creates RunbookChunk table)
             02_seed_corpus.sql (seeds Runbook with expanded content)

  Compat 170 required for AI_GENERATE_CHUNKS.
============================================================================*/
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET NUMERIC_ROUNDABORT OFF;
GO

USE zavalivesitedb;
GO

PRINT '>>> 03b_runbook_chunks.sql starting...';
GO

-- Drop existing vector index first (table cannot be truncated while indexed)
IF EXISTS (SELECT 1 FROM sys.indexes
           WHERE name = N'vec_runbook_chunk_embedding'
             AND object_id = OBJECT_ID(N'dbo.RunbookChunk'))
    DROP INDEX vec_runbook_chunk_embedding ON dbo.RunbookChunk;
GO

TRUNCATE TABLE dbo.RunbookChunk;
GO

-- Chunk every runbook and embed each chunk in a single INSERT...SELECT.
-- CHUNK_SIZE 50 + OVERLAP 10 yields ~1000 chunks over the expanded
-- 20-runbook corpus -- enough rows for the optimizer to prefer DiskANN
-- over a brute-force scan on the chunk table.
INSERT dbo.RunbookChunk (RunbookId, ChunkOrder, ChunkOffset, ChunkLength, ChunkText, Embedding)
SELECT  rb.RunbookId,
        c.chunk_order,
        c.chunk_offset,
        c.chunk_length,
        c.chunk,
        AI_GENERATE_EMBEDDINGS(c.chunk USE MODEL OllamaMxbai)
FROM    dbo.Runbook AS rb
CROSS APPLY AI_GENERATE_CHUNKS(
    SOURCE     = rb.Content,
    CHUNK_TYPE = FIXED,
    CHUNK_SIZE = 50,
    OVERLAP    = 10
) AS c;
GO

DECLARE @count int = (SELECT COUNT(*) FROM dbo.RunbookChunk);
PRINT '  RunbookChunk populated. Row count: ' + CAST(@count AS varchar(10));
GO

-- Build the DiskANN vector index on the chunk embeddings.
CREATE VECTOR INDEX vec_runbook_chunk_embedding
    ON dbo.RunbookChunk (Embedding)
    WITH (METRIC = 'cosine');
GO
PRINT '  vec_runbook_chunk_embedding built.';
GO

-- Verify health
SELECT vi.name,
       vi.vector_index_type,
       vi.distance_metric,
       JSON_VALUE(vi.build_parameters, '$.Version') AS version
FROM   sys.vector_indexes vi
WHERE  vi.object_id = OBJECT_ID(N'dbo.RunbookChunk');
GO

PRINT '>>> 03b_runbook_chunks.sql complete.';
GO
