/*============================================================================
  BRK223 - 01a_tables.sql
  -----------------------------------------------------------------------------
  Extracted from 01_schema.sql for stage readability.

  Section 1) TABLES (+ JSON indexes + ledger table).
============================================================================*/
USE zavalivesitedb;
GO

PRINT '>>> 01a_tables.sql starting...';
GO

IF OBJECT_ID(N'dbo.Incident', N'U')        IS NOT NULL DROP TABLE dbo.Incident;
IF OBJECT_ID(N'dbo.IncidentArchive', N'U') IS NOT NULL DROP TABLE dbo.IncidentArchive;
IF OBJECT_ID(N'dbo.RunbookChunk', N'U')    IS NOT NULL DROP TABLE dbo.RunbookChunk;
IF OBJECT_ID(N'dbo.Runbook', N'U')         IS NOT NULL DROP TABLE dbo.Runbook;
IF OBJECT_ID(N'dbo.AppLog', N'U')          IS NOT NULL DROP TABLE dbo.AppLog;
GO

CREATE TABLE dbo.Incident
(
    IncidentId          int            IDENTITY(5000,1) NOT NULL CONSTRAINT PK_Incident PRIMARY KEY,
    TenantId            nvarchar(100)  NOT NULL,
    Service             nvarchar(50)   NOT NULL,
    Region              nvarchar(50)   NULL,
    Severity            nvarchar(10)   NOT NULL,
    Status              nvarchar(20)   NOT NULL CONSTRAINT DF_Incident_Status DEFAULT N'open',
    AlertPayload        json           NOT NULL,
    EngineerNote        nvarchar(max)  NULL,
    Tags                json           NULL,
    Embedding           vector(1024)   NULL,
    ProposedMitigation  json           NULL,
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
    Embedding           vector(1024)   NOT NULL,
    RootCause           nvarchar(max)  NULL,
    Mitigation          nvarchar(max)  NULL,
    ResolvedAtUtc       datetime2(0)   NULL
);
GO

CREATE TABLE dbo.Runbook
(
    RunbookId           varchar(20)    NOT NULL CONSTRAINT PK_Runbook PRIMARY KEY,
    Title               nvarchar(200)  NOT NULL,
    Content             nvarchar(max)  NOT NULL,
    Tags                json           NULL,
    Embedding           vector(1024)   NOT NULL
);
GO

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

CREATE JSON INDEX ix_runbook_tags
    ON dbo.Runbook (Tags)
    FOR ('$.service', '$.tags');
GO

PRINT '  JSON indexes created.';
GO

PRINT '  Vector indexes deferred - run 03_vector_indexes.sql after seeding.';
GO

PRINT '>>> 01a_tables.sql complete.';
GO
