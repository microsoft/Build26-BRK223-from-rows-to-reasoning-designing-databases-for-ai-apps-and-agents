/*============================================================================
  BRK223 — 06_hybrid_search.sql
  -----------------------------------------------------------------------------
  Beat 2: one hybrid-search proc, two specialized access paths composed by
  the optimizer in a single statement.

    Incident side  -> Vector Index Seek on vec_archive_embedding (DiskANN).
                      Structured filters (tenant, errorCode) run as
                      residuals on the bookmark side.

    Runbook side   -> JSON Index Seek on ix_runbook_tags ($.service)
                      narrows the runbook corpus, then exact
                      vector_distance over the resulting chunks.

  Make sure "Enable Actual Plan" is ON in the MSSQL editor toolbar.
============================================================================*/
USE zavalivesitedb;
GO

EXEC dbo.usp_HybridSearch
     @TenantId  = N'zava',
     @Question  = N'Payroll batch Msg 1205 deadlock victim on dbo.PayrollBatch after build 9114.10212. Mitigate.',
     @ErrorCode = N'1205',
     @Service   = N'Payroll',
     @TopK      = 5;
GO
