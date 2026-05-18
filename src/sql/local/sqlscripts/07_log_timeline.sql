/*============================================================================
  BRK223 — 07_log_timeline.sql
  -----------------------------------------------------------------------------
  Beat 3: tamper-evident timeline via APPEND-ONLY LEDGER table dbo.AppLog.

  Why a ledger and not parquet/ADLS?  Because this demo must run on a
  laptop with no external storage. The ledger gives us the same story
  the audience cares about — a verifiable, immutable application log —
  without an ADLS dependency. Every row is hashed into the database
  Merkle tree; rows can never be updated or deleted.

  The narration in demo.md Beat 3 frames this as: "App logs in a SQL
  ledger table — tamper-evident, append-only, cryptographically
  verifiable. The same SELECT you've written for years."
============================================================================*/
USE zavalivesitedb;
GO

PRINT '--- Beat 3: ledger timeline for IncidentId 5012 ---';
GO

-- The Beat 3 query (procedure call form — same shape DAB exposes as MCP tool).
EXEC dbo.usp_LogTimeline
    @IncidentId = 5012,
    @FromUtc    = '2026-05-04T14:25:00',
    @ToUtc      = '2026-05-04T14:35:00',
    @TopN       = 10;
GO

-- Inline query form — what we'd type in the editor.
SELECT TOP 10 ts, level, message
FROM   dbo.AppLog
WHERE  IncidentId = 5012
   AND ts BETWEEN '2026-05-04T14:25:00' AND '2026-05-04T14:35:00'
ORDER BY ts;
GO

-- Optional: prove tamper-evidence (skip on stage unless asked).
--   sys.database_ledger_blocks  — Merkle root per block
--   sys.database_ledger_transactions — every transaction recorded
-- EXEC sys.sp_verify_database_ledger;
