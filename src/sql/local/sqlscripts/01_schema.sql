/*============================================================================
  BRK223 — 01_schema.sql
  -----------------------------------------------------------------------------
  Tables, EXTERNAL MODELs, indexes for the Zava On-Call demo.

  Embedding width on this side: 1024 (mxbai-embed-large via Foundry Local).
  Cloud variant (Hyperscale) uses 1536 (text-embedding-3-small via AOAI).

  Beat 2 setup is critical:
    - JSON Index #1 on IncidentArchive.AlertPayload — CREATED here
    - DiskANN on IncidentArchive.Embedding          — CREATED here
    - JSON Index on IncidentArchive.Tags ($.errorCode) — INTENTIONALLY OMITTED.
      That index is added live on stage in Beat 2c via 02b_apply_fix.sql.
      Do not add it here.
============================================================================*/
USE zavalivesitedb;
GO

PRINT '>>> 01_schema.sql starting...';
GO

/*-----------------------------------------------------------
  EXTERNAL MODELs (container path)
  -----------------------------------------------------------
  Embeddings only — Azure SQL today supports MODEL_TYPE = EMBEDDINGS
  on EXTERNAL MODEL. Chat completions are invoked directly via
  sp_invoke_external_rest_endpoint inside usp_GenerateMitigation, with the
  endpoint URL parameterized (@ChatUrl) and a DATABASE SCOPED CREDENTIAL
  bound to the URL.

  Container side:
    EMBEDDINGS  -> OllamaMxbai      (mxbai-embed-large -> vector(1024))
    CHAT        -> sp_invoke against https://localhost:8444/v1/chat/completions (in-container)

  Cloud side (Hyperscale, deployed separately):
    EMBEDDINGS  -> AoaiTextEmbed3Small (text-embedding-3-small -> vector(1536))
    CHAT        -> sp_invoke against AOAI gpt-4o-mini deployment URL
-----------------------------------------------------------*/
IF EXISTS (SELECT 1 FROM sys.external_models WHERE name = N'OllamaMxbai')
    DROP EXTERNAL MODEL OllamaMxbai;
GO

CREATE EXTERNAL MODEL OllamaMxbai
WITH (
    LOCATION   = 'https://localhost:8444/v1/embeddings',
    API_FORMAT = 'OpenAI',
    MODEL_TYPE = EMBEDDINGS,
    MODEL      = 'mxbai-embed-large'
);
GO

PRINT '  EXTERNAL MODEL OllamaMxbai created (chat goes via sp_invoke).';
GO

/*-----------------------------------------------------------
  Tables
-----------------------------------------------------------*/
IF OBJECT_ID(N'dbo.Incident', N'U')        IS NOT NULL DROP TABLE dbo.Incident;
IF OBJECT_ID(N'dbo.IncidentArchive', N'U') IS NOT NULL DROP TABLE dbo.IncidentArchive;
IF OBJECT_ID(N'dbo.RunbookChunk', N'U')    IS NOT NULL DROP TABLE dbo.RunbookChunk;
IF OBJECT_ID(N'dbo.Runbook', N'U')         IS NOT NULL DROP TABLE dbo.Runbook;
IF OBJECT_ID(N'dbo.AppLog', N'U')          IS NOT NULL DROP TABLE dbo.AppLog;
GO

CREATE TABLE dbo.Incident
(
    IncidentId          int            IDENTITY(5000,1) NOT NULL CONSTRAINT PK_Incident PRIMARY KEY,
    TenantId            nvarchar(100)  NOT NULL,                 -- 'zava' | 'northwind' | ...
    Service             nvarchar(50)   NOT NULL,                 -- 'Payroll' | 'Auth' | ...
    Region              nvarchar(50)   NULL,
    Severity            nvarchar(10)   NOT NULL,                 -- 'sev1' | 'sev2' | 'sev3'
    Status              nvarchar(20)   NOT NULL CONSTRAINT DF_Incident_Status DEFAULT N'open',
    AlertPayload        json           NOT NULL,                 -- (1) JSON: Azure Monitor envelope
    EngineerNote        nvarchar(max)  NULL,                     -- on-call's first observations
    Tags                json           NULL,                     -- (3) JSON: regex-extracted tokens
    Embedding           vector(1024)   NULL,                     -- (5) embedding of EngineerNote
    ProposedMitigation  json           NULL,                     -- written by usp_GenerateMitigation
    CreatedAtUtc        datetime2(0)   NOT NULL CONSTRAINT DF_Incident_Created DEFAULT sysutcdatetime()
);
GO

