/*============================================================================
  BRK223 — 04b_diagnostic_procs.sql
  -----------------------------------------------------------------------------
  Three "Dx" procedures the agent calls through MCP to validate runbook
  recommendations against current state, before composing a mitigation.

    dbo.usp_DxIndexExists       — does this index already exist on this table?
    dbo.usp_DxResourcePressure  — is the database under pressure right now?
    dbo.usp_DxDeadlockRecent    — is the deadlock symptom still active?

  Each proc returns ONE row whose first column is `finding` (kebab-case
  verdict), followed by evidence columns. The agent reads `finding` to
  branch its plan and folds the full row into @DiagnosticsJson when it
  calls usp_GenerateMitigation.

  Also creates the stage trick: dbo.PayrollBatch WITHOUT ix_payroll_runDate,
  so dx_index_exists returns `index_missing` and the agent confirms the
  runbook step ("create ix_payroll_runDate") is still relevant. The agent
  then uses dx_resource_pressure to gate WHEN it's safe to apply.
============================================================================*/
USE zavalivesitedb;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/*----------------------------------------------------------------------------
  Stage state: synthetic PayrollBatch table, WITHOUT the recommended index.
  Runbook Payroll.7 recommends ix_payroll_runDate. We deliberately do NOT
  pre-create it so dx_index_exists returns `index_missing` on stage. The
  agent then confirms the runbook step is still relevant and proposes it,
  using dx_resource_pressure to gate WHEN it's safe to apply.

  If the index already exists from a prior run (e.g. stage was rehearsed
  end-to-end), drop it so the demo starts in the missing state.
----------------------------------------------------------------------------*/
IF OBJECT_ID(N'dbo.PayrollBatch', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.PayrollBatch (
        BatchId    bigint        IDENTITY(1,1) PRIMARY KEY,
        TenantId   nvarchar(100) NOT NULL,
        RunDate    date          NOT NULL,
        Status     nvarchar(20)  NOT NULL DEFAULT N'pending',
        Amount     decimal(18,2) NOT NULL DEFAULT 0,
        CreatedAt  datetime2     NOT NULL DEFAULT SYSUTCDATETIME()
    );
    PRINT '>>> dbo.PayrollBatch created (synthetic, for diagnostic stage).';
END
GO

IF EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'ix_payroll_runDate'
      AND object_id = OBJECT_ID(N'dbo.PayrollBatch')
)
BEGIN
    DROP INDEX ix_payroll_runDate ON dbo.PayrollBatch;
    PRINT '>>> ix_payroll_runDate dropped (stage starts in index_missing state).';
END
GO

