from __future__ import annotations

from datetime import UTC, datetime

from models import DemoUser, Ticket


def utc_now() -> str:
    return datetime.now(UTC).isoformat()


DEMO_USERS: list[DemoUser] = [
    DemoUser(
        id="support-user-james",
        name="James",
        role="Enterprise IT admin",
        company="Northwind Manufacturing",
        accent="#2563eb",
        summary="Manages Windows devices and Microsoft 365 for a distributed enterprise team.",
    ),
    DemoUser(
        id="support-user-aayush",
        name="Aayush",
        role="Startup founder and developer",
        company="PacketForge Labs",
        accent="#059669",
        summary="Prefers concise, technical answers about reliability, webhooks, and API latency.",
    ),
    DemoUser(
        id="support-user-theo",
        name="Theo",
        role="Data engineer",
        company="Contoso Analytics",
        accent="#d97706",
        summary="Runs Azure-heavy data systems and cares about Cosmos DB throughput and query plans.",
    ),
    DemoUser(
        id="support-user-raj",
        name="Raj",
        role="Security and compliance lead",
        company="Fabrikam Financial",
        accent="#7c3aed",
        summary="Focuses on audit trails, access control, retention policies, and approval workflows.",
    ),
]


TICKETS: dict[str, list[Ticket]] = {
    "support-user-james": [
        Ticket(
            id="ticket-james-intune",
            title="Intune enrollment failures for Surface devices",
            status="Monitoring",
            priority="High",
            product="Microsoft Intune",
            created_at="2026-05-21T09:10:00+00:00",
        ),
        Ticket(
            id="ticket-james-battery",
            title="Surface Pro battery diagnostics",
            status="Resolved",
            priority="Medium",
            product="Surface Pro 9",
            created_at="2026-05-22T14:35:00+00:00",
        ),
    ],
    "support-user-aayush": [
        Ticket(
            id="ticket-aayush-webhook",
            title="Webhook delivery retries and duplicate events",
            status="Open",
            priority="High",
            product="Azure API Management",
            created_at="2026-05-20T16:20:00+00:00",
        ),
        Ticket(
            id="ticket-aayush-latency",
            title="API latency regression after deployment",
            status="Resolved",
            priority="Medium",
            product="Azure App Service",
            created_at="2026-05-23T11:45:00+00:00",
        ),
    ],
    "support-user-theo": [
        Ticket(
            id="ticket-theo-cosmos-ru",
            title="Cosmos DB RU spikes during dashboard refresh",
            status="Open",
            priority="High",
            product="Azure Cosmos DB",
            created_at="2026-05-19T10:00:00+00:00",
        ),
        Ticket(
            id="ticket-theo-query",
            title="Slow analytical query over device telemetry",
            status="Monitoring",
            priority="Medium",
            product="Azure Cosmos DB",
            created_at="2026-05-24T13:15:00+00:00",
        ),
    ],
    "support-user-raj": [
        Ticket(
            id="ticket-raj-rbac",
            title="Privileged access review for production subscription",
            status="Open",
            priority="High",
            product="Microsoft Entra ID",
            created_at="2026-05-18T08:40:00+00:00",
        ),
        Ticket(
            id="ticket-raj-audit",
            title="Audit log export and retention requirements",
            status="Monitoring",
            priority="High",
            product="Microsoft Purview",
            created_at="2026-05-25T12:25:00+00:00",
        ),
    ],
}


