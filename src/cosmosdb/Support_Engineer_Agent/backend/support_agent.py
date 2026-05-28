from __future__ import annotations

from typing import Any

from memory_service import MemoryService
from models import DemoUser


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


def create_support_response(
    *,
    memory: MemoryService,
    user: DemoUser,
    thread_id: str,
    message: str,
) -> dict[str, Any]:
    recalled = memory.search_context(user_id=user.id, query=message, top_k=5)
    profile = memory.get_profile(user_id=user.id)
    facts = memory.get_memories_by_type(user_id=user.id, memory_type="fact", recent_k=8)
    existing_thread = memory.get_thread(user_id=user.id, thread_id=thread_id)[-8:]

    conversation = "\n".join(f"{turn['role']}: {turn['content']}" for turn in existing_thread)
    prompt = [
        {
            "role": "system",
            "content": (
                "You are Support Engineer Agent, a careful technical support engineer. "
                "Use the supplied Agent Memory Toolkit context when it is relevant. "
                "Do not claim certainty when the stored memory is ambiguous. "
                "Keep the answer practical, customer-specific, and action-oriented. "
                "Refer to yourself as Support Engineer Agent."
            ),
        },
        {
            "role": "user",
            "content": (
                f"Customer: {user.name}\n"
                f"Role: {user.role}\n"
                f"Company: {user.company}\n"
                f"Memory scope: {user.id}\n\n"
                f"Generated user profile:\n{_render_profile(profile)}\n\n"
                f"Relevant recalled memories:\n{_render_memory_context(recalled)}\n\n"
                f"Recent ticket conversation:\n{conversation or 'No prior turns in this ticket.'}\n\n"
                f"Latest customer message:\n{message}"
            ),
        },
    ]

    response = memory.generate_agent_response(messages=prompt)
    memory.add_turn(user_id=user.id, thread_id=thread_id, role="user", content=message)
    memory.add_turn(user_id=user.id, thread_id=thread_id, role="agent", content=response)

    return {
        "thread_id": thread_id,
        "response": response,
        "recalled_memories": [compact_memory(item) for item in recalled],
        "profile": profile,
        "facts": [compact_memory(item) for item in facts],
    }