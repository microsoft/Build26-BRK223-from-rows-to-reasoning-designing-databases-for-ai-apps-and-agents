from __future__ import annotations

from datetime import UTC, datetime

from models import DemoUser, Ticket


def utc_now() -> str:
    return datetime.now(UTC).isoformat()


DEMO_USERS: list[DemoUser] = [
    DemoUser(
        id="success-account-northwind",
        name="Northwind Analytics",
        role="VP Data Platform",
        company="Northwind Analytics",
        accent="#2563eb",
        summary="Enterprise analytics customer focused on executive dashboards, onboarding speed, and renewal risk.",
    ),
    DemoUser(
        id="success-account-contoso-health",
        name="Contoso Health",
        role="Security and compliance lead",
        company="Contoso Health",
        accent="#059669",
        summary="Regulated healthcare customer rolling out SSO, audit evidence, and data-governance controls.",
    ),
    DemoUser(
        id="success-account-fabrikam-retail",
        name="Fabrikam Retail",
        role="Growth operations manager",
        company="Fabrikam Retail",
        accent="#d97706",
        summary="Retail customer preparing QBRs, driving workflow adoption, and evaluating expansion opportunities.",
    ),
    DemoUser(
        id="success-account-alpine-robotics",
        name="Alpine Robotics",
        role="CTO",
        company="Alpine Robotics",
        accent="#7c3aed",
        summary="High-growth robotics customer focused on API reliability, launch readiness, and enterprise-plan value.",
    ),
]


TICKETS: dict[str, list[Ticket]] = {
    "success-account-northwind": [
        Ticket(
            id="engagement-northwind-discovery",
            title="Data platform discovery and success plan",
            status="Resolved",
            priority="Medium",
            product="Onboarding",
            created_at="2026-03-12T09:30:00+00:00",
        ),
        Ticket(
            id="engagement-northwind-onboarding",
            title="Executive dashboard onboarding milestone",
            status="Monitoring",
            priority="High",
            product="Onboarding",
            created_at="2026-05-21T09:10:00+00:00",
        ),
        Ticket(
            id="engagement-northwind-renewal-risk",
            title="Finance-team adoption and renewal risk",
            status="Open",
            priority="High",
            product="Renewal",
            created_at="2026-05-22T14:35:00+00:00",
        ),
        Ticket(
            id="engagement-northwind-forecasting",
            title="Predictive revenue forecasting expansion",
            status="Open",
            priority="Medium",
            product="Expansion",
            created_at="2026-05-27T15:05:00+00:00",
        ),
    ],
    "success-account-contoso-health": [
        Ticket(
            id="engagement-contoso-discovery",
            title="Security architecture discovery review",
            status="Resolved",
            priority="High",
            product="Enterprise security",
            created_at="2026-03-05T13:00:00+00:00",
        ),
        Ticket(
            id="engagement-contoso-phi",
            title="PHI encryption and key-management review",
            status="Open",
            priority="High",
            product="Compliance",
            created_at="2026-04-18T10:15:00+00:00",
        ),
        Ticket(
            id="engagement-contoso-sso",
            title="SSO rollout and identity mapping",
            status="Open",
            priority="High",
            product="Enterprise security",
            created_at="2026-05-20T16:20:00+00:00",
        ),
        Ticket(
            id="engagement-contoso-audit",
            title="Audit evidence for procurement review",
            status="Monitoring",
            priority="High",
            product="Compliance",
            created_at="2026-05-23T11:45:00+00:00",
        ),
        Ticket(
            id="engagement-contoso-incident",
            title="Incident response and BAA alignment",
            status="Monitoring",
            priority="High",
            product="Enterprise security",
            created_at="2026-05-26T09:50:00+00:00",
        ),
    ],
    "success-account-fabrikam-retail": [
        Ticket(
            id="engagement-fabrikam-onboarding",
            title="Campaign workflow automation onboarding",
            status="Resolved",
            priority="Medium",
            product="Onboarding",
            created_at="2026-04-02T10:30:00+00:00",
        ),
        Ticket(
            id="engagement-fabrikam-qbr",
            title="Executive QBR and adoption narrative",
            status="Monitoring",
            priority="High",
            product="QBR",
            created_at="2026-05-19T10:00:00+00:00",
        ),
        Ticket(
            id="engagement-fabrikam-expansion",
            title="Seasonal campaign automation expansion",
            status="Open",
            priority="Medium",
            product="Expansion",
            created_at="2026-05-24T13:15:00+00:00",
        ),
    ],
    "success-account-alpine-robotics": [
        Ticket(
            id="engagement-alpine-integration",
            title="Telemetry API integration kickoff",
            status="Resolved",
            priority="Medium",
            product="Onboarding",
            created_at="2026-03-28T08:20:00+00:00",
        ),
        Ticket(
            id="engagement-alpine-reliability",
            title="API reliability before production launch",
            status="Open",
            priority="High",
            product="Reliability",
            created_at="2026-05-18T08:40:00+00:00",
        ),
        Ticket(
            id="engagement-alpine-incident",
            title="Latency incident postmortem",
            status="Resolved",
            priority="High",
            product="Reliability",
            created_at="2026-05-22T17:10:00+00:00",
        ),
        Ticket(
            id="engagement-alpine-enterprise",
            title="Enterprise plan evaluation and roadmap fit",
            status="Monitoring",
            priority="High",
            product="Enterprise plan",
            created_at="2026-05-25T12:25:00+00:00",
        ),
    ],
}


