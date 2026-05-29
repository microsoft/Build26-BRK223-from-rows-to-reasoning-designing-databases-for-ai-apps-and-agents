/*============================================================================
  BRK223 (Azure) — 04a_proc_generate_mitigation.sql
  -----------------------------------------------------------------------------
  dbo.usp_GenerateMitigation — the ONE cloud mitigation proc.

  DESIGN
    True lift-and-shift of the laptop demo: same proc name, same parameters,
    same `Incident.ProposedMitigation` target column as the local proc in
    `sql/local/sqlscripts/04a_proc_generate_mitigation.sql`. The only thing
    that changes is the chat URL and credential — local Ollama vs cloud APIM.

    Cloud always goes through APIM (Hyperscale → APIM → AOAI). APIM applies:
      - llm-content-safety  (Hate/Violence/SelfHarm/Sexual classifiers + shield-prompt)
      - llm-token-limit     (TPM cap per subscription)
      - llm-emit-token-metric (App Insights dims)
      - authentication-managed-identity (APIM MI → AOAI)

    Auth model: SQL MI bearer is injected by sp_invoke; APIM ignores it and
    uses its own MI to authenticate to AOAI. No keys are ever stored.

  sqlcmd variables required (substituted by Prep-Cloud.ps1):
    ApimHost          — e.g. zava-apim-vzew2f.azure-api.net
    ChatDeployment    — e.g. gpt-5-4-mini
    AoaiApiVersion    — e.g. 2024-10-21
============================================================================*/
:on error exit
:setvar ChatDeployment "gpt-5-4-mini"
:setvar AoaiApiVersion "2024-10-21"

/*----------------------------------------------------------------------------
  4) PROC FOR MITIGATION (cloud)

  Local shows sections (1) tables, (2) external model, (3) vector-search proc.
  Cloud keeps the same story split across scripts; this file is the cloud
  mitigation proc shown before running the agent.
----------------------------------------------------------------------------*/

-- Connection is already scoped to the target database; Azure SQL does not support USE.
GO

IF OBJECT_ID(N'dbo.usp_GenerateMitigation', N'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_GenerateMitigation;
GO

CREATE PROCEDURE dbo.usp_GenerateMitigation
    @IncidentId      int,
    @DiagnosticsJson nvarchar(max)  = NULL,
    @WhatIf          bit            = 0,
    @ChatUrl         nvarchar(4000) = N'https://$(ApimHost)/openai/deployments/$(ChatDeployment)/chat/completions?api-version=$(AoaiApiVersion)',
    @ChatModel       nvarchar(100)  = N'$(ChatDeployment)',
    @Credential      nvarchar(200)  = N'https://$(ApimHost)'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    /*------------------------------------------------------------------
      1. Read the incident.
    ------------------------------------------------------------------*/
    DECLARE @TenantId   nvarchar(100),
            @Service    nvarchar(50),
            @Severity   nvarchar(10),
            @ErrorCode  nvarchar(20),
            @Note       nvarchar(max),
            @AlertJson  nvarchar(max),
            @TagsJson   nvarchar(max);

    SELECT  @TenantId  = TenantId,
            @Service   = Service,
            @Severity  = Severity,
            @Note      = EngineerNote,
            @AlertJson = CAST(AlertPayload AS nvarchar(max)),
            @TagsJson  = CAST(Tags         AS nvarchar(max)),
            @ErrorCode = JSON_VALUE(CAST(Tags AS nvarchar(max)), '$.errorCode')
    FROM    dbo.Incident
    WHERE   IncidentId = @IncidentId;

    IF @TenantId IS NULL
    BEGIN
        RAISERROR('Incident %d not found.', 16, 1, @IncidentId);
        RETURN;
    END

    /*------------------------------------------------------------------
      2. Pull RAG context via usp_HybridSearch.
    ------------------------------------------------------------------*/
    CREATE TABLE #hits (
        source    nvarchar(20),
        id        nvarchar(40),
        title     nvarchar(400),
        body      nvarchar(max),
        distance  float,
        extra     nvarchar(max)
    );

    INSERT #hits (source, id, title, body, distance, extra)
    EXEC dbo.usp_HybridSearch
            @TenantId  = @TenantId,
            @Question  = @Note,
            @ErrorCode = @ErrorCode,
            @Service   = @Service,
            @TopK      = 3;

    /*------------------------------------------------------------------
      2b. Blast-radius signals from current state.
    ------------------------------------------------------------------*/
    DECLARE @ActiveSameService int, @TenantsAffected int, @OpenSev1Last24h int;

    SELECT  @ActiveSameService = COUNT(*),
            @TenantsAffected   = COUNT(DISTINCT TenantId)
    FROM    dbo.Incident
    WHERE   Service = @Service
      AND   Status IN (N'open', N'mitigating')
      AND   CreatedAtUtc >= DATEADD(hour, -24, SYSUTCDATETIME());

    SELECT  @OpenSev1Last24h = COUNT(*)
    FROM    dbo.Incident
    WHERE   LOWER(Severity) = N'sev1'
      AND   Status          IN (N'open', N'mitigating')
      AND   CreatedAtUtc   >= DATEADD(hour, -24, SYSUTCDATETIME());

    /*------------------------------------------------------------------
      3. Build the chat-completion request body (OpenAI shape).
    ------------------------------------------------------------------*/
    DECLARE @system nvarchar(max) = N'You are an SRE assistant for Azure SQL operations. You will be given:
  - an ACTIVE INCIDENT (with alert payload, tags, and the on-call engineer''s note),
  - PRIOR INCIDENTS retrieved by semantic similarity from the incident archive,
  - RUNBOOKS retrieved by semantic similarity,
  - CURRENT-STATE SIGNALS (counts of related active incidents right now), and
  - LIVE DIAGNOSTICS (named dx_* checks the agent ran against current state right before calling you).

