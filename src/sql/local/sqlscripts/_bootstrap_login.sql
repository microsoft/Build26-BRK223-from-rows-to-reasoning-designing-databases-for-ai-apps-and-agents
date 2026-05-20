/*============================================================================
  BRK223 — _bootstrap_login.sql
  -----------------------------------------------------------------------------
  ONE-TIME bootstrap. Run this ONCE as sa against the Azure SQL container.
  Creates the sqladmin sysadmin login used for all subsequent demo scripts.

  After this runs, sa is never used again. Every other demo script
  (00_setup.sql through 07_log_timeline.sql) connects as sqladmin.

  This file is intentionally NOT numbered so it doesn't appear in the
  on-stage script flow. It is a deployment prerequisite, not part of the demo.

  Connection: localhost,1434  /  sa  /  <SA password from env>  /  TrustServerCertificate=Yes
  Idempotent: safe to re-run.

  Expects a sqlcmd-style variable $(SqlAdminPassword) to be substituted in
  before execution. deploy-prestage.ps1 passes this via
  Invoke-SqlsimScript -SqlcmdVariables @{ SqlAdminPassword = $SqlAdminPassword }.
============================================================================*/
USE master;
GO

IF SUSER_ID(N'sqladmin') IS NULL
BEGIN
    PRINT '>>> Creating login sqladmin...';
    CREATE LOGIN sqladmin WITH PASSWORD = '$(SqlAdminPassword)', CHECK_POLICY = OFF;
END
ELSE
BEGIN
    PRINT '>>> Login sqladmin already exists; resetting password.';
    ALTER LOGIN sqladmin WITH PASSWORD = '$(SqlAdminPassword)';
    ALTER LOGIN sqladmin ENABLE;
END
GO

IF IS_SRVROLEMEMBER(N'sysadmin', N'sqladmin') = 0
BEGIN
    PRINT '>>> Adding sqladmin to sysadmin server role...';
    ALTER SERVER ROLE sysadmin ADD MEMBER sqladmin;
END
GO

PRINT '>>> Bootstrap complete. Use sqladmin for all subsequent scripts.';
GO
