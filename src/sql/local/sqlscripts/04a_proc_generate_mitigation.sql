/*============================================================================
  BRK223 — 04a_proc_generate_mitigation.sql
  -----------------------------------------------------------------------------
  usp_GenerateMitigation — the proc that DAB exposes as an MCP tool.

  Flow when the agent calls it:
    1. Read the incident (AlertPayload, EngineerNote, Tags).
    2. Run usp_HybridSearch to get top prior incidents + runbooks.
    3. Build a chat-completion request body with the RAG context.
    4. Call sp_invoke_external_rest_endpoint against the chat endpoint
         (https://localhost:8444/v1/chat/completions, phi4-mini via Caddy).
         EXTERNAL MODEL is not used here — Azure SQL only supports
         MODEL_TYPE = EMBEDDINGS, so chat goes through sp_invoke + a URL.
    5. Parse the response.
    6. UPDATE Incident SET ProposedMitigation = ... WHERE IncidentId = @IncidentId.
    7. SELECT IncidentId, Status, ProposedMitigation back to the caller.

  Cloud variant: only the @ChatUrl / @ChatModel defaults change.
============================================================================*/
USE zavalivesitedb;
GO

IF OBJECT_ID(N'dbo.usp_GenerateMitigation', N'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_GenerateMitigation;
GO

CREATE PROCEDURE dbo.usp_GenerateMitigation
    @IncidentId      int,
    @DiagnosticsJson nvarchar(max)  = NULL,  -- aggregated dx_* findings supplied by the agent
    @WhatIf          bit            = 0,     -- 1 = build prompt + call model, but don't UPDATE
    @ChatUrl         nvarchar(4000) = N'https://localhost:8444/v1/chat/completions',
    @ChatModel       nvarchar(100)  = N'phi4-mini',
    @Credential      nvarchar(200)  = NULL
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
      2. Pull RAG context. usp_HybridSearch returns a single result
         set with rows tagged by 'source' = 'incident' | 'runbook',
         interleaved by cosine distance. We materialize into one temp
         table and split when building the prompt below.
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
      2b. Compute blast-radius signals from current state. These are
          NOT in the runbook or prior-incident text — they require
          reasoning over what is happening *right now* in the system,
          and we hand them to the model so its rollout-plan / blast-
          radius section is grounded in current operational reality.
    ------------------------------------------------------------------*/
    DECLARE @ActiveSameService    int,
            @TenantsAffected      int,
            @OpenSev1Last24h      int;

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
      3. Build the chat-completion request body.
         Shape: { model, messages: [system, user], temperature, max_tokens,
                  response_format: { type: 'json_object' } }
    ------------------------------------------------------------------*/
    DECLARE @system nvarchar(max) = N'You are an SRE assistant for Azure SQL operations. You will be given:
  - an ACTIVE INCIDENT (with alert payload, tags, and the on-call engineer''s note),
  - PRIOR INCIDENTS retrieved by semantic similarity from the incident archive,
  - RUNBOOKS retrieved by semantic similarity,
  - CURRENT-STATE SIGNALS (counts of related active incidents right now), and
  - LIVE DIAGNOSTICS (named dx_* checks the agent ran against current state right before calling you).

LIVE DIAGNOSTICS are GROUND TRUTH about the system at this moment. If a runbook
or prior-incident action conflicts with a diagnostic finding, follow the diagnostic
and explain in the rollout_plan rationale. Examples:
  - dx_index_exists.finding = ''index_present'' for a runbook''s recommended index
      → that runbook step is already done. Skip it. Say so in rationale.
  - dx_resource_pressure.finding = ''pressure_high''
      → do NOT propose immediate online DDL or large batched UPDATEs. Reorder
        the plan so heavy operations are scheduled, not applied right now.
    - dx_deadlock_recent.finding = ''no_deadlock_history''
      → symptom may already be self-mitigated. Keep confidence at ''medium'' unless
        other signals (multiple matching prior incidents, narrow blast radius) override.

Use LIVE DIAGNOSTICS for immediate action gating and ordering decisions. Do NOT
ask for additional exploratory monitoring/diagnostic queries as preconditions when
the supplied diagnostics already answer symptom-currentness and safety-to-change.
Follow-up checks are still required, but only as post-change validation.

Your job is to produce a JSON mitigation plan with THREE distinct contributions:

  1. cited_actions  — what to do. Take these directly from the prior incidents and runbooks.
                      Every action MUST cite its source (incident id or runbook id).
                      Preserve specific identifiers (index names, settings, numeric thresholds).
  2. rollout_plan   — the order to apply the cited_actions, why that order is safer, and what to
                      verify after each step. The "verify" string for each step MUST be grounded
                      in the PRIOR INCIDENTS or RUNBOOKS above — quote the DMV, XEvent session,
                      Query Store view, or Azure Monitor metric that those sources used to
                      confirm the same class of fix. Make each verify a concrete post-change check
                      with: (a) exact metric/query, (b) success threshold/expected value, and
                      (c) time window (for example: "within 10 minutes"). Do NOT invent verification artifacts; if
                      the corpus does not name one for a step, say "see runbook <id>" or
                      "per incident #<id>". This is Azure SQL Database, so anything the corpus
                      does not mention (SQL ERRORLOG, SSMS, Profiler, on-box files) is off-limits.
                      Avoid generic wording like "monitor closely" or "run monitoring queries".
  3. confidence     — your honest assessment. Use "high" when you have strong prior-incident
                      matches (cosine distance <0.2) AND a narrow blast radius (<=1 active
                      incident same service, <=2 affected tenants, <3 open sev1 total).
                      Use "medium" for good matches but wider blast radius, or when a
                      critical diagnostic finding (e.g., dx_resource_pressure=pressure_high)
                      requires caution. Use "low" for weak matches or ambiguous symptoms.

Return ONLY this JSON shape (no prose outside the JSON):
{ "summary": "<2-3 sentences. Sentence 1: the symptom and likely root cause, naming the specific error code, object (index/table/proc), and tenant/service. Sentence 2: the primary fix, naming the exact artifact (index name, setting, threshold) and where it is applied. Sentence 3 (optional): the secondary action or guardrail. Do NOT be generic — every sentence must contain at least one specific identifier from the alert, tags, prior incidents, or runbooks.>",
  "cited_actions": [
    { "action": "<imperative sentence>", "source": "incident #<id>" | "runbook <id>" }
  ],
  "rollout_plan": [
    { "step": <int>, "action": "<imperative sentence>", "rationale": "<why this order>", "verify": "<exact post-change check with metric/query + threshold + time window>" }
  ],
  "blast_radius": {
    "tenants_affected": <int>,
    "active_incidents_same_service": <int>,
    "summary": "<one sentence on current operational impact>"
  },
  "confidence": { "overall": "low|medium|high", "notes": "<one sentence>" }
}';

    DECLARE @user nvarchar(max) =
        N'ACTIVE INCIDENT #' + CAST(@IncidentId AS nvarchar(20)) + N':' + CHAR(10) +
        N'  tenant=' + ISNULL(@TenantId, N'?') +
        N'  service=' + ISNULL(@Service, N'?') +
        N'  severity=' + ISNULL(@Severity, N'?') + CHAR(10) +
        N'  alert=' + ISNULL(@AlertJson, N'{}') + CHAR(10) +
        N'  tags='  + ISNULL(@TagsJson,  N'{}') + CHAR(10) +
        N'  note=' + ISNULL(@Note, N'') + CHAR(10) + CHAR(10) +
        N'CONFIDENCE GUIDANCE: Award "high" when you have multiple prior incidents matching the symptom AND the blast' + CHAR(10) +
        N'radius is narrow (few active incidents, single/few tenants affected, low open_sev1 count). Award "medium" for' + CHAR(10) +
        N'good matches but wider blast radius OR missing diagnostic confirmation. Award "low" when symptom is ambiguous or' + CHAR(10) +
        N'prior matches are weak.' + CHAR(10) + CHAR(10) +
        N'CURRENT-STATE SIGNALS (computed at query time, NOT from the corpus):' + CHAR(10) +
        N'  active_incidents_same_service_last_24h = ' + CAST(@ActiveSameService AS nvarchar(20)) + CHAR(10) +
        N'  distinct_tenants_affected_same_service = ' + CAST(@TenantsAffected   AS nvarchar(20)) + CHAR(10) +
        N'  open_sev1_last_24h_total               = ' + CAST(@OpenSev1Last24h   AS nvarchar(20)) + CHAR(10) +
        N'  Use these counts verbatim in blast_radius.tenants_affected and blast_radius.active_incidents_same_service.' + CHAR(10) + CHAR(10) +
        N'LIVE DIAGNOSTICS (run by the agent right before calling you; treat as ground truth):' + CHAR(10) +
        ISNULL(@DiagnosticsJson, N'  (none — agent did not run any diagnostics)') + CHAR(10) + CHAR(10) +
        N'PRIOR INCIDENTS:' + CHAR(10) +
        ISNULL((
            SELECT STRING_AGG(
                CONCAT(N'  - #', id, N' [', title, N']: ',
                       LEFT(ISNULL(body, N''), 600)),
                CHAR(10))
            FROM (SELECT TOP (10) id, title, body, distance
                  FROM #hits WHERE source = N'incident'
                  ORDER BY distance) AS p
        ), N'  (none)') + CHAR(10) + CHAR(10) +
        N'RUNBOOKS:' + CHAR(10) +
        ISNULL((
            SELECT STRING_AGG(
                CONCAT(N'  - ', id, N' "', title, N'": ',
                       LEFT(ISNULL(body, N''), 600)),
                CHAR(10))
            FROM (SELECT TOP (10) id, title, body, distance
                  FROM #hits WHERE source = N'runbook'
                  ORDER BY distance) AS r
        ), N'  (none)');

    DECLARE @body nvarchar(max) = (
        SELECT  @ChatModel                          AS [model],
                0.2                                 AS [temperature],
                1200                                AS [max_tokens],
                JSON_OBJECT('type': 'json_object')  AS [response_format],
                JSON_ARRAY(
                    JSON_OBJECT('role': 'system', 'content': @system),
                    JSON_OBJECT('role': 'user',   'content': @user)
                )                                   AS [messages]
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    );

    /*------------------------------------------------------------------
      4. Call the chat endpoint.
    ------------------------------------------------------------------*/
    DECLARE @ret      int,
            @response nvarchar(max),
            @headers  nvarchar(4000) = N'{"Content-Type":"application/json"}';

    BEGIN TRY
        IF @Credential IS NULL
            EXEC @ret = sp_invoke_external_rest_endpoint
                @url      = @ChatUrl,
                @method   = N'POST',
                @headers  = @headers,
                @payload  = @body,
                @timeout  = 180,
                @response = @response OUTPUT;
        ELSE
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

    IF @ret <> 0
    BEGIN
        RAISERROR('Chat endpoint returned non-zero status. Response head: %.500s',
                  16, 1, @response);
        RETURN;
    END

    /*------------------------------------------------------------------
      5. Extract assistant message content. Both OpenAI and Ollama-OpenAI
         shapes put it at result.choices[0].message.content.
    ------------------------------------------------------------------*/
    DECLARE @assistant nvarchar(max) =
        JSON_VALUE(@response, '$.result.choices[0].message.content');

    IF @assistant IS NULL OR LEN(@assistant) = 0
    BEGIN
        RAISERROR('No assistant content in response. Response head: %.500s',
                  16, 1, @response);
        RETURN;
    END

    -- The model was asked for JSON; if it returned a string-encoded JSON
    -- envelope, ISJSON will return 1 only when parseable. If 0, fail loud.
    IF ISJSON(@assistant) = 0
    BEGIN
        RAISERROR('Assistant did not return valid JSON. Head: %.500s',
                  16, 1, @assistant);
        RETURN;
    END

    /*------------------------------------------------------------------
      6. Persist (unless WhatIf).
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

    /*------------------------------------------------------------------
      7. Return the result so the MCP caller (the agent) sees it.
    ------------------------------------------------------------------*/
    SELECT  IncidentId        = @IncidentId,
            Status            = (SELECT Status FROM dbo.Incident WHERE IncidentId = @IncidentId),
            ProposedMitigation = CAST(@assistant AS json),
            ChatModel         = @ChatModel,
            ChatUrl           = @ChatUrl,
            WhatIf            = @WhatIf;
END
GO

PRINT '>>> usp_GenerateMitigation created.';
GO
