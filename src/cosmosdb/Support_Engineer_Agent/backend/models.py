from __future__ import annotations

from typing import Any

from pydantic import BaseModel, Field


class DemoUser(BaseModel):
    id: str
    name: str
    role: str
    company: str
    accent: str
    summary: str


class Ticket(BaseModel):
    id: str
    title: str
    status: str = "Open"
    priority: str = "Medium"
    product: str
    created_at: str


class ChatMessage(BaseModel):
    role: str
    content: str


class NewTicketRequest(BaseModel):
    title: str
    product: str = "Microsoft Cloud"
    priority: str = "Medium"


class MessageRequest(BaseModel):
    content: str = Field(min_length=1)


class MessageResponse(BaseModel):
    thread_id: str
    response: str
    recalled_memories: list[dict[str, Any]]
    profile: dict[str, Any] | None = None
    facts: list[dict[str, Any]] = Field(default_factory=list)


class ProcessResponse(BaseModel):
    thread_id: str
    extraction: dict[str, Any]
    thread_summary: dict[str, Any]
    user_summary: dict[str, Any]


class UserProfileResponse(BaseModel):
    user: DemoUser
    profile: dict[str, Any] | None = None
    facts: list[dict[str, Any]] = Field(default_factory=list)
    procedural: list[dict[str, Any]] = Field(default_factory=list)
    episodic: list[dict[str, Any]] = Field(default_factory=list)


class UserTicketsResponse(BaseModel):
    user_id: str
    tickets: list[Ticket]