# Talk Track — Agent Memory Toolkit on Azure Cosmos DB

**Demo:** Customer Success Agent
**Target length:** 3–4 minutes of speaking


NOTES:
Go through process
Go into code
show search, invocation of toolkit capabilties


---

## The problem (≈30 sec)

> "Memory is a critical attribute of humans and agents alike. It lets agents recall past experiences, reason over history, and respond with real contextual relevance. But most ways of managing memory today fall short — they're **rigid**, locked into fixed data models; they're **expensive**, with heavy processing costs; and they lack **operational guarantees** like high availability and **enterprise readiness** like multi-tenancy."
>
> "Today we're excited to show the **Agent Memory Toolkit for Azure Cosmos DB** — an SDK and serverless arhictecture for memory storage, processing, and retrieval, built on the world's most scalable NoSQL database."

---

## What is the Agent Memory Toolkit? (≈45 sec)

> "The **Agent Memory Toolkit** gives AI agents long-term memory. Instead of just keeping chat history, it automatically extracts durable **facts**, **procedural** preferences (how a customer wants to be handled), and **episodic** events from raw conversations — then recalls the *right* memories for the current question using semantic search."

- **Self-maintaining.** One processing step summarizes a conversation, updates a profile, and reconciles or supersedes outdated facts.
- **Isolated by design.** Memory is scoped per account, so one customer's context never leaks into another's.
- **Serverless and drop-in.** It runs as **serverless** processing — no infrastructure to manage, scales to zero when idle. For developers it's just a few calls: `add`, `search`, `get_memories`, plus the pipeline.

---

## Why Azure Cosmos DB (≈40 sec)

> "All of that memory lives in **Azure Cosmos DB** — the memory store of record."

- **Vector + operational data together.** Native vector search powers semantic recall *in the same database* that stores the records — no separate vector store to sync.
- **Built for agents at scale.** Low-latency reads/writes, elastic scale, and global distribution keep memory fast as accounts and traffic grow.
- **Serverless option.** Cosmos DB serverless pairs naturally with serverless processing — you pay for what you use.
- **Tenant isolation by design.** Partitioning by account maps cleanly to per-customer memory boundaries.

---

## What we'll see today (≈25 sec)

> "This is a **Customer Success Agent** built on the toolkit. It manages four SaaS accounts — Northwind, Contoso Health, Fabrikam Retail, and Alpine Robotics — each with several prior engagements. The point: the agent *remembers* each account across conversations, so every interaction starts with full context instead of a blank slate."

---

## Walkthrough (≈90 sec — live)

1. **Pick an account.** Show the seeded accounts and their prior engagements — this is memory that already exists.
2. **Ask a recall question (Sample Q1).** The agent answers using stored facts and summaries from *past* engagements. Open the **Memory Inspector** to show exactly which memories were recalled for that answer.
3. **Ask a lifecycle question (Sample Q2).** Show how memory evolves over time across engagements — goals, blockers, and preferences carried forward.
4. **Process memory (Database button).** Run extraction + summarization on the engagement and watch new facts, procedural/episodic memories, and an updated account profile appear.
5. **See it in Cosmos DB.** Open the **Azure Cosmos DB Data Explorer** and show the actual stored documents — conversations, the extracted memory items, and the account profile, each partitioned by account. This is the same database that powers the semantic recall you just saw.
6. **Switch accounts.** Reinforce isolation — the new account only sees its own memory.

---

## Closing line (≈15 sec)

> "So with the Agent Memory Toolkit on Azure Cosmos DB, you get an agent that remembers — relevant, isolated, and self-maintaining memory — running serverless on the database you already trust for operational and vector data."
