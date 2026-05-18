/*============================================================================
  grant_aca_mi.sql

  Grants the ACA system-assigned managed identity (the DAB container app)
  AAD access to the zavalivesitedb database on Hyperscale, scoped to read of
  Incident/IncidentArchive/Runbook + EXECUTE on the stored procs that DAB
  exposes as MCP tools.

  This script CANNOT be done in Bicep — `CREATE USER FROM EXTERNAL PROVIDER`
  is a T-SQL operation against Hyperscale.

  Required sqlcmd variables (passed via Prep-Cloud-Hosting.ps1):
    AcaAppName       — display name of the ACA app (= principal name in AAD)
                       e.g. zava-dab-vzew2f
    AcaPrincipalId   — system-assigned MI object id (not strictly required;
                       CREATE USER FROM EXTERNAL PROVIDER resolves by name)

  Auth model recap:
    - ACA app system MI authenticates to Hyperscale via
      Authentication=Active Directory Default (resolves to MI in ACA).
    - This user reads/executes; it does NOT need rights on AOAI or APIM,
      because the proc body calls AOAI/APIM via the SQL server's MI (the
      sp_invoke_external_rest_endpoint + DATABASE SCOPED CREDENTIAL path).
============================================================================*/
:on error exit
USE [$(DatabaseName)];
GO

/*----------------------------------------------------------------------------
  Idempotent: drop the user (if it exists) before re-creating. This
  intentionally preserves the underlying AAD principal — only the database
  user is recreated.
----------------------------------------------------------------------------*/
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'$(AcaAppName)')
BEGIN
    DROP USER [$(AcaAppName)];
    PRINT '>>> Existing user $(AcaAppName) dropped.';
END
GO

CREATE USER [$(AcaAppName)] FROM EXTERNAL PROVIDER;
PRINT '>>> User $(AcaAppName) created from external provider.';
GO

/*----------------------------------------------------------------------------
  Read access — DAB needs SELECT to serve REST /api/Incident etc.
  Embedding column is excluded by DAB at the entity level, but db_datareader
  still has rights on it; that's fine because DAB filters on response.
----------------------------------------------------------------------------*/
ALTER ROLE db_datareader ADD MEMBER [$(AcaAppName)];
GO

/*----------------------------------------------------------------------------
  Write access — usp_GenerateMitigation UPDATEs dbo.Incident, so the user
  needs UPDATE through the proc's ownership chain. db_datawriter is the
  simplest grant. (db_datawriter on Hyperscale is the same as on a normal
  DB; ownership chaining handles the proc → table hop.)
----------------------------------------------------------------------------*/
ALTER ROLE db_datawriter ADD MEMBER [$(AcaAppName)];
GO

/*----------------------------------------------------------------------------
  EXECUTE on each stored-proc entity DAB exposes as an MCP tool.
  Granting at the proc level (vs db_executor) keeps the surface area
  tight — only the procs DAB needs.
----------------------------------------------------------------------------*/
GRANT EXECUTE ON dbo.usp_HybridSearch               TO [$(AcaAppName)];
GRANT EXECUTE ON dbo.usp_LogTimeline                TO [$(AcaAppName)];
GRANT EXECUTE ON dbo.usp_GenerateMitigation         TO [$(AcaAppName)];
GRANT EXECUTE ON dbo.usp_DxIndexExists              TO [$(AcaAppName)];
GRANT EXECUTE ON dbo.usp_DxResourcePressure         TO [$(AcaAppName)];
GRANT EXECUTE ON dbo.usp_DxDeadlockRecent           TO [$(AcaAppName)];
GO

PRINT '>>> Grants applied to $(AcaAppName).';
GO