SEED_DIALOGUES: dict[str, list[tuple[str, str, str]]] = {
    "support-user-james": [
        (
            "ticket-james-intune",
            "user",
            "I'm James from Northwind Manufacturing. Intune enrollment is failing for a batch of Surface Pro 9 devices with error 80180014.",
        ),
        (
            "ticket-james-intune",
            "agent",
            "Thanks James. We should check device enrollment restrictions, confirm the users have Intune licenses, and verify the devices are not blocked by platform restrictions.",
        ),
        (
            "ticket-james-intune",
            "user",
            "The license assignment was fine. We found a stale device enrollment restriction scoped to the pilot group.",
        ),
        (
            "ticket-james-intune",
            "agent",
            "We removed the stale restriction, asked James to retry enrollment on two devices, and kept the ticket in monitoring.",
        ),
        (
            "ticket-james-battery",
            "user",
            "One Surface Pro 9 battery drains in about 3 hours. I need detailed troubleshooting steps because these devices are assigned to executives.",
        ),
        (
            "ticket-james-battery",
            "agent",
            "James prefers detailed steps. We asked him to run the Surface app diagnostic, export a battery report, and check firmware updates before replacement.",
        ),
    ],
    "support-user-aayush": [
        (
            "ticket-aayush-webhook",
            "user",
            "I'm Aayush. Our checkout webhooks are arriving twice after retries. I need concise technical answers and timestamps for anything you find.",
        ),
        (
            "ticket-aayush-webhook",
            "agent",
            "We saw retry storms after 502 responses from PacketForge's webhook endpoint. Recommended idempotency keys and a dead-letter view for failed delivery attempts.",
        ),
        (
            "ticket-aayush-webhook",
            "user",
            "We added idempotency keys. The remaining issue is p95 delivery latency above 8 seconds during deploys.",
        ),
        (
            "ticket-aayush-latency",
            "user",
            "API latency jumped right after yesterday's deployment. Cold starts seem possible, but I need the shortest path to rule it out.",
        ),
        (
            "ticket-aayush-latency",
            "agent",
            "We enabled Always On for the App Service, pinned minimum instances during release windows, and asked Aayush to compare p95 latency before and after warmup.",
        ),
    ],
    "support-user-theo": [
        (
            "ticket-theo-cosmos-ru",
            "user",
            "I'm Theo from Contoso Analytics. Our Cosmos DB container telemetry-events spikes to 18k RU/s whenever the operations dashboard refreshes.",
        ),
        (
            "ticket-theo-cosmos-ru",
            "agent",
            "The dashboard query filters by deviceType but not tenantId. Recommended adding tenantId to the query and checking whether partition key /tenantId is aligned with the access pattern.",
        ),
        (
            "ticket-theo-cosmos-ru",
            "user",
            "Container partition key is /tenantId. The expensive query selected all fields and sorted by eventTime without a composite index.",
        ),
        (
            "ticket-theo-query",
            "user",
            "The analytical query over device telemetry is still slow. It only needs five fields, not the full payload.",
        ),
        (
            "ticket-theo-query",
            "agent",
            "Recommended projecting only required fields, adding a composite index for tenantId and eventTime, and testing with continuation tokens instead of one large page.",
        ),
    ],
    "support-user-raj": [
        (
            "ticket-raj-rbac",
            "user",
            "I'm Raj from Fabrikam Financial. We need evidence for who has privileged access to production and when access was approved.",
        ),
        (
            "ticket-raj-rbac",
            "agent",
            "Raj needs audit-ready answers. Recommended Microsoft Entra privileged identity management access reviews and exportable approval history.",
        ),
        (
            "ticket-raj-rbac",
            "user",
            "Any change to production access must include ticket number, approver, start time, and expiry time.",
        ),
        (
            "ticket-raj-audit",
            "user",
            "For audit logs, we need retention beyond the default window and a way to prove exports were not modified.",
        ),
        (
            "ticket-raj-audit",
            "agent",
            "Recommended exporting audit logs to immutable storage with retention policies and documenting the chain of custody in the support ticket.",
        ),
    ],
}


def get_user(user_id: str) -> DemoUser | None:
    return next((user for user in DEMO_USERS if user.id == user_id), None)


def get_tickets(user_id: str) -> list[Ticket]:
    return list(TICKETS.get(user_id, []))


def add_ticket(user_id: str, ticket: Ticket) -> Ticket:
    TICKETS.setdefault(user_id, []).insert(0, ticket)
    return ticket