/*============================================================================
  dbo.usp_DxIndexExists
============================================================================*/
IF OBJECT_ID(N'dbo.usp_DxIndexExists', N'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_DxIndexExists;
GO

CREATE PROCEDURE dbo.usp_DxIndexExists
    @SchemaName nvarchar(128),
    @TableName  nvarchar(128),
    @IndexName  nvarchar(128)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @object_id int = OBJECT_ID(QUOTENAME(@SchemaName) + N'.' + QUOTENAME(@TableName));
    DECLARE @target    nvarchar(260) = @SchemaName + N'.' + @TableName;

    -- Single result set so DAB returns the row in REST/MCP responses
    -- (multi-statement procs make DAB return only the first result set).
    DECLARE @finding            nvarchar(40);
    DECLARE @found_index_name   nvarchar(128);
    DECLARE @key_columns        nvarchar(max);
    DECLARE @is_unique          bit;
    DECLARE @index_type         nvarchar(60);
    DECLARE @created_for_object datetime2;

    IF @object_id IS NULL
    BEGIN
        SET @finding = N'table_not_found';
    END
    ELSE
    BEGIN
        SELECT TOP 1
            @finding            = N'index_present',
            @found_index_name   = i.name,
            @key_columns        = STUFF((
                                    SELECT N',' + c.name
                                    FROM   sys.index_columns ic
                                    JOIN   sys.columns c
                                           ON c.object_id = ic.object_id
                                          AND c.column_id = ic.column_id
                                    WHERE  ic.object_id = i.object_id
                                      AND  ic.index_id  = i.index_id
                                      AND  ic.is_included_column = 0
                                    ORDER BY ic.key_ordinal
                                    FOR XML PATH(''), TYPE
                                  ).value('.', 'nvarchar(max)'), 1, 1, ''),
            @is_unique          = i.is_unique,
            @index_type         = i.type_desc,
            @created_for_object = (SELECT create_date FROM sys.objects WHERE object_id = @object_id)
        FROM sys.indexes i
        WHERE i.object_id = @object_id
          AND i.name      = @IndexName;

        IF @finding IS NULL SET @finding = N'index_missing';
    END

    SELECT
        finding            = @finding,
        [target]           = @target,
        index_name         = ISNULL(@found_index_name, @IndexName),
        key_columns        = @key_columns,
        is_unique          = @is_unique,
        index_type         = @index_type,
        created_for_object = @created_for_object;
END
GO

PRINT '>>> usp_DxIndexExists created.';
GO

/*============================================================================
  dbo.usp_DxResourcePressure

  ----- IDEAL IMPLEMENTATION (commented out -- see DEV-TEAM NOTE below) -----
  -- Reads sys.dm_db_resource_stats which gives a rolling 15-second sampled
  -- view of avg_cpu_percent / avg_data_io_percent / log_write_percent for
  -- the database. This is the standard Azure SQL DB pressure DMV.
  --
  -- DEV-TEAM NOTE (Bob Ward, May 12 2026):
  --   sys.dm_db_resource_stats is NOT exposed by the local Azure SQL Database
  --   container image we ship for BRK223 (sqldb-dev-edition-nomiaa-3j:18.0.161_2_8).
  --   Querying it returns 42S02 "Invalid object name 'sys.dm_db_resource_stats'."
  --   even though @@VERSION reports EngineEdition=5 (Azure SQL DB). This is a
  --   surface-area gap in the dev-edition container; the DMV exists in the
  --   actual Azure SQL DB service. Please confirm whether the dev-edition
  --   container is supposed to surface dm_db_resource_stats and either
  --   enable it or document the omission so AI scenarios that rely on it
  --   (this one) can target it consistently in container and cloud.
  --
  --   When the DMV becomes available in the container, restore the original
  --   body below and remove the workaround.
  /*
  DECLARE @cutoff datetime2 = DATEADD(minute, -@WindowMinutes, SYSUTCDATETIME());
  ;WITH s AS (
      SELECT  end_time, avg_cpu_percent, avg_data_io_percent, log_write_percent
      FROM    sys.dm_db_resource_stats
      WHERE   end_time >= @cutoff
  )
  SELECT TOP 1
      finding = CASE WHEN MAX(log_write_percent) > 80 OR MAX(avg_cpu_percent) > 80 THEN N'pressure_high'
                     WHEN MAX(log_write_percent) > 50 OR MAX(avg_cpu_percent) > 50 THEN N'pressure_moderate'
                     ELSE N'pressure_normal' END,
      window_minutes    = @WindowMinutes,
      max_cpu_percent   = MAX(avg_cpu_percent),
      avg_cpu_percent   = AVG(avg_cpu_percent),
      max_log_write_pct = MAX(log_write_percent),
      max_data_io_pct   = MAX(avg_data_io_percent),
      sample_count      = COUNT(*),
      latest_sample_utc = MAX(end_time)
  FROM s;
  */

  ----- WORKAROUND IMPLEMENTATION (active) -----
  -- Same shape, derived from DMVs that DO work in the dev-edition container.
  -- Two cheap point-in-time signals approximate the three percentages:
  --   * CPU pressure proxy:  SUM(runnable_tasks_count) across schedulers.
  --     >= 4 runnable per scheduler is the classic "CPU saturation" rule of
  --     thumb. We map that to pressure_high.
  --   * Log write pressure proxy:  avg write latency (ms) on the LOG file
  --     from sys.dm_io_virtual_file_stats. Healthy LOG writes are < 5 ms;
  --     > 20 ms means the log subsystem is under pressure.
  -- @WindowMinutes is accepted for API stability but ignored by the workaround
  -- because both DMVs are point-in-time / cumulative since startup.
============================================================================*/
IF OBJECT_ID(N'dbo.usp_DxResourcePressure', N'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_DxResourcePressure;
GO

CREATE PROCEDURE dbo.usp_DxResourcePressure
    @WindowMinutes int = 5
AS
BEGIN
    SET NOCOUNT ON;

    -- CPU pressure: runnable tasks across user schedulers.
    DECLARE @runnable_tasks   int;
    DECLARE @scheduler_count  int;
    SELECT  @runnable_tasks  = SUM(runnable_tasks_count),
            @scheduler_count = COUNT(*)
    FROM    sys.dm_os_schedulers
    WHERE   scheduler_id < 255      -- user (non-DAC, non-hidden) schedulers
      AND   status = N'VISIBLE ONLINE';

    DECLARE @runnable_per_sched decimal(9,2) =
        CASE WHEN ISNULL(@scheduler_count,0) = 0 THEN 0
             ELSE CAST(@runnable_tasks AS decimal(9,2)) / @scheduler_count
        END;

    -- Log write latency: avg write stall (ms) on the LOG file of the current DB.
    DECLARE @log_write_ms decimal(9,2);
    SELECT TOP 1
        @log_write_ms = CASE WHEN num_of_writes = 0 THEN 0
                             ELSE CAST(io_stall_write_ms AS decimal(18,2)) / num_of_writes
                        END
    FROM    sys.dm_io_virtual_file_stats(DB_ID(), NULL) vfs
    JOIN    sys.database_files df
         ON df.file_id = vfs.file_id
    WHERE   df.type_desc = N'LOG';

    SELECT
        finding             = CASE
                                  WHEN @runnable_per_sched >= 4 OR @log_write_ms > 20 THEN N'pressure_high'
                                  WHEN @runnable_per_sched >= 2 OR @log_write_ms > 10 THEN N'pressure_moderate'
                                  ELSE                                                      N'pressure_normal'
                              END,
        window_minutes      = @WindowMinutes,    -- accepted for API stability; not used by workaround
        runnable_per_sched  = @runnable_per_sched,
        runnable_tasks      = @runnable_tasks,
        scheduler_count     = @scheduler_count,
        avg_log_write_ms    = ISNULL(@log_write_ms, 0),
        sample_count        = 1,                 -- point-in-time snapshot
        latest_sample_utc   = SYSUTCDATETIME(),
        source_note         = N'workaround: sys.dm_os_schedulers + sys.dm_io_virtual_file_stats (sys.dm_db_resource_stats unavailable in dev-edition container)';
END
GO

PRINT '>>> usp_DxResourcePressure created.';
GO

/*============================================================================
  dbo.usp_DxDeadlockRecent
  Reads dbo.AppLog (the ledger from Beat 3) for deadlock-shaped messages.
  We deliberately use AppLog rather than the system_health XEvent ring
  buffer because (a) the demo seeds AppLog with a known-good deadlock
  history and (b) it ties Beat 4's diagnostics back to Beat 3's ledger.
============================================================================*/
IF OBJECT_ID(N'dbo.usp_DxDeadlockRecent', N'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_DxDeadlockRecent;
GO

CREATE PROCEDURE dbo.usp_DxDeadlockRecent
    @TopN int = 5
AS
BEGIN
    SET NOCOUNT ON;

    -- Single result set so DAB returns rows in REST/MCP responses
    -- (multi-statement procs make DAB return only the first result set).
    DECLARE @hits TABLE (
        ts             datetime2,
        [level]        nvarchar(20),
        message_head   nvarchar(400)
    );

    INSERT INTO @hits (ts, [level], message_head)
    SELECT TOP (@TopN)
        ts,
        [level],
        LEFT(message, 400)
    FROM    dbo.AppLog
    WHERE   message LIKE N'%deadlock%'
       OR   message LIKE N'%Msg 1205%'
       OR   message LIKE N'%LCK_M_X%'
    ORDER BY ts DESC;

    IF EXISTS (SELECT 1 FROM @hits)
        SELECT  finding         = N'deadlock_present',
                event_time_utc  = ts,
                [level]         = [level],
                message_head    = message_head
        FROM    @hits
        ORDER BY ts DESC;
    ELSE
        SELECT  finding         = N'no_deadlock_history',
                event_time_utc  = CAST(NULL AS datetime2),
                [level]         = CAST(NULL AS nvarchar(20)),
                message_head    = CAST(NULL AS nvarchar(400));
END
GO

PRINT '>>> usp_DxDeadlockRecent created.';
GO
