from __future__ import annotations

import uuid
from contextlib import asynccontextmanager
from typing import Any

from fastapi import Depends, FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from memory_service import (
    MemoryService,
    close_memory_service,
    get_config_status,
    get_memory_service,
)
from models import MessageRequest, NewTicketRequest, Ticket
from seed_data import DEMO_USERS, SEED_DIALOGUES, add_ticket, get_tickets, get_user, utc_now
from support_agent import compact_memory, create_success_response


@asynccontextmanager
async def lifespan(_: FastAPI):
    yield
    await close_memory_service()


app = FastAPI(title="Customer Success Agent API", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:5173", "http://127.0.0.1:5173"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
    allow_origin_regex=r"http://(localhost|127\.0\.0\.1):\d+",
)


def _require_user(user_id: str):
    user = get_user(user_id)
    if not user:
        raise HTTPException(status_code=404, detail=f"Unknown demo user: {user_id}")
    return user


def _compact_record(record: dict[str, Any]) -> dict[str, Any]:
    return compact_memory(record)


@app.get("/api/health")
def health() -> dict[str, str]:
    return {"status": "ok", "service": "Customer Success Agent"}


@app.get("/api/config/status")
def config_status() -> dict[str, Any]:
    return get_config_status()


@app.get("/api/users")
def list_users() -> list[dict[str, Any]]:
    return [user.model_dump() for user in DEMO_USERS]


@app.get("/api/users/{user_id}/profile")
async def get_profile(user_id: str, memory: MemoryService = Depends(get_memory_service)) -> dict[str, Any]:
    user = _require_user(user_id)
    return {
        "user": user.model_dump(),
        "profile": await memory.get_profile(user_id=user_id),
        "facts": [_compact_record(item) for item in await memory.get_memories_by_type(user_id=user_id, memory_type="fact")],
        "procedural": [
            _compact_record(item) for item in await memory.get_memories_by_type(user_id=user_id, memory_type="procedural")
        ],
        "episodic": [
            _compact_record(item) for item in await memory.get_memories_by_type(user_id=user_id, memory_type="episodic")
        ],
    }


@app.get("/api/users/{user_id}/tickets")
def list_tickets(user_id: str) -> dict[str, Any]:
    _require_user(user_id)
    return {"user_id": user_id, "tickets": [ticket.model_dump() for ticket in get_tickets(user_id)]}


@app.post("/api/users/{user_id}/tickets")
def create_ticket(user_id: str, request: NewTicketRequest) -> dict[str, Any]:
    _require_user(user_id)
    ticket = Ticket(
        id=f"engagement-{uuid.uuid4().hex[:8]}",
        title=request.title,
        product=request.product,
        priority=request.priority,
        created_at=utc_now(),
    )
    add_ticket(user_id, ticket)
    return ticket.model_dump()


@app.get("/api/users/{user_id}/tickets/{thread_id}/messages")
async def get_messages(user_id: str, thread_id: str, memory: MemoryService = Depends(get_memory_service)) -> list[dict[str, Any]]:
    _require_user(user_id)
    return [_compact_record(item) for item in await memory.get_thread(user_id=user_id, thread_id=thread_id)]


@app.post("/api/users/{user_id}/tickets/{thread_id}/messages")
async def post_message(
    user_id: str,
    thread_id: str,
    request: MessageRequest,
    memory: MemoryService = Depends(get_memory_service),
) -> dict[str, Any]:
    user = _require_user(user_id)
    return await create_success_response(memory=memory, user=user, thread_id=thread_id, message=request.content)


@app.get("/api/users/{user_id}/memories")
async def search_memories(
    user_id: str,
    q: str,
    memory: MemoryService = Depends(get_memory_service),
) -> list[dict[str, Any]]:
    _require_user(user_id)
    return [_compact_record(item) for item in await memory.search_context(user_id=user_id, query=q, top_k=8)]


@app.post("/api/users/{user_id}/tickets/{thread_id}/process")
async def process_ticket(user_id: str, thread_id: str, memory: MemoryService = Depends(get_memory_service)) -> dict[str, Any]:
    _require_user(user_id)
    return await memory.process_thread(user_id=user_id, thread_id=thread_id)


@app.post("/api/demo/seed")
async def seed_demo(process: bool = False, memory: MemoryService = Depends(get_memory_service)) -> dict[str, Any]:
    threads_by_user = {
        user.id: sorted({thread_id for thread_id, _, _ in SEED_DIALOGUES.get(user.id, [])}) for user in DEMO_USERS
    }
    seeded: dict[str, list[str]] = {user.id: [] for user in DEMO_USERS}
    skipped: dict[str, list[str]] = {user.id: [] for user in DEMO_USERS}
    processed: dict[str, list[str]] = {user.id: [] for user in DEMO_USERS}

    for user in DEMO_USERS:
        for thread_id in threads_by_user[user.id]:
            turns = [(role, content) for seed_thread_id, role, content in SEED_DIALOGUES[user.id] if seed_thread_id == thread_id]
            result = await memory.seed_thread_if_empty(user_id=user.id, thread_id=thread_id, turns=turns)
            target = seeded if result == "seeded" else skipped
            target[user.id].append(thread_id)

            if process:
                await memory.process_thread(user_id=user.id, thread_id=thread_id)
                processed[user.id].append(thread_id)

    return {
        "status": "seeded" if any(seeded.values()) else "already_seeded",
        "processed": process,
        "seeded": seeded,
        "skipped": skipped,
        "processed_threads": processed,
    }


@app.post("/api/demo/reset")
async def reset_demo(memory: MemoryService = Depends(get_memory_service)) -> dict[str, Any]:
    demo_user_ids = [user.id for user in DEMO_USERS]
    deleted = await memory.reset_demo_records(user_ids=demo_user_ids)
    return {"status": "reset", "deleted": deleted, "scope": demo_user_ids}