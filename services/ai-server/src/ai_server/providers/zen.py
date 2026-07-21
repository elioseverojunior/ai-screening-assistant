from __future__ import annotations

import time
from base64 import b64encode
from typing import Any

import httpx

from ai_server.config import Settings
from ai_server.logging import get_logger
from ai_server.providers.base import AnalysisProvider, AnalysisResult

logger = get_logger(__name__)


class ZenProvider(AnalysisProvider):
    BASE_URL = "https://opencode.ai/zen/v1"

    def __init__(self, model: str, settings: Settings) -> None:
        super().__init__(model, settings)
        if not settings.zen_api_key:
            raise ValueError("zen_api_key is required when using the Zen provider")
        self.api_key = settings.zen_api_key

    @staticmethod
    def _detect_mime(_image: bytes) -> str:
        if _image[:4] == b"\x89PNG":
            return "image/png"
        if _image[:2] in {b"\xff\xd8", b"\xff\xd9"} or _image[6:10] in {b"JFIF", b"Exif"}:
            return "image/jpeg"
        return "image/png"

    async def analyze(self, image: bytes, prompt: str) -> AnalysisResult:
        start = time.monotonic()
        mime = self._detect_mime(image)
        b64_image = b64encode(image).decode()
        content: list[dict[str, Any]] = [
            {"type": "text", "text": prompt},
            {"type": "image_url", "image_url": {"url": f"data:{mime};base64,{b64_image}"}},
        ]
        payload = {
            "model": self.model,
            "messages": [{"role": "user", "content": content}],
            "stream": False,
        }
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
        }
        logger.debug("Calling OpenCode Zen", extra={"props": {"model": self.model, "image_size": len(image)}})
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{self.BASE_URL}/chat/completions",
                json=payload,
                headers=headers,
                timeout=120.0,
            )
            response.raise_for_status()
            data = response.json()
        elapsed = int((time.monotonic() - start) * 1000)
        content = data["choices"][0]["message"]["content"]
        logger.info("Zen analysis completed", extra={"props": {"model": self.model, "duration_ms": elapsed, "response_length": len(content)}})
        return AnalysisResult(response=content, model=self.model, processing_ms=elapsed)
