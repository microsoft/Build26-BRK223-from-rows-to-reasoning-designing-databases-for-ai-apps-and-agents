/*============================================================================
  BRK223 — 03_vector_indexes.sql
  -----------------------------------------------------------------------------
  Builds DiskANN vector indexes AFTER 02_seed_corpus.sql has populated
  IncidentArchive and Runbook with ~300 / ~20 rows.

  vec_incident_embedding is created on the live Incident table even though
  it starts near-empty; Azure SQL will materialize lazily as rows arrive.
  If your CTP build rejects an empty-table CREATE VECTOR INDEX, comment
  the first block out and recreate it after Beat 1 has inserted rows.
============================================================================*/
USE zavalivesitedb;
GO

PRINT '>>> 03_vector_indexes.sql starting...';
GO

-- IncidentArchive: corpus is seeded, build immediately.
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'vec_archive_embedding'
           AND object_id = OBJECT_ID(N'dbo.IncidentArchive'))
    DROP INDEX vec_archive_embedding ON dbo.IncidentArchive;
GO
CREATE VECTOR INDEX vec_archive_embedding
    ON dbo.IncidentArchive (Embedding)
    WITH (METRIC = 'cosine');
GO
PRINT '  vec_archive_embedding built.';
GO

-- Runbook: 20 rows is below the typical DiskANN threshold. Try anyway;
-- if it fails, the demo path on Runbook still works (exact KNN scan).
BEGIN TRY
    IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'vec_runbook_embedding'
               AND object_id = OBJECT_ID(N'dbo.Runbook'))
        DROP INDEX vec_runbook_embedding ON dbo.Runbook;

    EXEC('CREATE VECTOR INDEX vec_runbook_embedding
              ON dbo.Runbook (Embedding)
              WITH (METRIC = ''cosine'');');
    PRINT '  vec_runbook_embedding built.';
END TRY
BEGIN CATCH
    PRINT '  vec_runbook_embedding skipped (expected on small corpus): ' + ERROR_MESSAGE();
END CATCH;
GO

-- Incident (live table): may be empty.
BEGIN TRY
    IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'vec_incident_embedding'
               AND object_id = OBJECT_ID(N'dbo.Incident'))
        DROP INDEX vec_incident_embedding ON dbo.Incident;

    EXEC('CREATE VECTOR INDEX vec_incident_embedding
              ON dbo.Incident (Embedding)
              WITH (METRIC = ''cosine'');');
    PRINT '  vec_incident_embedding built.';
END TRY
BEGIN CATCH
    PRINT '  vec_incident_embedding skipped (expected on empty table): ' + ERROR_MESSAGE();
END CATCH;
GO

PRINT '>>> 03_vector_indexes.sql complete.';
GO
