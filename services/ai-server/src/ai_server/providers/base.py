from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass


@dataclass
class AnalysisResult:
    response: str
    model: str
    processing_ms: int


class AnalysisProvider(ABC):
    def __init__(self, model: str, settings: object) -> None:
        self.model = model
        self.settings = settings

    @abstractmethod
    async def analyze(self, image: bytes, prompt: str) -> AnalysisResult:
        ...
