/*============================================================================
  BRK223 — _reset_for_beat2.sql
  -----------------------------------------------------------------------------
  Rewinds demo state to "before Beat 1 ran". Use between rehearsals after a
  smoke test or a full Plan-A run. Deletes incident #5012.

  Safe to run multiple times (everything is IF EXISTS / WHERE-filtered).
  Does NOT touch the corpus (IncidentArchive, Runbook), vector indexes,
  EXTERNAL MODEL, or any procs. Re-running 02_seed_corpus / 03_vector_indexes
  is NOT required after this.

  Usage:
    .\Reset-ForBeat2.ps1
============================================================================*/
USE zavalivesitedb;
GO

PRINT '--- _reset_for_beat2 ---';

-- Delete incident #5012 inserted in Beat 1 (and any ProposedMitigation
-- written by Beat 4 lives on the same row).
IF EXISTS (SELECT 1 FROM dbo.Incident WHERE IncidentId = 5012)
BEGIN
    DELETE FROM dbo.Incident WHERE IncidentId = 5012;
    PRINT '  deleted dbo.Incident #5012';
END
ELSE
    PRINT '  dbo.Incident #5012 not present (ok)';
GO

-- Verify clean state.
DECLARE @has5012 bit = CASE WHEN EXISTS (
    SELECT 1 FROM dbo.Incident WHERE IncidentId = 5012) THEN 1 ELSE 0 END;

SELECT
    incident_5012_present = @has5012,
    archive_rowcount      = (SELECT COUNT(*) FROM dbo.IncidentArchive),
    runbook_rowcount      = (SELECT COUNT(*) FROM dbo.Runbook);

IF @has5012 = 0
    PRINT '>>> Reset OK. Ready to run Beat 1.';
ELSE
    PRINT '>>> Reset INCOMPLETE. Investigate.';
GO
