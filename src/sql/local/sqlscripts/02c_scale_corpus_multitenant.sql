/*============================================================================
  BRK223 — 02c_scale_corpus_multitenant.sql
  -----------------------------------------------------------------------------
  Build a dataset where the optimizer naturally chooses BOTH:
    1) a JSON index seek on ix_archive_alert_payload ($.tenantId), AND
    2) a DiskANN Vector Index Seek on vec_archive_embedding
  for the WHERE+VECTOR_SEARCH query in usp_HybridSearch.

  Recipe:
    - 6 tenants × ~25,000 rows each = ~150,000 rows total
    - Tenant 'zava' selectivity ~16% (~25k rows match) — large enough
      that brute-force cosine over the filtered set loses to
      DiskANN + iterative-filter on the JSON-tenant index
    - Each clone row's $.tenantId is rewritten via JSON_MODIFY so the
      JSON index over $.tenantId has real distribution
    - Embedding reused as-is (DiskANN cares about graph shape, not
      payload uniqueness, for plan-shape demo)

  Wipes and rebuilds: deletes any IncidentId >= 10001, recreates DiskANN.
============================================================================*/
USE zavalivesitedb;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET NUMERIC_ROUNDABORT OFF;
GO

PRINT '>>> 02c_scale_corpus_multitenant.sql starting...';
GO

-- 1. Drop DiskANN (faster bulk insert without index maintenance noise).
IF EXISTS (SELECT 1 FROM sys.indexes
           WHERE name = N'vec_archive_embedding'
             AND object_id = OBJECT_ID(N'dbo.IncidentArchive'))
BEGIN
    PRINT '  Dropping vec_archive_embedding...';
    DROP INDEX vec_archive_embedding ON dbo.IncidentArchive;
END
GO

-- 2. Wipe prior clones.
PRINT '  Deleting any prior clones (IncidentId >= 10001)...';
DELETE FROM dbo.IncidentArchive WHERE IncidentId >= 10001;
PRINT CONCAT('  Deleted ', @@ROWCOUNT, ' clone rows.');
GO

-- 3. Clone 300 synthetic source rows × 500 multipliers = 150,000 new rows.
--    Each clone's tenantId is rewritten via JSON_MODIFY based on the
--    multiplier index modulo 6 -> one of 6 tenants (~25k rows each).
PRINT '  Cloning 300 source rows x 500 multipliers x 6 tenants (target ~150,000 rows)...';

;WITH multipliers AS (
    SELECT TOP (500) ROW_NUMBER() OVER (ORDER BY (SELECT 0)) AS n
    FROM   sys.all_objects AS a CROSS JOIN sys.all_objects AS b
), tenants AS (
    SELECT 0 AS idx, N'zava'      AS tenant UNION ALL
    SELECT 1,        N'contoso'           UNION ALL
    SELECT 2,        N'fabrikam'          UNION ALL
    SELECT 3,        N'northwind'         UNION ALL
    SELECT 4,        N'litware'           UNION ALL
    SELECT 5,        N'wingtip'
)
INSERT dbo.IncidentArchive
    (IncidentId, TenantId, Service, Region, Severity,
     AlertPayload, EngineerNote, Tags, Embedding,
     RootCause, Mitigation, ResolvedAtUtc)
SELECT
    10000 + ((m.n - 1) * 300) + (a.IncidentId - 1000)                      AS IncidentId,
    t.tenant                                                               AS TenantId,
    a.Service, a.Region, a.Severity,
    JSON_MODIFY(CAST(a.AlertPayload AS nvarchar(max)),
                '$.tenantId', t.tenant)                                    AS AlertPayload,
    a.EngineerNote,
    a.Tags,
    a.Embedding,
    a.RootCause,
    a.Mitigation,
    DATEADD(day, -((a.IncidentId % 90) + m.n), sysutcdatetime())
FROM   dbo.IncidentArchive AS a
       CROSS JOIN multipliers AS m
       INNER JOIN tenants  AS t ON t.idx = (m.n - 1) % 6
WHERE  a.IncidentId BETWEEN 1001 AND 1300;

PRINT CONCAT('  Inserted ', @@ROWCOUNT, ' clone rows.');
GO

-- 4. Recreate DiskANN over the full corpus.
PRINT '  Building vec_archive_embedding (DiskANN, cosine) over multitenant corpus...';
CREATE VECTOR INDEX vec_archive_embedding
    ON dbo.IncidentArchive (Embedding)
    WITH (METRIC = 'cosine');
GO

-- 5. Refresh stats + clear plan cache for the proc.
UPDATE STATISTICS dbo.IncidentArchive WITH FULLSCAN;
EXEC sp_recompile 'dbo.usp_HybridSearch';
GO

-- 6. Report.
DECLARE @cnt int = (SELECT COUNT(*) FROM dbo.IncidentArchive);
PRINT CONCAT('  IncidentArchive row count: ', @cnt);

SELECT JSON_VALUE(AlertPayload, '$.tenantId') AS tenantId, COUNT(*) AS cnt
FROM   dbo.IncidentArchive
GROUP BY JSON_VALUE(AlertPayload, '$.tenantId')
ORDER BY cnt DESC;
GO

PRINT '>>> 02c_scale_corpus_multitenant.sql complete.';
GO
