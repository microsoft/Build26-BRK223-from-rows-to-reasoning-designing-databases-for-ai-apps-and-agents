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

  @Question is the verbatim EngineerNote from 05_create_incident.sql —
  the same string usp_GenerateMitigation (Beat 4) and the live-site-sql
  agent feed into hybrid_search. Hand-crafted summaries degrade recall;
  the embedding model is trained on natural prose.

  Make sure "Enable Actual Plan" is ON in the MSSQL editor toolbar.
============================================================================*/
USE zavalivesitedb;
GO

EXEC dbo.usp_HybridSearch
     @TenantId  = N'zava',
     @Question  = N'hey on-call here, payroll''s been red since ~14:30 UTC. Msg 1205 spam in the app logs, customers calling support about pay stubs not posting, and our finance lead just messaged me directly about Zava''s payday tomorrow. We rolled Build 9114.10212 about 30 min before this started -- last clean rev was 9114.10180. Wait stat I keep seeing is LCK_M_X on dbo.PayrollBatch key (TenantId, RunDate). Two writers fighting for an X lock and one keeps getting picked as the deadlock victim every cycle. Need a plan asap, payday job has to run tonight.',
     @ErrorCode = N'1205',
     @Service   = N'Payroll',
     @TopK      = 3;
GO