LIVE DIAGNOSTICS are GROUND TRUTH about the system at this moment. Follow them when they conflict
with a runbook or prior incident, and explain in rationale.

Use LIVE DIAGNOSTICS for immediate action gating and ordering decisions. Do NOT
ask for additional exploratory monitoring/diagnostic queries as preconditions when
the supplied diagnostics already answer symptom-currentness and safety-to-change.
Follow-up checks are still required, but only as concrete post-change validation.

Return ONLY this JSON shape (no prose outside the JSON):
{ "summary": "<2-3 sentences naming specific identifiers from alert/tags/runbooks>",
  "cited_actions": [ { "action": "...", "source": "incident #<id> | runbook <id>" } ],
  "rollout_plan":  [ { "step": <int>, "action": "...", "rationale": "...", "verify": "<exact post-change check with metric/query + threshold + time window; no generic monitoring wording>" } ],
  "blast_radius":  { "tenants_affected": <int>, "active_incidents_same_service": <int>, "summary": "..." },
  "confidence":    { "overall": "low|medium|high", "notes": "..." } }';

    DECLARE @user nvarchar(max) =
        N'ACTIVE INCIDENT #' + CAST(@IncidentId AS nvarchar(20)) + N':' + CHAR(10) +
        N'  tenant=' + ISNULL(@TenantId, N'?') +
        N'  service=' + ISNULL(@Service, N'?') +
        N'  severity=' + ISNULL(@Severity, N'?') + CHAR(10) +
        N'  alert=' + ISNULL(@AlertJson, N'{}') + CHAR(10) +
        N'  tags='  + ISNULL(@TagsJson,  N'{}') + CHAR(10) +
        N'  note=' + ISNULL(@Note, N'') + CHAR(10) + CHAR(10) +
        N'CURRENT-STATE SIGNALS:' + CHAR(10) +
        N'  active_incidents_same_service_last_24h = ' + CAST(@ActiveSameService AS nvarchar(20)) + CHAR(10) +
        N'  distinct_tenants_affected_same_service = ' + CAST(@TenantsAffected   AS nvarchar(20)) + CHAR(10) +
        N'  open_sev1_last_24h_total               = ' + CAST(@OpenSev1Last24h   AS nvarchar(20)) + CHAR(10) +
        N'  Use these counts verbatim in blast_radius.' + CHAR(10) + CHAR(10) +
        N'LIVE DIAGNOSTICS:' + CHAR(10) +
        ISNULL(@DiagnosticsJson, N'  (none)') + CHAR(10) + CHAR(10) +
        N'PRIOR INCIDENTS:' + CHAR(10) +
        ISNULL((
            SELECT STRING_AGG(
                CONCAT(N'  - #', id, N' [', title, N']: ', LEFT(ISNULL(body, N''), 600)),
                CHAR(10))
            FROM (SELECT TOP (10) id, title, body, distance
                  FROM #hits WHERE source = N'incident' ORDER BY distance) AS p
        ), N'  (none)') + CHAR(10) + CHAR(10) +
        N'RUNBOOKS:' + CHAR(10) +
        ISNULL((
            SELECT STRING_AGG(
                CONCAT(N'  - ', id, N' "', title, N'": ', LEFT(ISNULL(body, N''), 600)),
                CHAR(10))
            FROM (SELECT TOP (10) id, title, body, distance
                  FROM #hits WHERE source = N'runbook' ORDER BY distance) AS r
        ), N'  (none)');

    DECLARE @body nvarchar(max) = (
        SELECT  @ChatModel                          AS [model],
                3000                                AS [max_completion_tokens],
                N'low'                              AS [reasoning_effort],
                JSON_OBJECT('type': 'json_object')  AS [response_format],
                JSON_ARRAY(
                    JSON_OBJECT('role': 'system', 'content': @system),
                    JSON_OBJECT('role': 'user',   'content': @user)
                )                                   AS [messages]
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    );

    /*------------------------------------------------------------------
      4. Call AOAI through APIM. SQL MI bearer is injected by sp_invoke;
         APIM ignores it and uses its own MI to authenticate to AOAI.
         APIM applies llm-content-safety + llm-token-limit + metrics in
         the inbound pipeline before forwarding.
    ------------------------------------------------------------------*/
    DECLARE @ret      int,
            @response nvarchar(max),
            @headers  nvarchar(4000) = N'{"Content-Type":"application/json"}';

    BEGIN TRY
        EXEC @ret = sp_invoke_external_rest_endpoint
            @url        = @ChatUrl,
            @method     = N'POST',
            @headers    = @headers,
            @payload    = @body,
            @timeout    = 180,
            @credential = @Credential,
            @response   = @response OUTPUT;
    END TRY
    BEGIN CATCH
        DECLARE @errMsg nvarchar(4000) = ERROR_MESSAGE();
        RAISERROR('sp_invoke failed against %s: %s', 16, 1, @ChatUrl, @errMsg);
        RETURN;
    END CATCH;

    IF @ret = 403
    BEGIN
        RAISERROR('APIM blocked the request (HTTP 403). Likely llm-content-safety. Response: %.1000s',
                  16, 1, @response);
        RETURN;
    END

    IF @ret <> 0
    BEGIN
        RAISERROR('Gateway returned non-zero status %d. Response head: %.500s',
                  16, 1, @ret, @response);
        RETURN;
    END

    /*------------------------------------------------------------------
      5. Extract assistant content.
    ------------------------------------------------------------------*/
    DECLARE @assistant nvarchar(max) =
        JSON_VALUE(@response, '$.result.choices[0].message.content');

    IF @assistant IS NULL OR LEN(@assistant) = 0
    BEGIN
        RAISERROR('No assistant content. Response head: %.500s', 16, 1, @response);
        RETURN;
    END

    IF ISJSON(@assistant) = 0
    BEGIN
        RAISERROR('Assistant did not return valid JSON. Head: %.500s', 16, 1, @assistant);
        RETURN;
    END

    /*------------------------------------------------------------------
      6. Persist to ProposedMitigation (the SAME column the local proc
         writes; this is what makes the lift transparent to the Blazor
         page and the DAB Incident entity).
         Also append a tamper-evident row to dbo.AppLog so the Beat 3
         timeline closes with the agent's action. Ledger is append-only,
         so this row cannot be edited or backdated later.
    ------------------------------------------------------------------*/
    IF @WhatIf = 0
    BEGIN
        UPDATE  dbo.Incident
        SET     ProposedMitigation = CAST(@assistant AS json),
                Status             = CASE WHEN Status = N'open' THEN N'mitigating' ELSE Status END
        WHERE   IncidentId = @IncidentId;

        DECLARE @summary    nvarchar(1000) = JSON_VALUE(@assistant, '$.summary'),
                @confidence nvarchar(20)   = JSON_VALUE(@assistant, '$.confidence.overall');

        INSERT dbo.AppLog (ts, IncidentId, level, message)
        VALUES (
            SYSUTCDATETIME(),
            @IncidentId,
            N'action',
            CONCAT(
                N'[mitigation] ',
                @ChatModel,
                N' proposed mitigation (confidence=',
                COALESCE(@confidence, N'unknown'),
                N'): ',
                LEFT(COALESCE(@summary, N'(no summary)'), 900)
            )
        );
    END

    SELECT  IncidentId         = @IncidentId,
            Status             = (SELECT Status FROM dbo.Incident WHERE IncidentId = @IncidentId),
            ProposedMitigation = CAST(@assistant AS json),
            ChatModel          = @ChatModel,
            ChatUrl            = @ChatUrl,
            Lane               = N'aoai-gateway',
            WhatIf             = @WhatIf;
END
GO

PRINT '>>> dbo.usp_GenerateMitigation (cloud gateway) created.';
GO