SEED_DIALOGUES: dict[str, list[tuple[str, str, str]]] = {
    "success-account-northwind": [
        (
            "engagement-northwind-discovery",
            "user",
            "I'm Dana from Northwind Analytics. Before we commit, I need a success plan that proves we can stand up executive analytics without a long services engagement.",
        ),
        (
            "engagement-northwind-discovery",
            "agent",
            "Captured Northwind's goal of fast self-serve onboarding and recommended a 30-day success plan covering identity setup, data connections, and a first executive dashboard.",
        ),
        (
            "engagement-northwind-discovery",
            "user",
            "Our data lives in Snowflake and we authenticate through Okta, so any plan has to work with both from day one.",
        ),
        (
            "engagement-northwind-discovery",
            "agent",
            "Noted Snowflake as Northwind's primary data source and Okta as the identity provider for all onboarding and access planning.",
        ),
        (
            "engagement-northwind-onboarding",
            "user",
            "I'm Dana from Northwind Analytics. We need the first executive dashboard live before our June 15 board review.",
        ),
        (
            "engagement-northwind-onboarding",
            "agent",
            "Captured the June 15 executive deadline and recommended a success plan with Okta mapping, data freshness checks, and a dashboard-readiness review.",
        ),
        (
            "engagement-northwind-onboarding",
            "user",
            "Our blocker is Okta group mapping. Finance users cannot see the new revenue dashboard, and the CFO wants proof of daily data freshness.",
        ),
        (
            "engagement-northwind-onboarding",
            "agent",
            "For Northwind, follow-ups should lead with executive-ready adoption metrics, data freshness status, and any identity-mapping risks.",
        ),
        (
            "engagement-northwind-renewal-risk",
            "user",
            "Renewal is at risk if finance adoption does not improve this quarter. The CFO asked for a weekly progress summary.",
        ),
        (
            "engagement-northwind-renewal-risk",
            "agent",
            "Recommended a finance adoption plan with weekly enablement sessions, dashboard usage milestones, and CFO-ready progress reporting.",
        ),
        (
            "engagement-northwind-forecasting",
            "user",
            "Now that the executive dashboard is stable, the CFO wants predictive revenue forecasting before the next board cycle.",
        ),
        (
            "engagement-northwind-forecasting",
            "agent",
            "Captured predictive revenue forecasting as Northwind's next expansion and recommended scoping a pilot on the existing Snowflake revenue model.",
        ),
        (
            "engagement-northwind-forecasting",
            "user",
            "Keep it tied to the same finance audience we just won over, and reuse the daily freshness checks we already built.",
        ),
        (
            "engagement-northwind-forecasting",
            "agent",
            "For Northwind forecasting, reuse the finance adoption motion and existing freshness checks, and report progress in the CFO's weekly summary.",
        ),
    ],
    "success-account-contoso-health": [
        (
            "engagement-contoso-discovery",
            "user",
            "I'm Leena from Contoso Health. Security has to sign off before any clinical data touches the platform, so I need an architecture review first.",
        ),
        (
            "engagement-contoso-discovery",
            "agent",
            "Captured Contoso Health's security-first gate and recommended an architecture review covering identity, encryption, and data residency before onboarding clinical data.",
        ),
        (
            "engagement-contoso-discovery",
            "user",
            "We're a regulated healthcare provider, so HIPAA alignment and a signed BAA are non-negotiable.",
        ),
        (
            "engagement-contoso-discovery",
            "agent",
            "Noted that Contoso Health requires HIPAA alignment and a signed BAA as prerequisites for any data onboarding.",
        ),
        (
            "engagement-contoso-phi",
            "user",
            "We need confirmation that PHI is encrypted at rest and in transit, and that we control the encryption keys.",
        ),
        (
            "engagement-contoso-phi",
            "agent",
            "Captured Contoso Health's requirement for customer-managed keys with PHI encrypted at rest and in transit, and recommended documenting the key-management model for audit.",
        ),
        (
            "engagement-contoso-phi",
            "user",
            "Remember, anything we share with security must use audit-ready language, not marketing claims.",
        ),
        (
            "engagement-contoso-phi",
            "agent",
            "For Contoso Health, all security and PHI documentation must use audit-ready, evidence-based language.",
        ),
        (
            "engagement-contoso-sso",
            "user",
            "I'm Leena from Contoso Health. We need SSO live before the clinical pilot, and our security team requires least-privilege role mapping.",
        ),
        (
            "engagement-contoso-sso",
            "agent",
            "Captured the clinical-pilot deadline and recommended mapping Entra groups to least-privilege application roles before enabling SSO.",
        ),
        (
            "engagement-contoso-sso",
            "user",
            "Please remember that Contoso Health needs audit-ready language, not marketing language, whenever we discuss security controls.",
        ),
        (
            "engagement-contoso-audit",
            "user",
            "Procurement asked for evidence of data residency, access review history, and whether admin activity can be exported for seven years.",
        ),
        (
            "engagement-contoso-audit",
            "agent",
            "For Contoso Health, every compliance follow-up should include data residency, audit-export options, and access-review evidence.",
        ),
        (
            "engagement-contoso-incident",
            "user",
            "If there's a security incident involving our data, what's the notification timeline and how does it map to our BAA?",
        ),
        (
            "engagement-contoso-incident",
            "agent",
            "Captured Contoso Health's need for incident-notification timelines mapped to their BAA, and recommended sharing the incident-response runbook with audit-ready evidence of remediation.",
        ),
    ],
    "success-account-fabrikam-retail": [
        (
            "engagement-fabrikam-onboarding",
            "user",
            "I'm Marco from Fabrikam Retail. We're rolling out campaign workflow automation and need merchandising and store ops onboarded without disrupting peak season.",
        ),
        (
            "engagement-fabrikam-onboarding",
            "agent",
            "Captured Fabrikam's goal of onboarding campaign automation across merchandising and store operations without disrupting peak retail season.",
        ),
        (
            "engagement-fabrikam-onboarding",
            "user",
            "Merchandising can move fast, but store operations is cautious and will need extra enablement.",
        ),
        (
            "engagement-fabrikam-onboarding",
            "agent",
            "Noted that Fabrikam's merchandising team adopts quickly while store operations needs additional enablement and change management.",
        ),
        (
            "engagement-fabrikam-qbr",
            "user",
            "I'm Marco from Fabrikam Retail. Our executive QBR is next week, and I need a story around campaign workflow adoption.",
        ),
        (
            "engagement-fabrikam-qbr",
            "agent",
            "Recommended a QBR narrative around seasonal campaign velocity, workflow completion rates, and teams that still need enablement.",
        ),
        (
            "engagement-fabrikam-qbr",
            "user",
            "The merchandising team adopted automation quickly, but store operations still prefers manual approvals.",
        ),
        (
            "engagement-fabrikam-expansion",
            "user",
            "If the seasonal campaign pilot succeeds, we want to expand automation into returns management before holiday planning.",
        ),
        (
            "engagement-fabrikam-expansion",
            "agent",
            "Captured returns management as an expansion opportunity and recommended a pilot scorecard tied to campaign cycle time and manual approval reduction.",
        ),
    ],
    "success-account-alpine-robotics": [
        (
            "engagement-alpine-integration",
            "user",
            "I'm Nina from Alpine Robotics. We're integrating fleet telemetry through your API and need a clean path to production.",
        ),
        (
            "engagement-alpine-integration",
            "agent",
            "Captured Alpine's telemetry API integration goal and recommended a plan covering authentication, rate limits, and a staging-to-production path.",
        ),
        (
            "engagement-alpine-integration",
            "user",
            "We push high-frequency telemetry, so batching and rate limits matter more than anything else.",
        ),
        (
            "engagement-alpine-integration",
            "agent",
            "Noted that Alpine sends high-frequency telemetry, making batching strategy and API rate limits the priority for integration design.",
        ),
        (
            "engagement-alpine-reliability",
            "user",
            "I'm Nina from Alpine Robotics. We launch production fleet telemetry next month, and API latency over 500 ms will block rollout.",
        ),
        (
            "engagement-alpine-reliability",
            "agent",
            "Captured the production launch date and recommended a reliability review around p95 latency, retry behavior, and alerting before rollout.",
        ),
        (
            "engagement-alpine-reliability",
            "user",
            "Alpine prefers direct technical detail and does not want high-level adoption slides unless an executive is in the meeting.",
        ),
        (
            "engagement-alpine-incident",
            "user",
            "We hit a latency spike yesterday that pushed p95 past 800 ms during a load test. I need a postmortem.",
        ),
        (
            "engagement-alpine-incident",
            "agent",
            "Captured Alpine's latency incident with p95 exceeding 800 ms under load and recommended a postmortem covering root cause, retry behavior, and capacity headroom.",
        ),
        (
            "engagement-alpine-incident",
            "user",
            "Give me direct technical detail in the writeup, not an executive summary.",
        ),
        (
            "engagement-alpine-incident",
            "agent",
            "For Alpine, the incident postmortem and follow-ups should stay technically detailed and skip executive-summary framing.",
        ),
        (
            "engagement-alpine-enterprise",
            "user",
            "We are evaluating the enterprise plan, but the CTO needs roadmap clarity for private networking and higher API limits.",
        ),
        (
            "engagement-alpine-enterprise",
            "agent",
            "For Alpine enterprise-plan discussions, include private networking status, API-limit options, and the business impact on production fleet rollout.",
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