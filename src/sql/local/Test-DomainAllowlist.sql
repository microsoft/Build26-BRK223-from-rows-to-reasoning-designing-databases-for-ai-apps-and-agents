SET NOCOUNT ON;
GO
PRINT '=== @@VERSION ===';
SELECT @@VERSION;
GO
IF DB_ID('DomainProbe') IS NULL EXEC('CREATE DATABASE DomainProbe');
GO
USE DomainProbe;
GO

IF EXISTS (SELECT 1 FROM sys.external_models WHERE name = N'M_HostDocker') DROP EXTERNAL MODEL M_HostDocker;
GO
IF EXISTS (SELECT 1 FROM sys.external_models WHERE name = N'M_Example') DROP EXTERNAL MODEL M_Example;
GO
IF EXISTS (SELECT 1 FROM sys.external_models WHERE name = N'M_OpenAI') DROP EXTERNAL MODEL M_OpenAI;
GO

PRINT '=== TEST 1: CREATE EXTERNAL MODEL host.docker.internal (non-Azure) ===';
GO
BEGIN TRY
    EXEC('CREATE EXTERNAL MODEL M_HostDocker
          WITH ( LOCATION = ''https://host.docker.internal:8444/v1/embeddings'',
                 API_FORMAT = ''OpenAI'',
                 MODEL_TYPE = EMBEDDINGS,
                 MODEL = ''qwen3-embedding-0.6b'' );');
    PRINT 'CREATE OK: M_HostDocker';
END TRY
BEGIN CATCH
    PRINT 'CREATE FAILED: M_HostDocker [' + CAST(ERROR_NUMBER() AS VARCHAR(10)) + '] ' + ERROR_MESSAGE();
END CATCH;
GO

PRINT '=== TEST 2: CREATE EXTERNAL MODEL example.com (non-Azure public) ===';
GO
BEGIN TRY
    EXEC('CREATE EXTERNAL MODEL M_Example
          WITH ( LOCATION = ''https://example.com/v1/embeddings'',
                 API_FORMAT = ''OpenAI'',
                 MODEL_TYPE = EMBEDDINGS,
                 MODEL = ''text-embedding-ada-002'' );');
    PRINT 'CREATE OK: M_Example';
END TRY
BEGIN CATCH
    PRINT 'CREATE FAILED: M_Example [' + CAST(ERROR_NUMBER() AS VARCHAR(10)) + '] ' + ERROR_MESSAGE();
END CATCH;
GO

PRINT '=== TEST 3: CREATE EXTERNAL MODEL api.openai.com (non-Azure, well-known) ===';
GO
BEGIN TRY
    EXEC('CREATE EXTERNAL MODEL M_OpenAI
          WITH ( LOCATION = ''https://api.openai.com/v1/embeddings'',
                 API_FORMAT = ''OpenAI'',
                 MODEL_TYPE = EMBEDDINGS,
                 MODEL = ''text-embedding-ada-002'' );');
    PRINT 'CREATE OK: M_OpenAI';
END TRY
BEGIN CATCH
    PRINT 'CREATE FAILED: M_OpenAI [' + CAST(ERROR_NUMBER() AS VARCHAR(10)) + '] ' + ERROR_MESSAGE();
END CATCH;
GO

PRINT '=== Models present ===';
SELECT name, location FROM sys.external_models;
GO

PRINT '=== TEST 4: invoke AI_GENERATE_EMBEDDINGS against M_HostDocker ===';
GO
BEGIN TRY
    DECLARE @v VECTOR(1024) = AI_GENERATE_EMBEDDINGS(N'hello world' USE MODEL M_HostDocker);
    PRINT 'INVOKE OK: M_HostDocker (got vector)';
END TRY
BEGIN CATCH
    PRINT 'INVOKE FAILED: M_HostDocker [' + CAST(ERROR_NUMBER() AS VARCHAR(10)) + '] ' + ERROR_MESSAGE();
END CATCH;
GO

PRINT '=== TEST 5: enable + invoke sp_invoke_external_rest_endpoint to host.docker.internal ===';
GO
EXEC sp_configure 'show advanced options', 1; RECONFIGURE;
EXEC sp_configure 'external rest endpoint enabled', 1; RECONFIGURE;
GO
DECLARE @resp NVARCHAR(MAX), @rc INT;
BEGIN TRY
    EXEC @rc = sp_invoke_external_rest_endpoint
        @url     = N'https://host.docker.internal:8445/v1/chat/completions',
        @method  = 'POST',
        @headers = N'{"Content-Type":"application/json"}',
        @payload = N'{"model":"phi-4","messages":[{"role":"user","content":"hi"}]}',
        @timeout = 15,
        @response = @resp OUTPUT;
    PRINT 'sp_invoke rc=' + CAST(@rc AS VARCHAR(10));
    PRINT LEFT(ISNULL(@resp,''),1000);
END TRY
BEGIN CATCH
    PRINT 'sp_invoke FAILED [' + CAST(ERROR_NUMBER() AS VARCHAR(10)) + '] ' + ERROR_MESSAGE();
END CATCH;
GO

PRINT '=== Cleanup ===';
GO
IF EXISTS (SELECT 1 FROM sys.external_models WHERE name = N'M_HostDocker') DROP EXTERNAL MODEL M_HostDocker;
GO
IF EXISTS (SELECT 1 FROM sys.external_models WHERE name = N'M_Example')    DROP EXTERNAL MODEL M_Example;
GO
IF EXISTS (SELECT 1 FROM sys.external_models WHERE name = N'M_OpenAI')     DROP EXTERNAL MODEL M_OpenAI;
GO
USE master;
GO
DROP DATABASE DomainProbe;
GO
PRINT '=== DONE ===';
GO
