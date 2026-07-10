from __future__ import annotations

import time
from base64 import b64encode

import httpx

from ai_server.config import Settings
from ai_server.logging import get_logger
from ai_server.providers.base import AnalysisProvider, AnalysisResult

logger = get_logger(__name__)


class OllamaProvider(AnalysisProvider):
    def __init__(self, model: str, settings: Settings) -> None:
        super().__init__(model, settings)
        self.base_url = settings.ollama_base_url.rstrip("/")

    async def analyze(self, image: bytes, prompt: str) -> AnalysisResult:
        start = time.monotonic()
        b64_image = b64encode(image).decode()
        payload = {
            "model": self.model,
            "messages": [
                {
                    "role": "user",
                    "content": prompt,
                    "images": [b64_image],
                }
            ],
            "stream": False,
        }
        logger.debug("Calling Ollama", extra={"props": {"model": self.model, "image_size": len(image)}})
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{self.base_url}/api/chat",
                json=payload,
                timeout=300.0,
            )
            response.raise_for_status()
            data = response.json()
        elapsed = int((time.monotonic() - start) * 1000)
        content = data["message"]["content"]
        logger.info("Ollama analysis completed", extra={"props": {"model": self.model, "duration_ms": elapsed, "response_length": len(content)}})
        return AnalysisResult(response=content, model=self.model, processing_ms=elapsed)
