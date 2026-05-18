/*============================================================================
  BRK223 — 01c_seed_corpus.sql
  -----------------------------------------------------------------------------
  Seeds IncidentArchive (~300 rows) + Runbook (~20 rows) with embeddings
  generated at insert time via OllamaMxbai (mxbai-embed-large, 1024-dim).

  Why preload: DiskANN in Azure SQL needs ~256 rows to build the index, and
  we want hybrid search to return real-looking neighbors during Beat 2.

  Two "anchor" rows are inserted explicitly so the live demo always has
  obvious matches:
    - IncidentArchive #4421  — Payroll / err 0x80131904 / Build 9114.10180
                              tenant=zava (the prior the agent should cite)
    - Runbook 'Payroll.7'    — "TLS handshake failure mitigation"

  Run AFTER 01_schema.sql.  Run BEFORE 03_vector_indexes.sql.

  Expected runtime: 1-3 minutes (embedding round-trips dominate).
============================================================================*/
USE zavalivesitedb;
GO

SET NOCOUNT ON;
GO

PRINT '>>> 02_seed_corpus.sql starting...';
GO

/*-----------------------------------------------------------
  Quick smoke test of the embedding endpoint before we burn
  300 round-trips on a misconfigured URL.
-----------------------------------------------------------*/
BEGIN TRY
    DECLARE @smoke vector(1024) =
        AI_GENERATE_EMBEDDINGS(N'smoke test' USE MODEL OllamaMxbai);
    PRINT '  Embedding endpoint OK.';
END TRY
BEGIN CATCH
    PRINT '  Embedding endpoint FAILED: ' + ERROR_MESSAGE();
    PRINT '  Aborting seed.';
    RETURN;
END CATCH;
GO

/*-----------------------------------------------------------
  Anchor row: the prior incident the demo cites.
-----------------------------------------------------------*/
-- Re-runnable: clear anchor + synthetic range (1001..1300).
-- dbo.AppLog is APPEND-ONLY LEDGER so it cannot be deleted; on a re-seed
-- it will accumulate duplicate ledger rows for IncidentId=5012, which is
-- harmless for the demo (Beat 3 just reads recent rows by IncidentId).
DELETE FROM dbo.IncidentArchive WHERE IncidentId = 4421;
DELETE FROM dbo.IncidentArchive WHERE IncidentId BETWEEN 1001 AND 1300;
GO

DECLARE @note4421 nvarchar(max) = N'Payroll batch failing with Msg 1205 deadlock victim under heavy concurrency on dbo.PayrollBatch. Wait type LCK_M_X on key (TenantId, RunDate). Started after rolling Build 9114.10180; reverting build cleared it. Mitigated long-term by adding covering index ix_payroll_runDate on (TenantId, RunDate) INCLUDE (Status, Amount) and reducing the per-transaction batch from 25k to 5k rows to shorten the lock hold time.';

INSERT dbo.IncidentArchive
    (IncidentId, TenantId, Service, Region, Severity,
     AlertPayload, EngineerNote, Tags, Embedding,
     RootCause, Mitigation, ResolvedAtUtc)
VALUES
    (4421, N'zava', N'Payroll', N'eastus2', N'sev1',
     JSON_OBJECT(
        'tenantId':'zava', 'service':'Payroll',
        'region':'eastus2',    'severity':'sev1',
        'errorCode':'1205',
        'build':'9114.10180',
        'waitType':'LCK_M_X',
        'object':'dbo.PayrollBatch'),
     @note4421,
     JSON_OBJECT(
        'errorCode':'1205',
        'build':'9114.10180',
        'waitType':'LCK_M_X',
        'object':'dbo.PayrollBatch',
        'correlationId':'c-4421-aaa',
        'kbRef':'KB-PAYROLL-7'),
     AI_GENERATE_EMBEDDINGS(@note4421 USE MODEL OllamaMxbai),
     N'Build 9114.10180 lengthened the payroll batch transaction so range locks escalated on the (TenantId, RunDate) key. Two writers fought for an X lock and the optimizer picked one as the deadlock victim every cycle.',
     N'Add covering index ix_payroll_runDate on dbo.PayrollBatch(TenantId, RunDate) INCLUDE (Status, Amount) and reduce the per-transaction batch from 25k to 5k rows to shorten the lock hold time. See Runbook Payroll.7.',
     DATEADD(day, -42, sysutcdatetime()));
GO

PRINT '  Anchor IncidentArchive #4421 inserted.';
GO

/*-----------------------------------------------------------
  Synthetic archive — ~300 rows across services / tenants /
  error codes / builds. Templated EngineerNote so embeddings
  cluster meaningfully without being identical.
-----------------------------------------------------------*/
DECLARE @tenants  TABLE (i int IDENTITY(0,1) PRIMARY KEY, v nvarchar(50));
INSERT @tenants(v) VALUES (N'zava'), (N'northwind'), (N'contoso'), (N'adventureworks');

DECLARE @services TABLE (i int IDENTITY(0,1) PRIMARY KEY, v nvarchar(50));
INSERT @services(v) VALUES (N'Payroll'), (N'Auth'), (N'Billing'), (N'Catalog'), (N'Search'), (N'Notifications');

DECLARE @regions  TABLE (i int IDENTITY(0,1) PRIMARY KEY, v nvarchar(50));
INSERT @regions(v) VALUES (N'eastus2'), (N'westeurope'), (N'southcentralus'), (N'japaneast');

DECLARE @errcodes TABLE (i int IDENTITY(0,1) PRIMARY KEY, v nvarchar(20));
INSERT @errcodes(v) VALUES
    (N'1205'),    -- the demo target (deadlock victim)
    (N'1222'),    -- lock request timeout
    (N'8645'),    -- memory grant timeout
    (N'9001'),    -- log corruption
    (N'701'),     -- out of memory
    (N'18056'),   -- session reset failed
    (N'4060'),    -- cannot open db
    (N'53');      -- network error

-- Wait types paired 1:1 with @errcodes by ordinal — gives the JSON index on
-- $.waitType real selectivity (~38 rows each) instead of one anchor row only.
DECLARE @waittypes TABLE (i int IDENTITY(0,1) PRIMARY KEY, v nvarchar(40));
INSERT @waittypes(v) VALUES
    (N'LCK_M_X'),                          -- 1205 deadlock victim
    (N'LCK_M_U'),                          -- 1222 lock request timeout
    (N'RESOURCE_SEMAPHORE'),               -- 8645 memory grant timeout
    (N'WRITELOG'),                         -- 9001 log corruption / log write
    (N'MEMORY_ALLOCATION_EXT'),            -- 701  out of memory
    (N'SOS_SCHEDULER_YIELD'),              -- 18056 scheduler / session reset
    (N'ASYNC_NETWORK_IO'),                 -- 4060 cannot open db / client wait
    (N'ASYNC_NETWORK_IO');                 -- 53   network error

