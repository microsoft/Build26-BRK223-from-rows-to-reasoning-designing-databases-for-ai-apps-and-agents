/*============================================================================
  BRK223 — 04a_proc_generate_mitigation.sql
  -----------------------------------------------------------------------------
  usp_GenerateMitigation — the proc that DAB exposes as an MCP tool.

  Flow when the agent calls it:
    1. Read the incident (AlertPayload, EngineerNote, Tags).
    2. Run usp_HybridSearch to get top prior incidents + runbooks.
    3. Build a chat-completion request body with the RAG context.
    4. Call sp_invoke_external_rest_endpoint against the chat endpoint
         (https://localhost:8444/v1/chat/completions, phi4 via Caddy).
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
    @ChatModel       nvarchar(100)  = N'phi4',
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

Deadlock policy for this environment (modern Azure SQL):
  - Do NOT recommend changing LOCK_ESCALATION table options or related lock-escalation settings.
  - Do NOT recommend disabling/toggling Optimized Locking.
  - For Msg 1205 / LCK_M_* patterns, prioritize reducing per-transaction batch size and
    shortening transaction scope first, then apply indexing/query-shape fixes from cited
    runbooks/incidents.

Runbook-fidelity policy:
  - Treat the RUNBOOKS list as authoritative. Reproduce EVERY numbered or lettered step
    from the most relevant runbook as a separate rollout_plan entry, in the runbook''s
    order, unless a LIVE DIAGNOSTIC makes a step unnecessary or unsafe (then skip/reorder
    it and say why in rationale). Do not collapse a multi-step runbook into a single step.
  - STEP COUNT RULE: If the runbook''s MITIGATION STEPS contains numbered substeps
    written inline as "(1) ... (2) ... (3) ... (N) ...", the rollout_plan MUST contain
    at least N entries, one per substep, copying each substep''s concrete action.
    Generic verification or monitoring steps do NOT count toward this minimum and must
    be ADDITIONAL to the prescribed substeps, not substitutes for them.
  - SOURCE SECTION RULE: When a runbook is structured with labelled sections (SYMPTOMS,
    DIAGNOSTIC SIGNALS, ROOT CAUSE, MITIGATION STEPS, VERIFICATION, ROLLBACK, etc.),
    extract rollout_plan steps ONLY from the MITIGATION STEPS section. Do NOT pull
    index names, object names, settings, or numeric values from DIAGNOSTIC SIGNALS or
    ROOT CAUSE — those sections describe the broken state, not the fix.
  - Each rollout_plan.action MUST be a concrete, self-contained instruction the on-call
    can execute without opening another document. NEVER write meta-instructions like
    "Apply runbook X", "Follow runbook Y", or "See runbook Z" as an action. The runbook
    id belongs in the source/citation field, not in the action text.
  - When a runbook step contains a literal SQL statement (CREATE, ALTER, UPDATE, EXEC,
    SET, etc.), copy the SQL verbatim — preserve object names, key columns, INCLUDE
    columns, options, and numeric thresholds — into the rollout_plan action and the
    matching cited_actions entry. Do not paraphrase, summarize, or generalize the SQL.
    The action text MUST contain the full executable statement.
  - When a runbook step is operational text (e.g. "lower MergeChunkSize from 25000 to 5000"),
    copy that exact text into the action — including the named knob and both numeric values.
  - Cite the runbook id (and step number if available) in the source field.

VERBATIM EXAMPLE — follow this pattern exactly:
  Runbook MITIGATION STEPS text:
    "(1) Create a covering nonclustered index named ix_payroll_runDate ON dbo.PayrollBatch
    (TenantId, RunDate) INCLUDE (Status, Amount, PayCycleId) WITH (ONLINE = ON, FILLFACTOR = 90).
    (2) Lower the per-transaction batch from 25000 back to 5000 by setting PayrollBatch.MergeChunkSize=5000
    and rolling pods."
  CORRECT rollout_plan.action values:
    1. "CREATE INDEX ix_payroll_runDate ON dbo.PayrollBatch (TenantId, RunDate) INCLUDE (Status, Amount, PayCycleId) WITH (ONLINE = ON, FILLFACTOR = 90);"
    2. "Lower PayrollBatch.MergeChunkSize from 25000 to 5000 and roll pods."
  WRONG (do NOT do this):
    1. "CREATE INDEX ix_payroll_runDate ON dbo.PayrollBatch (RunDate);"   -- dropped TenantId, INCLUDE, WITH
    2. "Reduce transaction scope in usp_PayrollBatch_MergeWindow."         -- paraphrased, lost numbers
  - ID format: runbook ids look like "Payroll.7" or "<Service>.<N>". Incident ids look
    like "#30016" with a hash. Do not put incident ids in the runbook citation, and do
    not invent ids that did not appear in the RUNBOOKS or PRIOR INCIDENTS sections above.

Diagnostic-gating policy:
  - If a diagnostic shows a runbook step is already done (for example, dx_index_exists =
    index_present for the very index that step would create), skip that step and note it
    in rationale instead of re-proposing it.
  - If a diagnostic shows a runbook step would be unsafe right now, keep the step but
    reorder or schedule it and explain why in rationale.

Your job is to produce a JSON mitigation plan with THREE distinct contributions:

  1. cited_actions  — what to do. Take these directly from the prior incidents and runbooks.
                      Every action MUST cite its source (incident id or runbook id).
                      Preserve specific identifiers (index names, settings, numeric thresholds)
                      verbatim from the runbook/incident — never paraphrase SQL statements.
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
                      matches (cosine distance <=0.29 for the Payroll 1205 / LCK_M_X pattern,
                      or <=0.2 for other incidents) AND a narrow blast radius (<=1 active
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
        N'CONFIDENCE GUIDANCE: Award "high" when prior-incident matches are strong (cosine distance' + CHAR(10) +
        N'<= 0.29) AND blast radius is narrow (<=1 active incident same service, <=2 affected tenants,' + CHAR(10) +
        N'<3 open sev1 total) AND live diagnostics confirm the symptom. Award "medium" for good matches' + CHAR(10) +
        N'but wider blast radius OR partial diagnostic confirmation. Award "low" when symptom is' + CHAR(10) +
        N'ambiguous or prior matches are weak.' + CHAR(10) +
        N'IMPORTANT: severity alone (sev1/sev2/sev3) is NOT a reason to downgrade. If the above three' + CHAR(10) +
        N'criteria (match strength, blast radius, diagnostic confirmation) all pass, the correct answer' + CHAR(10) +
        N'is "high" even when severity is sev1. Severity describes urgency, not confidence.' + CHAR(10) + CHAR(10) +
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
                       LEFT(ISNULL(body, N''), 1500)),
                CHAR(10))
            FROM (SELECT TOP (10) id, title, body, distance
                  FROM #hits WHERE source = N'incident'
                  ORDER BY distance) AS p
        ), N'  (none)') + CHAR(10) + CHAR(10) +
        N'RUNBOOKS (full text — authoritative source for rollout_plan steps):' + CHAR(10) +
        ISNULL((
            SELECT STRING_AGG(
                CONCAT(N'  - ', id, N' "', title, N'": ', ISNULL(body, N'')),
                CHAR(10))
            FROM (SELECT TOP (10) id, title, body, distance
                  FROM #hits WHERE source = N'runbook'
                  ORDER BY distance) AS r
        ), N'  (none)');

    DECLARE @body nvarchar(max) = (
        SELECT  @ChatModel                          AS [model],
                0.0                                 AS [temperature],
                1.0                                 AS [top_p],
                42                                  AS [seed],
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

    -- Generic guardrails (scenario-agnostic):
    --   * If diagnostics confirm the index is already present, the model must not
    --     re-propose CREATE/REBUILD for it.
    --   * The deadlock policy in the system prompt forbids LOCK_ESCALATION /
    --     Optimized Locking changes — enforce it here too.
    -- Anything more scenario-specific (which index, which DDL, which steps to take)
    -- must come from the runbook content, not from this proc.
    DECLARE @DxIndexFinding nvarchar(40) = JSON_VALUE(@DiagnosticsJson, '$.dx_index_exists.finding');

    IF @DxIndexFinding = N'index_present'
       AND (@assistant LIKE N'%CREATE INDEX%' OR @assistant LIKE N'%REBUILD%')
    BEGIN
        RAISERROR('Mitigation JSON invalid: dx_index_exists=index_present must not include CREATE/REBUILD index advice.', 16, 1);
        RETURN;
    END

    IF @assistant LIKE N'%LOCK_ESCALATION%'
       OR @assistant LIKE N'%optimized locking%'
    BEGIN
        RAISERROR('Mitigation JSON invalid: must not recommend LOCK_ESCALATION or Optimized Locking changes on modern Azure SQL.', 16, 1);
        RETURN;
    END

    -- Reject pointer-style actions ("apply runbook X", "see runbook Y") that
    -- punt the actual work back to the on-call. Each rollout step must be a
    -- concrete instruction the on-call can execute without opening another doc.
    IF @assistant LIKE N'%"action":%apply runbook%'
       OR @assistant LIKE N'%"action":%see runbook%'
       OR @assistant LIKE N'%"action":%follow runbook%'
       OR @assistant LIKE N'%"action":%per runbook%'
       OR @assistant LIKE N'%"action":%refer to runbook%'
    BEGIN
        RAISERROR('Mitigation JSON invalid: rollout_plan.action must contain the concrete step, not a pointer like "apply runbook X".', 16, 1);
        RETURN;
    END

    -- When diagnostics say an index is missing, the rollout MUST contain the
    -- verbatim CREATE INDEX DDL from the runbook (not a paraphrase like
    -- "create index X using CREATE INDEX statement"). Require the recognizable
    -- shape: CREATE [UNIQUE] [NONCLUSTERED] INDEX <name> ON <schema>.<table> (
    IF @DxIndexFinding = N'index_missing'
       AND @assistant NOT LIKE N'%CREATE%INDEX%ON dbo.%(%'
    BEGIN
        RAISERROR('Mitigation JSON invalid: dx_index_exists=index_missing requires a rollout step containing the verbatim CREATE INDEX ... ON dbo.<table> (...) DDL from the runbook.', 16, 1);
        RETURN;
    END

    -- Generic runbook-fidelity check. If any retrieved runbook contains a
    -- CREATE INDEX statement, require the assistant to use the SAME index
    -- name as the runbook. This stops the LLM from synthesizing its own
    -- index name when the runbook prescribes one.
    DECLARE @rbBody nvarchar(max), @rbIxName nvarchar(200);
    DECLARE rb_cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT body FROM #hits
        WHERE source = N'runbook'
          AND body LIKE N'%CREATE%INDEX%ON%dbo.%';
    OPEN rb_cur;
    FETCH NEXT FROM rb_cur INTO @rbBody;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- Extract token between "CREATE [UNIQUE] [NONCLUSTERED] INDEX " and " ON".
        DECLARE @ixPos int = PATINDEX(N'%INDEX [a-z_[]%', @rbBody);
        IF @ixPos > 0
        BEGIN
            DECLARE @nameStart int = @ixPos + 6;          -- past "INDEX "
            DECLARE @onPos int = CHARINDEX(N' ON ', @rbBody, @nameStart);
            IF @onPos > @nameStart
            BEGIN
                SET @rbIxName = LTRIM(RTRIM(SUBSTRING(@rbBody, @nameStart, @onPos - @nameStart)));
                IF @rbIxName IS NOT NULL AND LEN(@rbIxName) > 0
                   AND @assistant NOT LIKE N'%' + @rbIxName + N'%'
                BEGIN
                    CLOSE rb_cur; DEALLOCATE rb_cur;
                    DECLARE @msg nvarchar(400) =
                        N'Mitigation JSON invalid: runbook prescribes index name "'
                        + @rbIxName
                        + N'" but the rollout uses a different name. Use the runbook''s index name verbatim.';
                    RAISERROR(@msg, 16, 1);
                    RETURN;
                END
            END
        END
        FETCH NEXT FROM rb_cur INTO @rbBody;
    END
    CLOSE rb_cur; DEALLOCATE rb_cur;

    -- Generic step-count check. If any retrieved runbook chunk contains inline
    -- numbered substeps "(1) ... (N) ...", require the rollout to have at
    -- least N entries — so the LLM cannot drop runbook steps in favor of
    -- generic monitoring/verification.
    DECLARE @maxStepN int = 0;
    DECLARE @bodyAll nvarchar(max) = (
        SELECT STRING_AGG(CAST(body AS nvarchar(max)), N' ')
        FROM #hits WHERE source = N'runbook'
    );
    DECLARE @probe int = 1;
    WHILE @probe <= 9
    BEGIN
        IF @bodyAll LIKE N'%(' + CAST(@probe AS nvarchar(2)) + N')%'
            SET @maxStepN = @probe;
        SET @probe += 1;
    END

    IF @maxStepN >= 2
    BEGIN
        DECLARE @rolloutCount int = (
            SELECT COUNT(*)
            FROM OPENJSON(JSON_QUERY(@assistant, '$.rollout_plan'))
        );
        IF @rolloutCount < @maxStepN
        BEGIN
            DECLARE @stepMsg nvarchar(400) =
                N'Mitigation JSON invalid: runbook prescribes '
                + CAST(@maxStepN AS nvarchar(2))
                + N' numbered substeps but rollout_plan has only '
                + CAST(@rolloutCount AS nvarchar(2))
                + N' entries. Reproduce every (1)..(N) substep from MITIGATION STEPS.';
            RAISERROR(@stepMsg, 16, 1);
            RETURN;
        END
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