CREATE TABLE dbo.IncidentArchive
(
    IncidentId          int            NOT NULL CONSTRAINT PK_IncidentArchive PRIMARY KEY,
    TenantId            nvarchar(100)  NOT NULL,
    Service             nvarchar(50)   NOT NULL,
    Region              nvarchar(50)   NULL,
    Severity            nvarchar(10)   NOT NULL,
    AlertPayload        json           NOT NULL,
    EngineerNote        nvarchar(max)  NULL,
    Tags                json           NULL,
    Embedding           vector(1024)   NOT NULL,                 -- corpus is pre-embedded
    RootCause           nvarchar(max)  NULL,
    Mitigation          nvarchar(max)  NULL,
    ResolvedAtUtc       datetime2(0)   NULL
);
GO

CREATE TABLE dbo.Runbook
(
    RunbookId           varchar(20)    NOT NULL CONSTRAINT PK_Runbook PRIMARY KEY,   -- 'Payroll.7'
    Title               nvarchar(200)  NOT NULL,
    Content             nvarchar(max)  NOT NULL,
    Tags                json           NULL,                     -- $.service, $.tags[*]
    Embedding           vector(1024)   NOT NULL                  -- whole-doc embedding (kept for compatibility)
);
GO

-- Chunked runbook content for fine-grained vector retrieval.
-- Populated in 03b_runbook_chunks.sql via AI_GENERATE_CHUNKS + AI_GENERATE_EMBEDDINGS.
CREATE TABLE dbo.RunbookChunk
(
    RunbookChunkId      bigint         IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_RunbookChunk PRIMARY KEY,
    RunbookId           varchar(20)    NOT NULL
        CONSTRAINT FK_RunbookChunk_Runbook REFERENCES dbo.Runbook(RunbookId) ON DELETE CASCADE,
    ChunkOrder          bigint         NOT NULL,
    ChunkOffset         bigint         NOT NULL,
    ChunkLength         int            NOT NULL,
    ChunkText           nvarchar(max)  NOT NULL,
    Embedding           vector(1024)   NOT NULL,
    INDEX ix_RunbookChunk_RunbookId NONCLUSTERED (RunbookId)
);
GO

/*-----------------------------------------------------------
  AppLog — APPEND-ONLY LEDGER table (Beat 3).
  -----------------------------------------------------------
  Tamper-evident, cryptographically verifiable application log.
  Replaces the parquet/ADLS path so the demo runs end-to-end on
  a single Azure SQL container with no external dependencies.
  Every row is hashed into the Merkle tree; rows can never be
  updated or deleted.
-----------------------------------------------------------*/
CREATE TABLE dbo.AppLog
(
    LogId        bigint        IDENTITY(1,1) NOT NULL CONSTRAINT PK_AppLog PRIMARY KEY,
    ts           datetime2(0)  NOT NULL,
    IncidentId   int           NOT NULL,
    level        nvarchar(20)  NOT NULL,
    message      nvarchar(1000) NOT NULL,
    INDEX ix_AppLog_Incident_Ts NONCLUSTERED (IncidentId, ts)
)
WITH (LEDGER = ON (APPEND_ONLY = ON));
GO

PRINT '  Tables created (incl. ledger AppLog).';
GO

/*-----------------------------------------------------------
  JSON indexes
  -----------------------------------------------------------
  See design.md §4.

  NOTE: No JSON index on IncidentArchive.Tags($.errorCode) — the
        archive query is DiskANN-driven (vec_archive_embedding); the
        errorCode predicate runs as a residual filter on the bookmark
        side, so a JSON index here would not be picked by the optimizer.
-----------------------------------------------------------*/
CREATE JSON INDEX ix_incident_alert_payload
    ON dbo.Incident (AlertPayload)
    FOR ('$.tenantId', '$.service', '$.region', '$.severity');
GO

CREATE JSON INDEX ix_incident_tags
    ON dbo.Incident (Tags)
    FOR ('$.errorCode', '$.build', '$.dependencyHost', '$.correlationId', '$.waitType', '$.kbRef');
GO

CREATE JSON INDEX ix_archive_alert_payload
    ON dbo.IncidentArchive (AlertPayload)
    FOR ('$.tenantId', '$.service', '$.region', '$.severity');
GO

-- Runbook side: ix_runbook_tags ($.service) IS the demo's JSON Index Seek.
-- usp_HybridSearch narrows the runbook corpus by $.service through this
-- index, then computes exact vector_distance over the resulting chunks.
CREATE JSON INDEX ix_runbook_tags
    ON dbo.Runbook (Tags)
    FOR ('$.service', '$.tags');
GO

PRINT '  JSON indexes created.';
GO

/*-----------------------------------------------------------
  Vector (DiskANN) indexes — DEFERRED to 01d_vector_indexes.sql.
  -----------------------------------------------------------
  DiskANN in Azure SQL needs a non-trivial row count to build
  (~256 rows in current CTP). We seed the corpus first
  (01c_seed_corpus.sql) and then create the indexes.
-----------------------------------------------------------*/
PRINT '  Vector indexes deferred — run 03_vector_indexes.sql after seeding.';
GO

