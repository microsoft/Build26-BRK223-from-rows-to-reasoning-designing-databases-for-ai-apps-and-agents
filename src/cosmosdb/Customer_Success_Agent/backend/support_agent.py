from __future__ import annotations

from pathlib import Path
from typing import Any

from memory_service import MemoryService
from models import DemoUser

_SYSTEM_PROMPT_PATH = Path(__file__).parent / "prompts" / "support_agent_system.txt"
SYSTEM_PROMPT = _SYSTEM_PROMPT_PATH.read_text(encoding="utf-8").strip()


def compact_memory(record: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": record.get("id"),
        "type": record.get("type"),
        "role": record.get("role"),
        "content": record.get("content"),
        "confidence": record.get("confidence"),
        "thread_id": record.get("thread_id"),
        "created_at": record.get("created_at"),
        "supersede_reason": record.get("supersede_reason"),
        "tags": record.get("tags", []),
    }


def _render_memory_context(records: list[dict[str, Any]]) -> str:
    if not records:
        return "No relevant stored memories were found."
    lines = []
    for index, record in enumerate(records, 1):
        memory_type = record.get("type", "memory")
        thread_id = record.get("thread_id", "unknown-thread")
        content = record.get("content", "")
        lines.append(f"{index}. [{memory_type} from {thread_id}] {content}")
    return "\n".join(lines)


def _render_profile(profile: dict[str, Any] | None) -> str:
    if not profile:
        return "No generated user summary is available yet."
    return str(profile.get("content") or "No generated user summary is available yet.")


async def create_success_response(
    *,
    memory: MemoryService,
    user: DemoUser,
    thread_id: str,
    message: str,
) -> dict[str, Any]:
    recalled = await memory.search_context(user_id=user.id, query=message, top_k=5)
    profile = await memory.get_profile(user_id=user.id)
    facts = await memory.get_memories_by_type(user_id=user.id, memory_type="fact", recent_k=8)
    existing_thread = (await memory.get_thread(user_id=user.id, thread_id=thread_id))[-8:]

    conversation = "\n".join(f"{turn['role']}: {turn['content']}" for turn in existing_thread)
    prompt = [
        {
            "role": "system",
            "content": SYSTEM_PROMPT,
        },
        {
            "role": "user",
            "content": (
                f"Account: {user.company}\n"
                f"Primary stakeholder: {user.name}\n"
                f"Stakeholder role: {user.role}\n"
                f"Company: {user.company}\n"
                f"Memory scope: {user.id}\n\n"
                f"Generated user profile:\n{_render_profile(profile)}\n\n"
                f"Relevant recalled memories:\n{_render_memory_context(recalled)}\n\n"
                f"Recent engagement conversation:\n{conversation or 'No prior turns in this engagement.'}\n\n"
                f"Latest account message:\n{message}"
            ),
        },
    ]

    response = await memory.generate_agent_response(messages=prompt)
    await memory.add_turn(user_id=user.id, thread_id=thread_id, role="user", content=message)
    await memory.add_turn(user_id=user.id, thread_id=thread_id, role="agent", content=response)

    return {
        "thread_id": thread_id,
        "response": response,
        "recalled_memories": [compact_memory(item) for item in recalled],
        "profile": profile,
        "facts": [compact_memory(item) for item in facts],
    }