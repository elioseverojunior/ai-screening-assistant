from __future__ import annotations

import time
from base64 import b64encode

import httpx

from ai_server.config import Settings
from ai_server.logging import get_logger
from ai_server.providers.base import AnalysisProvider, AnalysisResult

logger = get_logger(__name__)


class MantleProvider(AnalysisProvider):
    def __init__(self, model: str, settings: Settings) -> None:
        super().__init__(model, settings)
        self.api_endpoint = settings.mantle_api_endpoint.rstrip("/")
        self.api_key = settings.mantle_api_key
        self.client = httpx.AsyncClient(
            timeout=httpx.Timeout(60.0, connect=10.0),
            headers={"Authorization": f"Bearer {self.api_key}"} if self.api_key else None,
        )

    async def analyze(self, image: bytes, prompt: str) -> AnalysisResult:
        start = time.monotonic()

        image_format = self._detect_image_format(image)
        b64_image = b64encode(image).decode()

        payload = {
            "model": self.model,
            "messages": [
                {
                    "role": "user",
                    "content": [
                        {"type": "image", "image": f"data:image/{image_format};base64,{b64_image}"},
                        {"type": "text", "text": prompt},
                    ],
                }
            ],
            "max_tokens": 2000,
            "temperature": 0.3,
        }

        logger.debug(
            "Calling Mantle API",
            extra={"props": {"model": self.model, "image_size": len(image), "endpoint": self.api_endpoint}},
        )

        try:
            response = await self.client.post(
                f"{self.api_endpoint}/v1/chat/completions",
                json=payload,
            )
            response.raise_for_status()
            data = response.json()
        except httpx.HTTPError as e:
            logger.error("Mantle API error", extra={"props": {"error": str(e), "model": self.model}})
            raise

        elapsed = int((time.monotonic() - start) * 1000)

        content = data.get("choices", [{}])[0].get("message", {}).get("content", "")

        logger.info(
            "Mantle analysis completed",
            extra={"props": {"model": self.model, "duration_ms": elapsed, "response_length": len(content)}},
        )

        return AnalysisResult(response=content, model=self.model, processing_ms=elapsed)

    async def close(self) -> None:
        await self.client.aclose()

    def _detect_image_format(self, image: bytes) -> str:
        if image.startswith(b"\x89PNG\r\n\x1a\n"):
            return "png"
        elif image.startswith(b"\xff\xd8\xff"):
            return "jpeg"
        elif image.startswith(b"GIF87a") or image.startswith(b"GIF89a"):
            return "gif"
        elif image.startswith(b"RIFF") and b"WEBP" in image[:12]:
            return "webp"
        return "png"