/*-----------------------------------------------------------
  usp_HybridSearch — Beat 2 demo proc AND MCP-facing tool.
  -----------------------------------------------------------
  One statement, two specialized access paths composed by the optimizer:

    Incident side (large, weakly-tagged corpus, ~150k rows):
      Vector Index Seek on vec_archive_embedding (DiskANN, cosine).
      Structured predicates (tenant, errorCode) run as residual filters.

    Runbook side (small, well-tagged corpus, ~6k chunks):
      JSON Index Seek on ix_runbook_tags for $.service narrows the
      candidate set, then exact vector_distance over the resulting
      chunks — no DiskANN needed.

  Returns a SINGLE result set (a 'source' discriminator column makes
  rows self-identifying). DAB's stored-proc → MCP wrapper only surfaces
  the first result set, so emitting two would lose the runbooks. Single
  result set also keeps INSERT...EXEC into a temp table simple for the
  internal call from usp_GenerateMitigation.

  Columns: source ('incident' | 'runbook'), id, title, body, distance,
  extra (incident Tags JSON; NULL for runbook rows). Outer ORDER BY
  distance interleaves both kinds by relevance.
-----------------------------------------------------------*/
IF OBJECT_ID(N'dbo.usp_HybridSearch', N'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_HybridSearch;
GO
CREATE PROCEDURE dbo.usp_HybridSearch
    @TenantId   nvarchar(100),
    @Question   nvarchar(max),
    @ErrorCode  nvarchar(20)  = NULL,    -- if known; otherwise pass NULL
    @Service    nvarchar(50)  = NULL,    -- if known; narrows runbook side via JSON Index Seek
    @TopK       int           = 5
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @qvec vector(1024) =
        AI_GENERATE_EMBEDDINGS(@Question USE MODEL OllamaMxbai);

    -- Defeat parameter sniffing on @TenantId: at 1/6th tenant cardinality,
    -- the sniffed estimate makes the optimizer judge DiskANN+key-lookup
    -- more expensive than a scan. Copying to a local forces the optimizer
    -- to use the density-based estimate, which picks Vector Index Seek.
    DECLARE @lTenantId  nvarchar(100) = @TenantId;
    DECLARE @lErrorCode nvarchar(20)  = @ErrorCode;
    DECLARE @lService   nvarchar(50)  = @Service;
    DECLARE @lTopK      int           = @TopK;

    -- Top prior incidents (approximate ANN via VECTOR_SEARCH)
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
            OR JSON_VALUE(a.Tags, '$.errorCode') = @lErrorCode)   -- residual filter on DiskANN bookmark side
    ORDER BY r.distance;

    -- Top runbook chunks. Two-step access path composed in ONE statement:
    --   1. JSON Index Seek on dbo.Runbook(Tags) for $.service = @Service
    --      narrows the runbook corpus to the right service family.
    --   2. Exact vector_distance over the chunks of those runbooks --
    --      no VECTOR_SEARCH / DiskANN needed because the structured
    --      filter already pinned the candidate set to a few dozen rows.
    --
    -- When @Service IS NULL we fall back to scanning all runbooks (still
    -- exact distance, just over the full chunk set -- small here).
    DECLARE @runbooks TABLE (
        source    nvarchar(20),
        id        nvarchar(60),
        title     nvarchar(400),
        body      nvarchar(max),
        distance  float,
        extra     nvarchar(max)
    );

    -- Branch by @Service to keep the JSON predicate sargable. An
    -- (@lService IS NULL OR JSON_VALUE = @lService) shortcut would
    -- block the JSON Index Seek (non-sargable OR-NULL pattern); two
    -- branches give us one sargable predicate per plan.
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

/*-----------------------------------------------------------
  usp_LogTimeline — Beat 3 / Beat 4 tool.
  -----------------------------------------------------------
  Reads from dbo.AppLog — an APPEND-ONLY LEDGER table.
  Tamper-evident, cryptographically verifiable record of
  application events for the incident. No ETL, no parquet,
  no external storage — just SQL.
-----------------------------------------------------------*/
IF OBJECT_ID(N'dbo.usp_LogTimeline', N'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_LogTimeline;
GO
CREATE PROCEDURE dbo.usp_LogTimeline
    @IncidentId int,
    @FromUtc    datetime2(0) = NULL,
    @ToUtc      datetime2(0) = NULL,
    @TopN       int          = 10
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  TOP (@TopN)
            ts,
            level,
            message
    FROM    dbo.AppLog
    WHERE   IncidentId = @IncidentId
      AND  (@FromUtc IS NULL OR ts >= @FromUtc)
      AND  (@ToUtc   IS NULL OR ts <= @ToUtc)
    ORDER BY ts;
END
GO

PRINT '  usp_LogTimeline (ledger) created.';
GO

PRINT '>>> 01_schema.sql complete. Run 02_seed_corpus.sql next.';
GO
