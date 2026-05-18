/*============================================================================
  BRK223 — 05_create_incident.sql
  -----------------------------------------------------------------------------
  Beat 1: the "five-feature INSERT" the audience watches go live.

  Five Azure SQL features in one statement:
    (1) JSON column / JSON_VALUE
    (2) REGEXP_MATCHES
    (3) FOR JSON PATH (shaping Tags)
    (4) AI_GENERATE_EMBEDDINGS
    (5) vector type

  The engineer note is engineered (pun intended) to match the seeded
  IncidentArchive #4421 + Runbook 'Payroll.7' so hybrid search returns
  obvious neighbors.  Same tenant (zava), same service (Payroll),
  same Msg 1205 deadlock pattern, same build line (9114.x), same
  object (dbo.PayrollBatch), same wait type (LCK_M_X).

  IncidentId 5012 is what the website polls. We force it via SET IDENTITY_INSERT.
============================================================================*/
USE zavalivesitedb;
GO

SET NOCOUNT ON;
GO

-- Demo is rerunnable: clear any existing 5012 row.
DELETE FROM dbo.Incident WHERE IncidentId = 5012;
GO

-- Belt-and-suspenders shape: the alert carries structured fields (what a
-- monitoring pipeline would actually emit), and regex over the free-form
-- @note augments them. Tags = COALESCE(alert, regex) so we get a clean
-- digit-only errorCode ('1205') matching IncidentArchive seed conventions
-- and the @ErrorCode parameter shape used by usp_HybridSearch.
DECLARE @alert json = JSON_OBJECT(
    'tenantId':'zava',
    'service':'Payroll',
    'region':'eastus2',
    'severity':'sev1',
    'incidentId':5012,
    'firedAt':'2026-05-04T14:32:00Z',
    'description':'Payroll batch Msg 1205 surge after 9114.10212 deploy',
    'object':'dbo.PayrollBatch',
    'errorCode':'1205',
    'build':'9114.10212',
    'waitType':'LCK_M_X');

DECLARE @note nvarchar(max) = N'hey on-call here, payroll''s been red since ~14:30 UTC. Msg 1205 spam in the app logs, customers calling support about pay stubs not posting, and our finance lead just messaged me directly about Zava''s payday tomorrow. We rolled Build 9114.10212 about 30 min before this started -- last clean rev was 9114.10180. Wait stat I keep seeing is LCK_M_X on dbo.PayrollBatch key (TenantId, RunDate). Two writers fighting for an X lock and one keeps getting picked as the deadlock victim every cycle. Need a plan asap, payday job has to run tonight.';

SET IDENTITY_INSERT dbo.Incident ON;

INSERT dbo.Incident
    (IncidentId, TenantId, Service, Region, Severity,
     AlertPayload, EngineerNote, Tags, Embedding)
SELECT
    5012,
    JSON_VALUE(@alert, '$.tenantId'),                                   -- (1) JSON
    JSON_VALUE(@alert, '$.service'),
    JSON_VALUE(@alert, '$.region'),
    JSON_VALUE(@alert, '$.severity'),
    @alert,                                                              -- (1) json column
    @note,
    -- (2) regex extracts → (3) shape into Tags as JSON.
    -- Structured alert wins; regex over the free-form note fills any gap.
    (SELECT
         COALESCE(
            JSON_VALUE(@alert, '$.errorCode'),
            (SELECT TOP 1 REPLACE(m.match_value, 'Msg ', '')
               FROM REGEXP_MATCHES(@note, '\bMsg\s+\d{3,5}\b') m)
         ) AS errorCode,
         COALESCE(
            JSON_VALUE(@alert, '$.build'),
            (SELECT TOP 1 m.match_value
               FROM REGEXP_MATCHES(@note, '\b\d+(?:\.\d+){1,3}\b') m)
         ) AS [build],
         COALESCE(
            JSON_VALUE(@alert, '$.waitType'),
            (SELECT TOP 1 m.match_value
               FROM REGEXP_MATCHES(@note, '\b(?:[A-Z][A-Z0-9]*(?:_[A-Z0-9]+)+|WRITELOG|CXPACKET|CXCONSUMER|THREADPOOL)\b') m)
         ) AS waitType
     FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    AI_GENERATE_EMBEDDINGS(@note USE MODEL OllamaMxbai);                 -- (4) embed → (5) vector(1024)

SET IDENTITY_INSERT dbo.Incident OFF;
GO

-- Verify (don't dwell on stage). Embedding returns as native vector type;
-- the MSSQL extension grid renders it as the bracketed float array.
SELECT TOP 1
        IncidentId,
        Tags,
        Embedding
FROM    dbo.Incident
WHERE   IncidentId = 5012;
GO
