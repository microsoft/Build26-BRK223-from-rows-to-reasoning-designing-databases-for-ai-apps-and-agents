/*============================================================================
  BRK223 — 03b_runbook_chunks.sql
  -----------------------------------------------------------------------------
  Populates dbo.RunbookChunk from dbo.Runbook using AI_GENERATE_CHUNKS
  (SQL Server 2025 built-in TVF) + AI_GENERATE_EMBEDDINGS.

  Story: chunks are the right unit for RAG retrieval.

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

TRUNCATE TABLE dbo.RunbookChunk;
GO

-- Chunk every runbook by SECTION (blank-line delimited) rather than by
-- fixed character count. The runbook corpus has a known, consistent
-- structure: SYMPTOMS. / DIAGNOSTIC SIGNALS. / ROOT CAUSE. /
-- MITIGATION STEPS. / VERIFICATION. / ROLLBACK. / POST-INCIDENT. /
-- REFERENCES. Each section is separated by a blank line (CHAR(10)+CHAR(10)).
--
-- Why not AI_GENERATE_CHUNKS(FIXED)? CHUNK_TYPE = FIXED is the only mode
-- SQL Server 2025 ships with. It splits at exact character boundaries
-- regardless of word/sentence position, so every chunk visibly ends
-- mid-word in agent output. OVERLAP (percentage, 0-50) helps the *next*
-- chunk recover the clipped word but does not fix the chunk being shown
-- to the user.
--
-- Section-based chunks are semantically coherent, never chop words, and
-- produce ~8 chunks/runbook (~160 total across 20 runbooks) -- still
-- plenty for DiskANN to find neighbors during hybrid_search.
--
-- Implementation: normalize CRLF -> LF, replace the blank-line delimiter
-- with the ASCII Unit Separator (CHAR(31)) so STRING_SPLIT (single-char
-- separator) can split cleanly, then enable_ordinal preserves order.
WITH normalized AS (
    SELECT  rb.RunbookId,
            REPLACE(
                REPLACE(REPLACE(rb.Content, CHAR(13)+CHAR(10), CHAR(10)), CHAR(13), CHAR(10)),
                CHAR(10)+CHAR(10),
                CHAR(31)
            ) AS Content
    FROM dbo.Runbook AS rb
),
sections AS (
    SELECT  n.RunbookId,
            s.ordinal       AS RawOrder,
            LTRIM(RTRIM(REPLACE(s.value, CHAR(10), ' '))) AS ChunkText
    FROM normalized AS n
    CROSS APPLY STRING_SPLIT(n.Content, CHAR(31), 1) AS s
    WHERE LEN(LTRIM(RTRIM(s.value))) > 0
)
INSERT dbo.RunbookChunk (RunbookId, ChunkOrder, ChunkOffset, ChunkLength, ChunkText, Embedding)
SELECT  s.RunbookId,
        ROW_NUMBER() OVER (PARTITION BY s.RunbookId ORDER BY s.RawOrder) AS ChunkOrder,
        0                              AS ChunkOffset,
        CAST(LEN(s.ChunkText) AS int)  AS ChunkLength,
        s.ChunkText,
        AI_GENERATE_EMBEDDINGS(s.ChunkText USE MODEL OllamaMxbai)
FROM sections AS s;
GO

DECLARE @count int = (SELECT COUNT(*) FROM dbo.RunbookChunk);
PRINT '  RunbookChunk populated. Row count: ' + CAST(@count AS varchar(10));
GO

PRINT '>>> 03b_runbook_chunks.sql complete.';
GO