DECLARE @builds   TABLE (i int IDENTITY(0,1) PRIMARY KEY, v nvarchar(20));
INSERT @builds(v) VALUES
    (N'9114.10180'),  -- the demo build
    (N'9114.10212'),
    (N'9112.10009'),
    (N'9110.09822'),
    (N'9108.09640');

DECLARE @templates TABLE (i int IDENTITY(0,1) PRIMARY KEY, v nvarchar(max));
INSERT @templates(v) VALUES
    (N'service returning HTTP 500 with inner exception during TLS handshake to legacy dependency after build roll'),
    (N'connection pool exhausted under burst traffic, latencies spiking on dependent calls'),
    (N'name resolution failure to internal DNS for downstream API, intermittent across pods'),
    (N'queue worker stalled on poison message, dead-letter growing rapidly'),
    (N'auth token cache invalidated cluster-wide, sign-in failures observed across regions'),
    (N'database deadlock chain on hot index page during nightly batch'),
    (N'cert rotation missed, outbound TLS calls to partner host failing'),
    (N'memory pressure on app pod after deploy, GC churn triggering restarts'),
    (N'rate limit returned by upstream graph API, retries amplifying load'),
    (N'feature flag rollout enabled new code path with race condition under concurrency');

-- 300 archive rows.
DECLARE @i int = 1;
WHILE @i <= 300
BEGIN
    DECLARE @tenant nvarchar(50)  = (SELECT v FROM @tenants  WHERE i = @i % 4);
    DECLARE @svc    nvarchar(50)  = (SELECT v FROM @services WHERE i = @i % 6);
    DECLARE @region nvarchar(50)  = (SELECT v FROM @regions  WHERE i = @i % 4);
    DECLARE @sev    nvarchar(10)  = CASE WHEN @i % 5 = 0 THEN N'sev1'
                                          WHEN @i % 3 = 0 THEN N'sev2'
                                          ELSE N'sev3' END;
    DECLARE @err    nvarchar(20)  = (SELECT v FROM @errcodes  WHERE i = @i % 8);
    DECLARE @wait   nvarchar(40)  = (SELECT v FROM @waittypes WHERE i = @i % 8);
    DECLARE @bld    nvarchar(20)  = (SELECT v FROM @builds    WHERE i = @i % 5);
    DECLARE @tmpl   nvarchar(max) = (SELECT v FROM @templates WHERE i = @i % 10);
    DECLARE @host   nvarchar(100) = LOWER(@svc) + N'-dep.' + @tenant + N'.internal';

    -- Note still says "Msg <n>" so the regex story in 05_create_incident.sql
    -- has analogues here; structured tags carry the digit-only canonical.
    DECLARE @note nvarchar(max) =
        @svc + N' on ' + @tenant + N'/' + @region + N': ' + @tmpl
        + N'. Msg ' + @err + N' wait ' + @wait + N' build ' + @bld + N' host=' + @host + N'.';

    INSERT dbo.IncidentArchive
        (IncidentId, TenantId, Service, Region, Severity,
         AlertPayload, EngineerNote, Tags, Embedding,
         RootCause, Mitigation, ResolvedAtUtc)
    VALUES
        (1000 + @i, @tenant, @svc, @region, @sev,
         JSON_OBJECT(
            'tenantId': @tenant, 'service': @svc,
            'region': @region,   'severity': @sev,
            'errorCode': @err,
            'build': @bld,
            'waitType': @wait,
            'dependencyHost': @host),
         @note,
         JSON_OBJECT(
            'errorCode': @err,
            'build': @bld,
            'waitType': @wait,
            'dependencyHost': @host,
            'correlationId': CONCAT('c-', 1000 + @i),
            'kbRef': CONCAT('KB-', UPPER(@svc), '-', (@i % 9) + 1)),
         AI_GENERATE_EMBEDDINGS(@note USE MODEL OllamaMxbai),
         N'See historical RCA notes; root cause varied with template.',
         N'Mitigated per service runbook for ' + @svc + N'.',
         DATEADD(day, -((@i % 90) + 1), sysutcdatetime()));

    IF @i % 50 = 0 PRINT CONCAT('  ...', @i, ' archive rows seeded.');
    SET @i += 1;
END
GO

PRINT '  IncidentArchive seeding complete.';
GO

/*-----------------------------------------------------------
  Runbooks (~20). 'Payroll.7' is the anchor for the demo.
-----------------------------------------------------------*/
DELETE FROM dbo.Runbook;
GO

DECLARE @runbooks TABLE (
    RunbookId varchar(20),
    Title     nvarchar(200),
    Service   nvarchar(50),
    Tags      nvarchar(max),
    Content   nvarchar(max));

