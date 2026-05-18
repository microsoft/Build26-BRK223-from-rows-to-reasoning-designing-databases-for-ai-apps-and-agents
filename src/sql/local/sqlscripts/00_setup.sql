/*============================================================================
  BRK223 — 00_setup.sql
  -----------------------------------------------------------------------------
  Creates the zavalivesitedb database against the Azure SQL container (localhost,1434).
  Idempotent: drops and recreates so you can iterate on schema while playing.

  Run order:
    00_setup.sql                          ← this file
    01_schema.sql                         ← tables + JSON indexes + EXTERNAL MODELs + procs
    02_seed_corpus.sql                    ← ~300 archive rows + ~20 runbooks (embedded)
    03_vector_indexes.sql                 ← DiskANN ×3 (after seed)
    04a_proc_generate_mitigation.sql      ← MCP tool proc (depends on 02+03)
    05_create_incident.sql                ← Beat 1 INSERT
    06_hybrid_search.sql                  ← Beat 2 (composed plan: vector + JSON)
    07_log_timeline.sql                   ← Beat 3 (parquet — optional)

  Connection: localhost,1434  /  sa  /  Password1  /  TrustServerCertificate=Yes
============================================================================*/
USE master;
GO

-- Server-level: enable sp_invoke_external_rest_endpoint and the
-- AI_GENERATE_EMBEDDINGS / EXTERNAL MODEL surface used by the demo.
-- Idempotent: ignored if already on.
EXEC sp_configure 'external rest endpoint enabled', 1;
RECONFIGURE;
GO

IF DB_ID(N'zavalivesitedb') IS NOT NULL
BEGIN
    PRINT '>>> Dropping existing zavalivesitedb database...';
    ALTER DATABASE zavalivesitedb SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE zavalivesitedb;
END
GO

PRINT '>>> Creating zavalivesitedb...';
CREATE DATABASE zavalivesitedb;
GO

ALTER DATABASE zavalivesitedb SET RECOVERY SIMPLE;
ALTER DATABASE zavalivesitedb SET QUERY_STORE = ON;
ALTER DATABASE zavalivesitedb SET QUERY_STORE (OPERATION_MODE = READ_WRITE);
GO

-- Match Azure SQL Database cloud defaults: ADR + RCSI + Optimized Locking.
-- The Azure SQL container inherits box defaults (all OFF), so we turn them on
-- explicitly. OPTIMIZED_LOCKING requires ADR + RCSI as prerequisites, so order
-- matters: ADR -> RCSI -> OL.
ALTER DATABASE zavalivesitedb SET ACCELERATED_DATABASE_RECOVERY = ON;
ALTER DATABASE zavalivesitedb SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE;
ALTER DATABASE zavalivesitedb SET OPTIMIZED_LOCKING = ON;
GO

-- VECTOR_SEARCH and CREATE VECTOR INDEX are preview features in Azure SQL.
USE zavalivesitedb;
GO
ALTER DATABASE SCOPED CONFIGURATION SET PREVIEW_FEATURES = ON;
GO

PRINT '>>> zavalivesitedb created. Proceed with 01_schema.sql.';
GO
