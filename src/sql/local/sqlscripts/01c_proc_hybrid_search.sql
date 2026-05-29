/*============================================================================
  BRK223 - 01c_proc_hybrid_search.sql
  -----------------------------------------------------------------------------
  Extracted from 01_schema.sql for stage readability.

  Section 3) PROC FOR VECTOR SEARCH (usp_HybridSearch).
============================================================================*/
USE zavalivesitedb;
GO

PRINT '>>> 01c_proc_hybrid_search.sql starting...';
GO

IF OBJECT_ID(N'dbo.usp_HybridSearch', N'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_HybridSearch;
GO
CREATE PROCEDURE dbo.usp_HybridSearch
    @TenantId   nvarchar(100),
    @Question   nvarchar(max),
    @ErrorCode  nvarchar(20)  = NULL,
    @Service    nvarchar(50)  = NULL,
    @TopK       int           = 5
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @qvec vector(1024) =
        AI_GENERATE_EMBEDDINGS(@Question USE MODEL OllamaMxbai);

    DECLARE @lTenantId  nvarchar(100) = @TenantId;
    DECLARE @lErrorCode nvarchar(20)  = @ErrorCode;
    DECLARE @lService   nvarchar(50)  = @Service;
    DECLARE @lTopK      int           = @TopK;

    DECLARE @incidents TABLE (
        source    nvarchar(20),
        id        nvarchar(60),
        title     nvarchar(400),
        body      nvarchar(max),
        distance  float,
        extra     nvarchar(max)
    );

    INSERT @incidents (source, id, title, body, distance, extra)
    SELECT TOP (@lTopK) WITH APPROXIMATE
           N'incident',
           CAST(a.IncidentId AS nvarchar(60)),
           a.Service + N' / ' + ISNULL(a.Severity, N''),
           ISNULL(a.RootCause, N'') + NCHAR(10) + NCHAR(10) + ISNULL(a.Mitigation, N''),
           r.distance,
           CAST(a.Tags AS nvarchar(max))
    FROM   VECTOR_SEARCH(
             TABLE      = dbo.IncidentArchive AS a,
             COLUMN     = Embedding,
             SIMILAR_TO = @qvec,
             METRIC     = 'cosine'
           ) AS r
    WHERE  a.TenantId = @lTenantId
       AND (@lErrorCode IS NULL
            OR JSON_VALUE(a.Tags, '$.errorCode') = @lErrorCode)
    ORDER BY r.distance;

    DECLARE @runbooks TABLE (
        source    nvarchar(20),
        id        nvarchar(60),
        title     nvarchar(400),
        body      nvarchar(max),
        distance  float,
        extra     nvarchar(max)
    );

    IF @lService IS NULL
    BEGIN
        INSERT @runbooks (source, id, title, body, distance, extra)
        SELECT TOP (@lTopK)
               N'runbook',
               CAST(rc.RunbookId AS nvarchar(40)) + N'#' + CAST(rc.ChunkOrder AS nvarchar(19)),
               rb.Title,
               rc.ChunkText,
               vector_distance('cosine', rc.Embedding, @qvec) AS distance,
               NULL
        FROM   dbo.Runbook      AS rb
        JOIN   dbo.RunbookChunk AS rc ON rc.RunbookId = rb.RunbookId
        ORDER BY distance;
    END
    ELSE
    BEGIN
        INSERT @runbooks (source, id, title, body, distance, extra)
        SELECT TOP (@lTopK)
               N'runbook',
               CAST(rc.RunbookId AS nvarchar(40)) + N'#' + CAST(rc.ChunkOrder AS nvarchar(19)),
               rb.Title,
               rc.ChunkText,
               vector_distance('cosine', rc.Embedding, @qvec) AS distance,
               NULL
        FROM   dbo.Runbook      AS rb
        JOIN   dbo.RunbookChunk AS rc ON rc.RunbookId = rb.RunbookId
        WHERE  JSON_VALUE(rb.Tags, '$.service') = @lService
        ORDER BY distance;
    END

    SELECT source, id, title, body, distance, extra
    FROM   @incidents
    UNION ALL
    SELECT source, id, title, body, distance, extra
    FROM   @runbooks
    ORDER BY distance;
END
GO

PRINT '  usp_HybridSearch created.';
GO

PRINT '>>> 01c_proc_hybrid_search.sql complete.';
GO
