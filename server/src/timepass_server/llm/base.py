"""Provider interface for the generic tier.

A provider turns a conversation into streamed text (the model's JSON answer)
plus web sources when the provider grounded the answer with search. Parsing,
validation, repair, and A2UI framing are provider-agnostic and live in
llm/__init__.py — providers only speak text.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from collections.abc import AsyncIterator
from dataclasses import dataclass, field


@dataclass
class Source:
    title: str
    url: str
    domain: str


@dataclass
class Turn:
    role: str  # "user" | "assistant"
    text: str


@dataclass
class Chunk:
    """Incremental text from the model."""

    text: str


@dataclass
class Final:
    """End of stream: the full text and any grounding sources."""

    text: str
    sources: list[Source] = field(default_factory=list)


class Provider(ABC):
    name: str

    @abstractmethod
    def available(self) -> bool:
        """Whether this provider is configured (keys present)."""

    @abstractmethod
    def stream(
        self, system: str, turns: list[Turn], *, grounded: bool = True
    ) -> AsyncIterator[Chunk | Final]:
        """Stream a completion. Yields Chunks then exactly one Final."""

    @abstractmethod
    async def complete(
        self, system: str, turns: list[Turn], *, grounded: bool = False
    ) -> Final:
        """Non-streaming completion (used by the repair retry)."""