/*--------------------------------------------------------------------------
  Each runbook follows the standard ZavaSRE runbook template so that
  AI_GENERATE_CHUNKS produces multiple useful chunks per document:
    SYMPTOMS / DIAGNOSTIC SIGNALS / ROOT CAUSE / MITIGATION STEPS
    / VERIFICATION / ROLLBACK / POST-INCIDENT / REFERENCES.
  Payroll.7 is the anchor cited by the on-stage incident (Msg 1205).
--------------------------------------------------------------------------*/
INSERT @runbooks VALUES
('Payroll.7', N'Payroll batch deadlock mitigation (Msg 1205, LCK_M_X)', N'Payroll',
 N'["deadlock","1205","sql","index","chunking","payroll","LCK_M_X","build-9114"]',
 N'SYMPTOMS. The Payroll service emits Msg 1205 ("Transaction was deadlocked on lock resources with another process and has been chosen as the deadlock victim") in bursts during the dbo.PayrollBatch run, typically the night before payday. The error appears under build payroll-engine 9114.10212 and later but not on 9114.10199. Failure rate climbs above 0.5% of batches and the victim count is dominated by tenant Zava Manufacturing during the 14:00-15:30 UTC window.

DIAGNOSTIC SIGNALS. Run sys.dm_exec_session_wait_stats filtered to the PayrollBatch session_id and look for LCK_M_X on key:7:72057594... bound to dbo.PayrollBatch (TenantId, RunDate). Pull the extended event system_health ring buffer and look for xml_deadlock_report entries whose victim-list resource includes objectname="dbo.PayrollBatch" and indexname="PK_PayrollBatch". Confirm the lock mode pair is X-X on the clustered key and that both sides are running the new merge SP usp_PayrollBatch_MergeWindow.

ROOT CAUSE. Build 9114.10212 increased the per-transaction batch from 5000 rows to 25000 rows in usp_PayrollBatch_MergeWindow to reduce log flush overhead, but the table has no covering index on (TenantId, RunDate). The merge takes range X locks across the partition key while two parallel writers from different runners overlap on the same TenantId+RunDate keys, forming a chain deadlock with the orchestrator session that updates the BatchControl ledger row.

MITIGATION STEPS. (1) Create a covering nonclustered index named ix_payroll_runDate ON dbo.PayrollBatch (TenantId, RunDate) INCLUDE (Status, Amount, PayCycleId) WITH (ONLINE = ON, FILLFACTOR = 90); this is the single most important step and converts the X range lock to a narrow key lock. (2) Lower the per-transaction batch from 25000 back to 5000 by setting payroll-engine config flag PayrollBatch.MergeChunkSize=5000 and rolling pods. (3) Wrap the merge in SET LOCK_TIMEOUT 10000 so the victim does not hold attempts for more than ten seconds. (4) On the orchestrator side, change the BatchControl UPDATE to a single sargable WHERE BatchId = @id predicate so it cannot escalate.

VERIFICATION. Re-run the PayrollBatch synthetic load (script test/payroll/replay-deadlock.ps1 with -Iterations 200) and confirm zero Msg 1205 entries in sys.fn_xe_file_target_read_file. Query Store should show usp_PayrollBatch_MergeWindow with a new plan_id using a Nested Loops + Index Seek on ix_payroll_runDate; the prior Clustered Index Scan plan should not be reused. Wait stats taken in 5-minute deltas should drop LCK_M_X to under 1% of total wait time.

ROLLBACK. If the new index causes plan regressions on the read path (rare), drop ix_payroll_runDate ON dbo.PayrollBatch and revert PayrollBatch.MergeChunkSize back to 25000. The deadlocks will return until a follow-up fix is shipped; page the on-call DBA before rolling back. Do NOT roll back the LOCK_TIMEOUT change in isolation.

POST-INCIDENT. File a code-quality follow-up to remove the implicit cross-statement transaction in usp_PayrollBatch_MergeWindow and replace it with TRY/CATCH around a single-batch MERGE. Add an alert on Avg LCK_M_X wait above 50ms for dbo.PayrollBatch via Query Store waits report.

REFERENCES. Incident #4421 (tenant Northwind, 2026-03-12) cites this runbook; ticket SRE-2026-PAY-007; build notes payroll-engine 9114.10212; Microsoft Learn doc "Resolve deadlocks in SQL Server".'),

('Payroll.3', N'Connection pool exhaustion in Payroll service', N'Payroll',
 N'["pool","timeout","sql","SqlException","18456"]',
 N'SYMPTOMS. Payroll API returns HTTP 503 with inner exception "Timeout expired. The timeout period elapsed prior to obtaining a connection from the pool." Latency p99 climbs from 200ms to over 8 seconds within a 5 minute window. SqlException error 18456 may also appear if the same pod is rotating credentials concurrently.

DIAGNOSTIC SIGNALS. Inspect the SqlConnectionPool counters in the per-pod dotnet-counters stream: NumberOfActiveConnections approaches the configured MaxPoolSize (default 100). On the SQL side, sys.dm_exec_connections shows hundreds of session_ids from the same client_net_address with status="sleeping" and last_request_end_time more than 30 seconds old. Query Store reports a small number of long-running queries with elapsed_time over the connection_timeout, holding connections hostage.

ROOT CAUSE. A code path in Payroll/JobRunner.cs opens a SqlConnection per job and does not dispose it on the failure branch when the downstream tax-svc call throws. Under bursts of tax-svc timeouts the leaked connections accumulate faster than the GC can finalize them, exhausting the pool.

MITIGATION STEPS. (1) Raise MaxPoolSize from 100 to 200 as a temporary headroom buffer via Payroll.ConnectionString. (2) Identify the leaking call sites by capturing a heap snapshot with dotnet-dump collect --type Microsoft.Data.SqlClient.SqlInternalConnection and looking for instances older than 60 seconds. (3) Recycle the Payroll deployment with kubectl rollout restart deployment/payroll-api once the patched image is available. (4) On SQL, run ALTER SYSTEM KILL on stuck sessions older than 5 minutes to free pool slots immediately if customer impact is sev1.

VERIFICATION. After the patch, the NumberOfActiveConnections curve should stabilize below 60% of MaxPoolSize even under tax-svc timeout simulation. The "Timeout expired" exception count should fall to zero in the next 30 minutes.

ROLLBACK. Lowering MaxPoolSize back to 100 is safe once the leak is patched; leaving 200 in place is also fine.

POST-INCIDENT. Add a regression test that opens 500 connections against a faulted tax-svc mock and asserts pool usage returns to baseline within 90 seconds.

REFERENCES. Microsoft Learn "SQL Server Connection Pooling (ADO.NET)"; internal ticket SRE-PAY-CONN-203.'),

('Auth.2', N'Token cache invalidation across regions', N'Auth',
 N'["token","cache","redis","jwt","invalidation"]',
 N'SYMPTOMS. Users report being signed out unexpectedly across regions or, conversely, being able to use revoked tokens for up to 10 minutes after admin revocation. Mixed behavior is the strongest signal that the regional token caches have drifted.

DIAGNOSTIC SIGNALS. Compare the auth-cache-eastus and auth-cache-westus Redis instances using redis-cli SCAN MATCH "tok:*" and compare counts. A difference greater than 1% indicates drift. Check the cache pub/sub channel auth.invalidate for missing or delayed messages using redis-cli MONITOR. Look at the auth-svc pod logs for "RedisInvalidateMessageDropped" or pub/sub reconnect warnings.

ROOT CAUSE. The cross-region invalidation broadcast relies on Redis pub/sub which is fire-and-forget; if a regional auth-svc pod was rolling at the moment the admin issued a revoke, the pub/sub message is lost.

MITIGATION STEPS. (1) Flush the affected regional Redis with redis-cli FLUSHDB on the impacted region only. (2) Force re-issue of tokens for the affected tenant by calling /admin/auth/invalidate-tenant?tenantId=ZAVA. (3) Verify clock skew between regions is under 30 seconds using ntpq -p; large skew can cause valid tokens to appear expired. (4) Switch the invalidation transport from pub/sub to a durable stream (Redis Streams XADD) by toggling the auth-svc config flag UseDurableInvalidation=true.

VERIFICATION. Issue a token, revoke it from /admin/auth/revoke?tokenId=X, then attempt to use it within 5 seconds from the OTHER region. Expect HTTP 401 "token revoked".

ROLLBACK. Reverting to pub/sub is supported; the durable stream consumer is a strict superset and rollback only requires UseDurableInvalidation=false.

POST-INCIDENT. Add a synthetic monitor that revokes a token in region A and asserts immediate rejection in region B; alert on any breach.

REFERENCES. JWT revocation design doc /docs/auth/revocation.md; Redis Streams documentation.'),

('Auth.5', N'TLS certificate rotation gaps causing handshake failures', N'Auth',
 N'["cert","rotation","tls","handshake","keyvault"]',
 N'SYMPTOMS. Downstream services begin failing TLS handshakes against auth.zava.io with errors like "remote certificate is invalid" or "certificate chain not trusted". Failure rate ramps over 30 minutes as connection pools cycle through stale endpoints.

DIAGNOSTIC SIGNALS. Run openssl s_client -connect auth.zava.io:443 -servername auth.zava.io and inspect the leaf cert NotAfter field. Compare the thumbprint to the latest version in KeyVault using az keyvault certificate show --vault-name kv-zava-prod --name auth-tls. Mismatch indicates the deployed bundle is stale. Check pod logs for "CertificateReloadFailed".

ROOT CAUSE. The auth-svc deployment ships the cert in a Kubernetes secret rather than reading from KeyVault directly, so the secret must be rotated by a separate pipeline step. If the upstream KeyVault rotation runs but the kube secret pipeline does not, the new cert sits in KeyVault while pods serve the old one.

MITIGATION STEPS. (1) Verify the deployed cert by checking the secret with kubectl get secret auth-tls -o jsonpath="{.data.tls\.crt}" | base64 -d | openssl x509 -noout -enddate. (2) Run the pipeline RotateAuthCert manually from the SRE portal; this fetches the latest cert from KeyVault and updates the kube secret. (3) Trigger a rolling restart of auth-svc to force pods to pick up the new secret. (4) If the rotation pipeline itself is broken, fall back to extracting the cert from KeyVault directly: az keyvault secret download --vault-name kv-zava-prod --name auth-tls --file /tmp/auth-tls.pem, then kubectl create secret tls auth-tls --cert /tmp/auth-tls.pem --key ...

VERIFICATION. openssl s_client repeated against each region must show the new thumbprint within 10 minutes. SyntheticTLSProbe should return SUCCESS for all auth endpoints.

ROLLBACK. The old cert can be re-applied by re-running RotateAuthCert with --version previous, valid until the original NotAfter date.

POST-INCIDENT. Migrate auth-svc to the csi-secrets-store-provider-azure driver so pods read directly from KeyVault and never need a separate kube secret pipeline.

REFERENCES. Azure Key Vault docs "Certificate rotation"; CSI driver Azure provider.'),

('Billing.1', N'Stripe rate limit fallback and queue drain', N'Billing',
 N'["rate-limit","retry","stripe","429","webhook"]',
 N'SYMPTOMS. Billing service emits HTTP 429 "Too Many Requests" from Stripe API in bursts during invoice runs. Webhook processing latency climbs and some invoices show status "pending" longer than 5 minutes.

DIAGNOSTIC SIGNALS. Stripe-Ratelimit-Remaining response header drops to zero; check billing-svc logs for the X-Stripe-Account header to identify which Stripe account is being throttled. dotnet-counters on billing-svc shows the StripeRetryQueueDepth metric climbing above 1000.

ROOT CAUSE. The retry policy is fixed-interval (1 second) rather than exponential, so bursts of failed requests immediately retry and re-trigger the rate limit. Compounding this, webhook concurrency was set to a fixed 10 even though Stripe permits up to 100 requests per second for our account tier.

MITIGATION STEPS. (1) Switch the HTTP retry policy from fixed-interval to exponential backoff with jitter: Polly WaitAndRetryAsync with delays [200ms, 400ms, 800ms, 1600ms, 3200ms] plus random 0-200ms jitter. (2) Drain the existing retry queue by pausing webhook intake for 30 seconds: kubectl annotate deployment billing-webhook ingress/pause=true. (3) Raise webhook concurrency from 10 to 50 once the queue is drained. (4) Verify Stripe account rate-limit tier by reading the X-RateLimit-Limit header.

VERIFICATION. StripeRetryQueueDepth should return to zero within 15 minutes. The 429 response rate should drop below 0.1% of total requests.

ROLLBACK. Lower webhook concurrency back to 10 if any downstream backpressure is observed.

POST-INCIDENT. Add a circuit breaker so the service auto-pauses for 60 seconds after seeing 100 consecutive 429s.

REFERENCES. Stripe API rate-limit doc; Polly retry policy reference.'),

('Billing.4', N'Webhook poison message drain to DLQ', N'Billing',
 N'["queue","poison","servicebus","dlq","webhook"]',
 N'SYMPTOMS. The billing-webhook deadletter queue (DLQ) on Service Bus namespace sb-zava-prod fills above 500 messages. Customers report duplicate or missing invoice events.

DIAGNOSTIC SIGNALS. Inspect DLQ messages with az servicebus message peek --namespace sb-zava-prod --queue billing-webhook --subqueue deadletter. Look at the DeadLetterReason property; "MaxDeliveryCountExceeded" combined with the same message payload repeating indicates a poison message.

ROOT CAUSE. A webhook payload with a malformed Stripe customer_id (containing whitespace) causes the handler to throw a FormatException which is not caught in the per-message try block. The Service Bus client retries 10 times then DLQs.

MITIGATION STEPS. (1) Move all current DLQ messages to a backup container for forensics using the PowerShell snippet Move-DlqToBlob.ps1 -Queue billing-webhook -Container dlq-archive. (2) Deploy the patched billing-svc image (tag billing-svc:fix-poison-2026-05) which catches FormatException and logs+skips the message. (3) Replay non-poison messages back to the main queue with Resubmit-DlqMessages.ps1 -Queue billing-webhook -Filter "!MalformedCustomerId".

VERIFICATION. DLQ depth should return to baseline (under 10 messages) within 30 minutes. The MalformedCustomerId log counter should equal the number of poison messages skipped.

ROLLBACK. Re-deploy the previous billing-svc image; poison messages will return to DLQ but no customer impact since DLQ is bounded.

POST-INCIDENT. Add input validation on the webhook receive endpoint before queueing, so poison messages are rejected with HTTP 400 at the edge.

REFERENCES. Azure Service Bus DLQ doc; billing-svc PR #4421.'),

('Catalog.2', N'Search index drift between primary and replica', N'Catalog',
 N'["search","reindex","azuresearch","drift"]',
 N'SYMPTOMS. Catalog search results show stale data: customers report seeing products that were removed up to 24 hours ago, or missing products that were just added. Count parity check between SQL catalog table and the Azure AI Search index shows greater than 0.5% drift.

DIAGNOSTIC SIGNALS. Run the parity probe scripts/catalog/parity-check.ps1; it returns a JSON with sql_count, index_count, and drift_pct. Inspect the change feed for skipped entries: az search index statistics --service-name srch-zava-prod --index-name catalog-v3 should show documentCount roughly equal to the SQL count.

ROOT CAUSE. The incremental indexer relies on a high-water mark of LastModified, but the catalog table uses a non-monotonic LastModified that can move backward when admins correct timestamps. Entries between the old and new high-water mark are skipped.

MITIGATION STEPS. (1) Trigger a full reindex by running the AKS job catalog-reindex-full; it streams the entire catalog table to the search index. Expect 4-8 hours runtime overnight. (2) Pause incremental indexing during the full reindex: az search indexer reset --name catalog-incremental. (3) After full reindex, switch the high-water mark column from LastModified to ChangeFeedSequence (monotonic).

VERIFICATION. Re-run parity-check.ps1; drift should be under 0.05%. Spot-check 20 random products in the UI search and confirm they match the SQL row.

ROLLBACK. Reverting to LastModified is safe; drift will return slowly.

POST-INCIDENT. Add an alert on drift_pct above 0.1% with a 30-minute aggregation window.

REFERENCES. Azure AI Search indexer doc; catalog-svc design doc /docs/catalog/indexing.md.'),

('Catalog.6', N'CDN cache poisoning and edge purge procedure', N'Catalog',
 N'["cdn","cache","purge","akamai","edge"]',
 N'SYMPTOMS. Customers in a specific region (typically EU-West) see incorrect product images, prices, or error pages cached for up to 24 hours despite the origin being correct.

DIAGNOSTIC SIGNALS. curl -I against the CDN URL with -H "Pragma: akamai-x-cache-on" returns X-Cache: TCP_MEM_HIT from the affected edge POP. Origin curl returns the correct content. Compare the X-Cache-Key header to confirm cache fragmentation by query string is not the cause.

ROOT CAUSE. An upstream Cache-Control header from a misconfigured promotional landing page (max-age=86400) was inherited by product asset URLs because the asset path was reused. The edge POPs cached the stale variant for the full TTL.

MITIGATION STEPS. (1) Purge edge nodes per affected region using akamai purge invalidate --network production --hostname catalog.zava.io --path "/assets/*". Wait 90 seconds for the purge to propagate. (2) Verify origin Cache-Control headers are correct: curl -I https://catalog-origin.zava.io/assets/sku12345.jpg should return Cache-Control: public, max-age=300 (not 86400). (3) Confirm the origin shield is healthy: az cdn endpoint show --name catalog-shield --resource-group rg-zava-prod should show healthStatus="Healthy". (4) If shield is unhealthy, fail over to direct-to-origin by toggling the CDN profile.

VERIFICATION. Re-curl from at least three different edge POPs (EU-West, US-East, AP-South); all should return TCP_MISS once and then TCP_MEM_HIT with the correct content.

ROLLBACK. Re-enabling the origin shield is safe once it returns to Healthy.

POST-INCIDENT. Add a CI check on origin Cache-Control headers that fails the build if max-age exceeds 3600 on the /assets/* path.

REFERENCES. Akamai purge API; CDN cache header best practices.'),

('Search.1', N'Embedding model regression after upgrade', N'Search',
 N'["embedding","model","regression","vector","recall"]',
 N'SYMPTOMS. Vector search recall@10 drops from baseline 0.92 to 0.74 immediately after deploying a new embedding model version. Customer-facing relevance complaints spike within 24 hours.

DIAGNOSTIC SIGNALS. Run the relevance regression suite scripts/search/eval-recall.py against the test query set; expect a JSON report with per-query recall. Compare the embedding norm distribution: the new model may produce vectors with a different mean norm, which breaks cosine similarity tuning.

ROOT CAUSE. The new embedding model uses a different training corpus with different vocabulary weighting; vectors are not directly comparable to those in the existing index without recomputation.

MITIGATION STEPS. (1) Pin the embedding model back to the known-good version by setting search-svc config EmbeddingModelVersion=v3.2-prod (not v3.3-prod) and rolling pods. (2) Recompute affected vectors by running the reindex job search-vector-reindex --model v3.2-prod; this takes 6-12 hours for the full catalog. (3) Validate recall@10 returns to 0.90+ before announcing fix.

VERIFICATION. eval-recall.py should report recall@10 within 2% of the baseline. Customer relevance complaint volume should drop below baseline within 48 hours.

ROLLBACK. Rolling forward to v3.3-prod requires a coordinated reindex; do not switch back partially.

POST-INCIDENT. Require a recall regression suite to pass before any embedding model version change is promoted.

REFERENCES. Search relevance eval framework doc; embedding model registry.'),

('Search.3', N'Vector query latency spike from DiskANN cache pressure', N'Search',
 N'["latency","query","diskann","cache","vector"]',
 N'SYMPTOMS. Vector search p99 latency climbs from 80ms to over 1.5s during peak traffic. Throughput drops by 40%. Affects all tenants but most severe on tenants with the largest vector corpora.

DIAGNOSTIC SIGNALS. Query sys.dm_db_vector_index_stats and look at the DiskAnnCacheHitRatio field; under 0.7 indicates pressure. sys.dm_os_buffer_descriptors shows the vector index pages being evicted. Replica spread can be checked via sys.dm_hadr_database_replica_states.

ROOT CAUSE. A new tenant onboarded with a 2M-row vector corpus that no longer fits in the configured 64GB DiskANN cache. The cache thrashes as queries from different tenants compete for cache lines.

MITIGATION STEPS. (1) Inspect the DiskANN cache configuration: SELECT * FROM sys.configurations WHERE name LIKE "diskann%"; raise the cache size to 128GB via sp_configure "diskann cache size", 131072; RECONFIGURE. (2) Raise the top-K cap from 50 to 100 to amortize the per-query cost. (3) Verify replica spread; if all queries hit the primary, add a secondary read replica via az sql failover-group create. (4) If short-term relief is needed, partition the large tenant onto a dedicated database with its own cache.

VERIFICATION. p99 latency should return to under 150ms within 30 minutes of raising the cache. DiskAnnCacheHitRatio should climb above 0.85.

ROLLBACK. Lowering the cache to 64GB is safe if compatible workload fits.

POST-INCIDENT. Add capacity planning gates for new tenants whose corpus would push total beyond 80% of cache size.

REFERENCES. SQL Server vector search performance doc; DMV reference.'),

('Notifications.1', N'SMTP relay throttling and failover', N'Notifications',
 N'["smtp","throttle","sendgrid","bounce"]',
 N'SYMPTOMS. Email notifications are delayed by 5-30 minutes. The notifications-svc retry queue grows above 5000. Bounce rate climbs above 2%.

DIAGNOSTIC SIGNALS. SendGrid API returns HTTP 429 with Retry-After headers in the 60-300 second range. notifications-svc logs show "SmtpRelayThrottled" with the X-SendGrid-Account header.

ROOT CAUSE. The primary SendGrid tenant hit its per-hour send cap because a marketing campaign was deployed without notifying SRE.

MITIGATION STEPS. (1) Switch primary relay from sendgrid-zava-prod-1 to sendgrid-zava-prod-2 by setting config flag PrimaryRelay=tenant2 and rolling pods. (2) Verify SPF and DKIM records for the new relay match the from-address: dig TXT mail.zava.io. (3) Monitor bounce rate via the SendGrid dashboard for 30 minutes; if it climbs above 1% pause sends and engage deliverability team.

VERIFICATION. SmtpRelayThrottled log entries should drop to zero within 10 minutes. Queue depth should return to baseline within 60 minutes.

ROLLBACK. Switching back to sendgrid-zava-prod-1 is safe once its per-hour window resets.

POST-INCIDENT. Require marketing to file SRE notification 24h before any campaign over 100k recipients.

REFERENCES. SendGrid rate limits doc; DKIM/SPF record reference.'),

('Notifications.4', N'Push notification storm overwhelming APNS and FCM', N'Notifications',
 N'["push","apns","fcm","storm","throttle"]',
 N'SYMPTOMS. Mobile push notifications are delayed by 10+ minutes. APNS returns HTTP 429; FCM returns QUOTA_EXCEEDED. The notifications-svc push queue climbs above 100k entries.

DIAGNOSTIC SIGNALS. Push throughput per channel can be queried from the channel-quota Redis. Look for any single tenant exceeding 80% of channel quota.

ROOT CAUSE. A misfiring promotional campaign sent the same push to all 2M users at once instead of rolling over 4 hours.

MITIGATION STEPS. (1) Throttle outbound APNS and FCM by lowering per-channel concurrency from 100 to 25 via config flag PushConcurrency. (2) Requeue overflow with priority demoted: redis-cli LPUSH push:overflow $(redis-cli LRANGE push:main 0 -1). (3) Coordinate with the campaign team to disable the misfiring template by setting Template.Disabled=true in the admin portal.

VERIFICATION. Queue depth should drop below 10k within 30 minutes. Push success rate should climb above 99% within an hour.

ROLLBACK. Raising concurrency back to 100 is safe after the storm clears.

POST-INCIDENT. Add a campaign safety check that rejects pushes targeting more than 100k recipients per minute.

REFERENCES. APNS and FCM rate limit docs; campaign safety design doc.'),

('Platform.1', N'Pod OOM after deploy due to memory leak', N'Platform',
 N'["oom","memory","pod","dotnet-dump"]',
 N'SYMPTOMS. Pods in the affected deployment restart every 20-40 minutes with exit code 137 (OOMKilled). Container memory climbs steadily from 400MB to the 2GB limit before the kill.

DIAGNOSTIC SIGNALS. kubectl describe pod shows reason=OOMKilled. Container memory chart in Grafana shows a sawtooth pattern. dotnet-counters output captures the gen2 heap size climbing without bound.

ROOT CAUSE. A new code path in the deploy holds onto large IDisposable instances (HttpClient or SqlConnection) in a static cache without eviction, causing a slow leak.

MITIGATION STEPS. (1) Raise the container memory limit from 2GB to 4GB as immediate relief: kubectl set resources deployment/affected --limits=memory=4Gi. (2) Capture a heap snapshot from a leaking pod: kubectl exec -it pod/affected -- dotnet-dump collect -p 1 --type Heap. Copy the dump out and analyze with dotnet-dump analyze to find the retained object graph. (3) If the leak is identified and a fix is ready, deploy the patched image and revert the memory limit. If no fix is ready, schedule a hourly rolling restart as a stopgap.

VERIFICATION. After the fix deploy, gen2 heap size should plateau under 800MB and the sawtooth should disappear.

ROLLBACK. Reverting to the previous image stops the leak; OOM kills cease.

POST-INCIDENT. Add a CI check for static IDisposable fields and a memory regression test that runs each PR for 30 minutes under load.

REFERENCES. dotnet-dump doc; Kubernetes resource limits.'),

('Platform.2', N'DNS resolution failure on AKS nodes', N'Platform',
 N'["dns","name-resolution","coredns","kube-dns"]',
 N'SYMPTOMS. Pods intermittently fail to resolve internal service hostnames (svc.cluster.local) or external hostnames. Errors include "Name or service not known" and "TLS handshake timeout" downstream.

DIAGNOSTIC SIGNALS. kubectl exec into an affected pod and run nslookup kubernetes.default. A success rate under 95% indicates DNS issues. Check CoreDNS pod logs for [ERROR] entries: kubectl logs -n kube-system -l k8s-app=kube-dns.

ROOT CAUSE. CoreDNS configmap was modified to add a custom upstream that points to an unreachable DNS server, causing 5-second timeouts on every query that falls back from the bad upstream.

MITIGATION STEPS. (1) Validate the CoreDNS configmap: kubectl get configmap coredns -n kube-system -o yaml. Compare to the known-good template at /infra/dns/coredns.template.yaml. (2) Restart kube-dns to clear in-memory state: kubectl rollout restart deployment/coredns -n kube-system. (3) If the custom upstream is required but the server is down, fall back to a secondary resolver by editing the forward block: forward . 168.63.129.16 (Azure internal resolver).

VERIFICATION. nslookup from a test pod should succeed in under 100ms. The DnsResolveErrors metric should drop to zero within 5 minutes.

ROLLBACK. Reverting the CoreDNS configmap is always safe.

POST-INCIDENT. Add CI validation that CoreDNS configmaps match the approved template before apply.

REFERENCES. CoreDNS Kubernetes plugin doc; Azure DNS resolver reference.'),

('Platform.5', N'Node disk pressure forcing pod evictions', N'Platform',
 N'["disk","node","pressure","eviction","pv"]',
 N'SYMPTOMS. Pods on the affected node are evicted with reason=DiskPressure. New pods scheduled to the node are immediately evicted, creating a churn loop.

DIAGNOSTIC SIGNALS. kubectl describe node shows conditions[type=DiskPressure].status=True. df -h on the node shows the root filesystem above 85% used. The PV directory under /var/lib/kubelet/pods may be dominated by a single greedy pod.

ROOT CAUSE. A logging misconfiguration in a workload writes to a hostPath instead of the persistent volume, filling the node disk.

MITIGATION STEPS. (1) Drain the affected node to safely evict pods: kubectl drain node-affected --ignore-daemonsets --delete-emptydir-data. (2) Identify the largest directories on the node: ssh into the node and run du -sh /var/log/* /var/lib/kubelet/pods/* | sort -h. (3) Expand the PV if the data is legitimate: az disk update --resource-group rg-zava-prod --name pv-affected --size-gb 256. (4) Cordon and reschedule: kubectl cordon node-affected; once drained, az aks nodepool scale --resource-group rg-zava-prod --cluster-name aks-zava-prod --nodepool-name default --node-count +1 then kubectl uncordon node-affected.

VERIFICATION. df -h on the node should show under 70% used. The DiskPressure condition should clear within 5 minutes.

ROLLBACK. Re-cordoning the node is safe if the underlying disk issue is not resolved.

POST-INCIDENT. Add a node-disk-usage alert at 80% and a CI check that no pod uses hostPath logging.

REFERENCES. Kubernetes resource pressure doc; AKS node troubleshooting.'),

('DB.1', N'SQL deadlock chain analysis and resolution', N'DB',
 N'["deadlock","sql","index","1205","xevent"]',
 N'SYMPTOMS. Application logs show recurring Msg 1205 across multiple tables and stored procedures. The deadlock graph in the system_health XE session shows chains of 3 or more sessions, not just pairs.

DIAGNOSTIC SIGNALS. Run this T-SQL to extract recent deadlock graphs:
SELECT xml_data.query("/event/data/value/deadlock") AS deadlock_graph
FROM (SELECT CAST(event_data AS xml) AS xml_data FROM sys.fn_xe_file_target_read_file("system_health*.xel", null, null, null)) e
WHERE xml_data.exist("/event[@name=''xml_deadlock_report'']") = 1;
Inspect the resource-list and process-list nodes to identify which keys and which queries are involved.

ROOT CAUSE. Two or more queries are accessing the same set of rows in different orders, OR a query is being repeatedly forced into a scan instead of a seek because of missing indexes.

MITIGATION STEPS. (1) Capture deadlock graph as above. Save to /sre/deadlocks/2026-MM-DD.xdl for follow-up. (2) Add a covering nonclustered index that lets the offending queries seek instead of scan. (3) Reduce per-transaction batch size to shorten the lock hold time; many deadlocks disappear if individual transactions complete in under 100ms. (4) Re-run the workload and confirm no new Msg 1205 in the system_health ring buffer.

VERIFICATION. The xml_deadlock_report count over a 15-minute window should drop to zero. Query Store should show the new plan being used.

ROLLBACK. Drop the new index if it causes plan regressions on the read path; the deadlocks may return.

POST-INCIDENT. Add a Query Store alert on Msg 1205 above 1 per minute.

REFERENCES. SQL Server deadlock troubleshooting doc; xevent system_health reference.'),

('DB.3', N'Long-running batch causing transaction log bloat', N'DB',
 N'["batch","tlog","log-growth","checkpoint"]',
 N'SYMPTOMS. Transaction log file grows from baseline 5GB to 100GB+. Backup window extends from 10 minutes to several hours. Tlog auto-growth events appear in the SQL error log.

DIAGNOSTIC SIGNALS. SELECT log_reuse_wait_desc FROM sys.databases WHERE name="zavalivesitedb" returns ACTIVE_TRANSACTION or LOG_BACKUP. Long-running transactions can be found via DBCC OPENTRAN or sys.dm_tran_active_transactions.

ROOT CAUSE. A nightly ETL batch loads 10M rows in a single INSERT...SELECT, holding a single transaction for hours. The tlog cannot be truncated while the transaction is open, so it grows unbounded.

MITIGATION STEPS. (1) Break the batch into chunks of 5000 rows each, with an explicit COMMIT between chunks. Example:
WHILE EXISTS (SELECT 1 FROM source WHERE Processed = 0)
BEGIN
  BEGIN TRAN;
  INSERT target SELECT TOP (5000) * FROM source WHERE Processed = 0 ORDER BY Id;
  UPDATE TOP (5000) source SET Processed = 1 WHERE Processed = 0 ORDER BY Id;
  COMMIT;
  CHECKPOINT;
END
(2) Monitor log growth with sys.dm_db_log_space_usage; it should stay under 10GB. (3) Take a CHECKPOINT between chunks to allow log truncation in simple recovery model, or schedule LOG BACKUPs every 5 minutes in full recovery.

VERIFICATION. Log file size should plateau and not grow further during the batch. Backup window should return to baseline.

ROLLBACK. Reverting to single-transaction batch is safe but log growth returns.

POST-INCIDENT. Add an alert on log file size growth above 50% in a 1-hour window.

REFERENCES. SQL Server transaction log management doc; recovery model reference.'),

('Net.1', N'Partner endpoint flapping with circuit breaker', N'Net',
 N'["partner","timeout","circuit-breaker","tax-svc"]',
 N'SYMPTOMS. Calls to a partner endpoint (e.g. tax-svc-3.zava.io) fail with HTTP 504 in bursts. Failure rate alternates between 0% and 80% on a 30-90 second cycle.

DIAGNOSTIC SIGNALS. Check the upstream partner status page. Run a continuous curl against the endpoint and observe the failure pattern. Inspect Polly circuit-breaker state via the dotnet-counters CircuitBreakerState metric.

ROOT CAUSE. The partner endpoint is itself behind a load balancer with an unhealthy backend; the flapping reflects which backend handles the request.

MITIGATION STEPS. (1) Open the circuit breaker for 5 minutes by toggling Polly config CircuitBreakerOpenDuration=300s. (2) Switch to cached responses for read-heavy calls: enable Cache.UseStaleOnError=true. (3) Alert partner ops with the request-id and timing data so they can identify the bad backend. (4) If multiple partner endpoints are available, fail over to tax-svc-1 by setting PartnerEndpoint=tax-svc-1.zava.io.

VERIFICATION. Failure rate should drop to under 1% within 10 minutes of failover. Circuit breaker should close once partner returns to healthy.

ROLLBACK. Re-enabling tax-svc-3 is safe once partner confirms the bad backend is removed.

POST-INCIDENT. Add a partner health check that probes all configured endpoints every 30 seconds and auto-fails-over.

REFERENCES. Polly circuit-breaker doc; partner SLA reference.'),

('Net.4', N'TLS 1.3 incompatibility with legacy peers', N'Net',
 N'["tls","1.3","cipher","handshake","legacy"]',
 N'SYMPTOMS. Specific downstream services (typically third-party legacy systems) fail TLS handshake with errors like "no protocols available" or "handshake failure". Affected services tend to be older PHP or Java 7 stacks.

DIAGNOSTIC SIGNALS. openssl s_client -connect peer:443 -tls1_2 succeeds; openssl s_client -connect peer:443 -tls1_3 fails. The server-side log shows the TLS version negotiation failing.

ROOT CAUSE. An OS update enabled TLS 1.3 by default; certain legacy peers cannot handshake against TLS 1.3 with the default cipher suites.

MITIGATION STEPS. (1) Disable TLS 1.3 for the affected outbound host group by setting OutboundTls.MaxVersion=1.2 in the service config and rolling pods. (2) Pin the cipher list to TLS 1.2 known-good suites: TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256:TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384. (3) For inbound, do NOT disable TLS 1.3 globally; only on the specific host group.

VERIFICATION. openssl s_client repeated against the legacy peer should succeed. Handshake failure count should drop to zero within 5 minutes.

ROLLBACK. Re-enabling TLS 1.3 is safe once the peer is upgraded.

POST-INCIDENT. Track legacy peers by host group; require upgrade within 6 months or migrate off the integration.

REFERENCES. RFC 8446 (TLS 1.3); OpenSSL cipher suite reference.'),

('Generic.1', N'Unknown error triage starter playbook', N'Generic',
 N'["triage","unknown","correlationId","oncall"]',
 N'SYMPTOMS. An alert fires with an error class that does not match any known runbook. Initial signal is ambiguous: could be infra, app, dependency, or noise.

DIAGNOSTIC SIGNALS. Pull the correlationId from the originating alert. Query the central log store for the last 15 minutes of entries matching the correlationId across all services. Build a timeline of which service emitted what message and in what order.

ROOT CAUSE. Unknown until investigation completes.

MITIGATION STEPS. (1) Capture the correlationId and freeze the alert (do not silence) so it remains visible. (2) Pull the last 15 minutes of logs across all services using the SRE log explorer query "correlationId:X". (3) Page the secondary on-call if the alert is sev1 and you cannot localize the cause within 10 minutes. (4) Open an incident channel #inc-YYYYMMDD-NNN in Teams and post timeline updates every 5 minutes. (5) Once the cause is localized, jump to the appropriate specific runbook (Payroll.7, Auth.5, etc.).

VERIFICATION. Incident is considered triaged when one of: (a) a specific runbook is engaged, (b) the alert is identified as noise and the source is documented, or (c) the customer impact is confirmed contained.

ROLLBACK. N/A — no changes are made in pure triage.

POST-INCIDENT. If this runbook is being engaged frequently for a recurring pattern, file a follow-up to create a specific runbook for that pattern.

REFERENCES. SRE on-call handbook; incident response framework doc.');

INSERT dbo.Runbook (RunbookId, Title, Content, Tags, Embedding)
SELECT  RunbookId,
        Title,
        Content,
        JSON_OBJECT('service': Service, 'tags': JSON_QUERY(Tags)),
        AI_GENERATE_EMBEDDINGS(Title + N'. ' + Content USE MODEL OllamaMxbai)
FROM    @runbooks;
GO

PRINT '  Runbook seeding complete.';
GO

/*-----------------------------------------------------------
  AppLog ledger seed for incident #5012 (Beat 3).
  Deadlock-victim entries clustered around 14:30 UTC on 2026-05-04,
  matching the engineer note: Msg 1205, LCK_M_X on dbo.PayrollBatch,
  build 9114.10212.
-----------------------------------------------------------*/
IF NOT EXISTS (SELECT 1 FROM dbo.AppLog WHERE IncidentId = 5012)
INSERT dbo.AppLog (ts, IncidentId, level, message)
VALUES
    ('2026-05-04T14:25:11', 5012, N'info',  N'Payroll batch run started for tenant=zava run_date=2026-05-04'),
    ('2026-05-04T14:27:04', 5012, N'info',  N'Build 9114.10212 active on dbo.PayrollBatch (last clean rev 9114.10180)'),
    ('2026-05-04T14:29:42', 5012, N'warn',  N'Lock wait LCK_M_X on dbo.PayrollBatch key (TenantId, RunDate) exceeded 5s'),
    ('2026-05-04T14:30:08', 5012, N'error', N'Msg 1205, Level 13: Transaction was deadlocked on lock resources with another process and has been chosen as the deadlock victim'),
    ('2026-05-04T14:30:09', 5012, N'error', N'Payroll batch worker #3 aborted: deadlock victim, retry queued'),
    ('2026-05-04T14:31:22', 5012, N'error', N'Msg 1205 deadlock victim: dbo.PayrollBatch X-lock contention (worker #5)'),
    ('2026-05-04T14:32:00', 5012, N'crit',  N'Sev1 alert raised: Payroll batch Msg 1205 surge after 9114.10212 deploy'),
    ('2026-05-04T14:32:47', 5012, N'error', N'Pay-stub posting backlog: 1842 records pending, customers paging support'),
    ('2026-05-04T14:33:31', 5012, N'warn',  N'Wait stat dominant: LCK_M_X 89% on dbo.PayrollBatch over last 60s'),
    ('2026-05-04T14:34:55', 5012, N'info',  N'On-call engaged, finance lead notified, payday SLA at risk');
GO

PRINT '  AppLog ledger seeded (10 rows for IncidentId=5012).';
GO

/*-----------------------------------------------------------
  Sanity counts.
-----------------------------------------------------------*/
SELECT 'IncidentArchive' AS tbl, COUNT(*) AS rows_seeded FROM dbo.IncidentArchive
UNION ALL
SELECT 'Runbook',                COUNT(*)                FROM dbo.Runbook
UNION ALL
SELECT 'AppLog',                 COUNT(*)                FROM dbo.AppLog;
GO

PRINT '>>> 02_seed_corpus.sql complete. Run 03_vector_indexes.sql next.';
GO
