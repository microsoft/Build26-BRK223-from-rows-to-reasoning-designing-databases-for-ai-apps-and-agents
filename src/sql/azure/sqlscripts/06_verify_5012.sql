/*============================================================================
  06_verify_5012.sql
  ----------------------------------------------------------------------------
  Post-prep sanity check for the Azure (Hyperscale) lane.

  Run AFTER Prep-Cloud.ps1.  Open this in the MSSQL extension against the
  Hyperscale connection:
      Server:   zavasqlserver-vzew2f.database.windows.net
      Database: zavalivesitedb

  Expected output (one row):
      IncidentId      = 5012
      Confidence      = high
      Summary         = "Incident #5012 on tenant zava in Payroll..."
      TotalChars      = ~3000
      V2_StillExists  = no (good)

  If Confidence is blank or TotalChars is 0, the proc did not write
  ProposedMitigation -> re-run Prep-Cloud.ps1 step 6.
  If V2_StillExists = YES (bad), the legacy gateway column was not dropped
  -> investigate; should not happen after a clean Prep-Cloud run.
============================================================================*/

SET NOCOUNT ON;

SELECT  IncidentId,
        Confidence     = JSON_VALUE(ProposedMitigation, '$.confidence.overall'),
        Summary        = JSON_VALUE(ProposedMitigation, '$.summary'),
        TotalChars     = LEN(CAST(ProposedMitigation AS nvarchar(max))),
        V2_StillExists = CASE WHEN COL_LENGTH('dbo.Incident','ProposedMitigation_v2') IS NULL
                              THEN N'no (good)' ELSE N'YES (bad)' END
FROM    dbo.Incident
WHERE   IncidentId = 5012;
