from __future__ import annotations

import os
from functools import lru_cache
from pathlib import Path
from typing import Any

from dotenv import load_dotenv

from agent_memory_toolkit import ChatClient, CosmosMemoryClient


SCENARIO_ROOT = Path(__file__).resolve().parents[1]
load_dotenv(SCENARIO_ROOT / ".env")
load_dotenv()


DERIVED_MEMORY_TYPES = ["fact", "procedural", "episodic"]
DEMO_TAG = "demo:support-engineer-agent"


def get_config_status() -> dict[str, Any]:
    required = ["COSMOS_DB_ENDPOINT", "AI_FOUNDRY_ENDPOINT"]
    optional = ["COSMOS_DB_KEY", "AI_FOUNDRY_API_KEY"]
    missing = [name for name in required if not os.environ.get(name)]
    return {
        "configured": not missing,
        "missing": missing,
        "auth": {
            "cosmos_key": bool(os.environ.get("COSMOS_DB_KEY")),
            "ai_foundry_api_key": bool(os.environ.get("AI_FOUNDRY_API_KEY")),
            "default_credential": any(not os.environ.get(name) for name in optional),
        },
        "database": os.environ.get("COSMOS_DB_DATABASE", "ai_memory"),
        "container": os.environ.get("COSMOS_DB_CONTAINER", "memories"),
    }


class MemoryService:
    def __init__(self) -> None:
        cosmos_endpoint = os.environ.get("COSMOS_DB_ENDPOINT")
        ai_foundry_endpoint = os.environ.get("AI_FOUNDRY_ENDPOINT")
        if not cosmos_endpoint or not ai_foundry_endpoint:
            raise RuntimeError("COSMOS_DB_ENDPOINT and AI_FOUNDRY_ENDPOINT must be set before starting the backend.")

        ai_foundry_api_key = os.environ.get("AI_FOUNDRY_API_KEY") or None
        ai_foundry_credential = None
        if not ai_foundry_api_key:
            from azure.identity import DefaultAzureCredential

            ai_foundry_credential = DefaultAzureCredential()

        self.client = CosmosMemoryClient(
            cosmos_endpoint=cosmos_endpoint,
            cosmos_key=os.environ.get("COSMOS_DB_KEY") or None,
            cosmos_database=os.environ.get("COSMOS_DB_DATABASE", "ai_memory"),
            cosmos_container=os.environ.get("COSMOS_DB_CONTAINER", "memories"),
            ai_foundry_endpoint=ai_foundry_endpoint,
            ai_foundry_credential=ai_foundry_credential,
            ai_foundry_api_key=ai_foundry_api_key,
            embedding_deployment_name=os.environ.get(
                "AI_FOUNDRY_EMBEDDING_DEPLOYMENT_NAME",
                "text-embedding-3-large",
            ),
            chat_deployment_name=os.environ.get("AI_FOUNDRY_CHAT_DEPLOYMENT_NAME", "gpt-4o-mini"),
        )
        self.chat = ChatClient(
            endpoint=ai_foundry_endpoint,
            credential=ai_foundry_credential,
            api_key=ai_foundry_api_key,
            model=os.environ.get("AI_FOUNDRY_CHAT_DEPLOYMENT_NAME", "gpt-4o-mini"),
        )
        self.client.connect_cosmos()

    def add_turn(self, *, user_id: str, thread_id: str, role: str, content: str) -> str:
        return self.client.add_cosmos(
            user_id=user_id,
            thread_id=thread_id,
            role=role,
            content=content,
            tags=[DEMO_TAG],
        )

    def get_thread(self, *, user_id: str, thread_id: str) -> list[dict[str, Any]]:
        return self.client.get_thread(user_id=user_id, thread_id=thread_id, memory_types=["turn"])

    def search_context(self, *, user_id: str, query: str, top_k: int = 5) -> list[dict[str, Any]]:
        if not query.strip():
            return []
        return self.client.search_cosmos(
            search_terms=query,
            user_id=user_id,
            memory_types=DERIVED_MEMORY_TYPES + ["summary", "user_summary"],
            top_k=top_k,
            include_superseded=False,
        )

    def get_profile(self, *, user_id: str) -> dict[str, Any] | None:
        summaries = self.client.get_memories(user_id=user_id, memory_types=["user_summary"], recent_k=1)
        return summaries[-1] if summaries else None

    def get_memories_by_type(self, *, user_id: str, memory_type: str, recent_k: int = 12) -> list[dict[str, Any]]:
        return self.client.get_memories(
            user_id=user_id,
            memory_types=[memory_type],
            recent_k=recent_k,
            include_superseded=False,
        )

    def process_thread(self, *, user_id: str, thread_id: str) -> dict[str, Any]:
        extraction = self.client.extract_memories(user_id=user_id, thread_id=thread_id)
        thread_summary = self.client.generate_thread_summary(user_id=user_id, thread_id=thread_id)
        user_summary = self.client.generate_user_summary(user_id=user_id)
        return {
            "thread_id": thread_id,
            "extraction": extraction,
            "thread_summary": thread_summary,
            "user_summary": user_summary,
        }

    def generate_agent_response(self, *, messages: list[dict[str, str]]) -> str:
        return self.chat.generate(messages, temperature=0.2)

    def seed_thread_if_empty(self, *, user_id: str, thread_id: str, turns: list[tuple[str, str]]) -> str:
        if self.get_thread(user_id=user_id, thread_id=thread_id):
            return "already_seeded"

        for role, content in turns:
            self.add_turn(user_id=user_id, thread_id=thread_id, role=role, content=content)
        return "seeded"

    def reset_demo_records(self, *, user_ids: list[str]) -> int:
        records: list[dict[str, Any]] = []
        for user_id in user_ids:
            records.extend(self.client.get_memories(user_id=user_id, include_superseded=True))

        deleted = 0
        for record in records:
            self.client.delete_cosmos(
                memory_id=record["id"],
                user_id=record["user_id"],
                thread_id=record["thread_id"],
            )
            deleted += 1
        return deleted


@lru_cache(maxsize=1)
def get_memory_service() -> MemoryService:
    return MemoryService()