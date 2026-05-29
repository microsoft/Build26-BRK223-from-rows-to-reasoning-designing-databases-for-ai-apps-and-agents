/*============================================================================
  BRK223 - 01b_external_model.sql
  -----------------------------------------------------------------------------
  Extracted from 01_schema.sql for stage readability.

  Section 2) CREATE EXTERNAL MODEL (embeddings).
============================================================================*/
USE zavalivesitedb;
GO

PRINT '>>> 01b_external_model.sql starting...';
GO

IF EXISTS (SELECT 1 FROM sys.external_models WHERE name = N'OllamaMxbai')
    DROP EXTERNAL MODEL OllamaMxbai;
GO

CREATE EXTERNAL MODEL OllamaMxbai
WITH (
    LOCATION   = 'https://localhost:8444/v1/embeddings',
    API_FORMAT = 'OpenAI',
    MODEL_TYPE = EMBEDDINGS,
    MODEL      = 'mxbai-embed-large'
);
GO

PRINT '  EXTERNAL MODEL OllamaMxbai created (chat goes via sp_invoke).';
GO

PRINT '>>> 01b_external_model.sql complete.';
GO
