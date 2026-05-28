/*============================================================================
  BRK223 (Azure) — 03_external_model.sql
  -----------------------------------------------------------------------------
  Creates two MI-based DATABASE SCOPED CREDENTIALs and the EXTERNAL MODEL
  used for embeddings:

    AoaiCred             — SQL logical server's system-assigned MI, audience
                           'https://cognitiveservices.azure.com'. Consumed by:
                             - EXTERNAL MODEL AoaiTextEmbed3Small (embeddings)
                             - usp_GenerateMitigation_AoaiDirect (chat)
    ApimCred             — same shape; SQL MI bearer is forwarded to APIM
                           which overwrites Authorization in policy. Consumed by:
                             - usp_GenerateMitigation_AoaiGateway (chat)

    AoaiTextEmbed3Small  — CREATE EXTERNAL MODEL pointing at the AOAI
                           text-embedding-3-small deployment. MODEL_TYPE
                           must be EMBEDDINGS (the only legal enum value).
                           Chat completions are NOT routed through EXTERNAL
                           MODEL — they go via sp_invoke_external_rest_endpoint
                           in 04a_direct / 04a_gateway.

  Prereqs (provisioned by Bicep / Prep-Cloud.ps1):
    - SQL server system-assigned MI exists.
    - SQL MI is granted 'Cognitive Services User' on the AOAI account.
    - AOAI deployment 'text-embedding-3-small' exists at $(AoaiHost).
    - APIM gateway URL is $(ApimHost) with the 'openai' API path.

  Required sqlcmd variables (passed via sqlsim/sqlcmd -v):
    AoaiHost  — e.g. zavalivesite-aoai-abc123.openai.azure.com
    ApimHost  — e.g. zavalivesite-apim-abc123.azure-api.net
============================================================================*/
:on error exit
:setvar EmbedDeployment "text-embedding-3-small"
:setvar AoaiApiVersion  "2024-10-21"

/*----------------------------------------------------------------------------
  2) CREATE EXTERNAL MODEL (cloud)

  Keeps the same conceptual slot as local 01_schema.sql section (2),
  but in cloud deployment this is split into its own script.
----------------------------------------------------------------------------*/

-- Connection is already scoped to the target database by Prep-Cloud.ps1.
-- Azure SQL does not support USE to switch databases, so no USE here.
GO

/*----------------------------------------------------------------------------
  Idempotency — drop the EXTERNAL MODEL FIRST.

  The DSCs below cannot be dropped while an EXTERNAL MODEL still
  references them (Msg 33270 "Cannot drop the credential ... because
  it is used by an external model"). On a re-run the model already
  exists from the prior pass, so it must go before the credentials.
----------------------------------------------------------------------------*/
IF EXISTS (SELECT 1 FROM sys.external_models WHERE name = N'AoaiTextEmbed3Small')
    DROP EXTERNAL MODEL AoaiTextEmbed3Small;
GO

/*----------------------------------------------------------------------------
  DATABASE SCOPED CREDENTIAL — https://$(AoaiHost)  (Managed Identity)

  sp_invoke_external_rest_endpoint requires the credential NAME to match
  the URL prefix being called. So the credential is named after the AOAI
  endpoint host. EXTERNAL MODEL uses the same credential.
----------------------------------------------------------------------------*/
IF EXISTS (SELECT 1 FROM sys.database_scoped_credentials WHERE name = N'https://$(AoaiHost)')
    DROP DATABASE SCOPED CREDENTIAL [https://$(AoaiHost)];
GO

CREATE DATABASE SCOPED CREDENTIAL [https://$(AoaiHost)]
    WITH IDENTITY = 'Managed Identity',
         SECRET   = '{"resourceid":"https://cognitiveservices.azure.com"}';
GO
PRINT '>>> DATABASE SCOPED CREDENTIAL [https://$(AoaiHost)] created (Managed Identity, audience=cognitiveservices.azure.com).';
GO

/*----------------------------------------------------------------------------
  DATABASE SCOPED CREDENTIAL — https://$(ApimHost)  (Managed Identity)

  Same MI, same audience. APIM does not validate the inbound JWT (the
  policy overwrites Authorization with APIM's own MI token before
  forwarding to AOAI). Two distinct DSCs are required because the URL
  prefix differs.
----------------------------------------------------------------------------*/
IF EXISTS (SELECT 1 FROM sys.database_scoped_credentials WHERE name = N'https://$(ApimHost)')
    DROP DATABASE SCOPED CREDENTIAL [https://$(ApimHost)];
GO

CREATE DATABASE SCOPED CREDENTIAL [https://$(ApimHost)]
    WITH IDENTITY = 'Managed Identity',
         SECRET   = '{"resourceid":"https://cognitiveservices.azure.com"}';
GO
PRINT '>>> DATABASE SCOPED CREDENTIAL [https://$(ApimHost)] created (Managed Identity, audience=cognitiveservices.azure.com).';
GO

/*----------------------------------------------------------------------------
  EXTERNAL MODEL — AoaiTextEmbed3Small

  MODEL_TYPE = EMBEDDINGS is the ONLY legal enum value. Do not write
  CHAT_COMPLETIONS — it does not exist. Chat goes via sp_invoke.

  Note: the idempotent DROP for this model lives at the top of the
  script so the DSCs above can be dropped cleanly on re-run.
----------------------------------------------------------------------------*/
CREATE EXTERNAL MODEL AoaiTextEmbed3Small
    AUTHORIZATION  dbo
    WITH (
        LOCATION       = 'https://$(AoaiHost)/openai/deployments/$(EmbedDeployment)/embeddings?api-version=$(AoaiApiVersion)',
        API_FORMAT     = 'Azure OpenAI',
        MODEL_TYPE     = EMBEDDINGS,
        MODEL          = '$(EmbedDeployment)',
        CREDENTIAL     = [https://$(AoaiHost)]
    );
GO
PRINT '>>> EXTERNAL MODEL AoaiTextEmbed3Small created (1536-dim).';
GO

/*----------------------------------------------------------------------------
  Smoke test — round-trip 'smoke test' through AOAI to prove MI auth +
  endpoint URL + role assignment all work. Fails fast and loud if any
  link is broken.
----------------------------------------------------------------------------*/
DECLARE @v vector(1536) =
    AI_GENERATE_EMBEDDINGS(N'smoke test' USE MODEL AoaiTextEmbed3Small);

IF @v IS NULL
BEGIN
    RAISERROR('AoaiTextEmbed3Small smoke test returned NULL. Check MI role assignment and endpoint URL.', 16, 1);
    RETURN;
END

PRINT '>>> AoaiTextEmbed3Small smoke test OK.';
GO
